'use strict';

/**
 * Email one-time-code sign-in — the logic, kept free of Firebase wiring so it
 * can be unit-tested with fakes (see test/otp.test.js). index.js connects it
 * to Firestore, Firebase Auth and the email sender.
 *
 * Storage: one Firestore doc per email at `emailOtps/{sha256(email)}`. The
 * email itself is never the doc id, and the code is stored only as a salted
 * hash, so a leaked database doesn't leak working codes. Clients can't read
 * this collection at all (see firestore.rules); only the Admin SDK can.
 */

const crypto = require('node:crypto');

const CODE_LENGTH = 6;
const CODE_TTL_MS = 10 * 60 * 1000; // a code works for 10 minutes
const RESEND_GAP_MS = 30 * 1000; // at most one email per 30 s per address
const SEND_WINDOW_MS = 60 * 60 * 1000; // ...and at most
const MAX_SENDS_PER_WINDOW = 5; //          5 emails per hour per address
const MAX_ATTEMPTS = 5; // wrong guesses allowed per code

/** A failure the app should show to the user. `code` is an HttpsError code. */
class OtpError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

function normalizeEmail(raw) {
  const email = String(raw || '').trim().toLowerCase();
  if (email.length > 254 || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
    throw new OtpError('invalid-argument', "That email address doesn't look right.");
  }
  return email;
}

const docIdFor = (email) =>
  crypto.createHash('sha256').update(email).digest('hex');

const hashCode = (salt, code) =>
  crypto.createHash('sha256').update(`${salt}:${code}`).digest('hex');

function newCode(randomInt = crypto.randomInt) {
  return String(randomInt(0, 10 ** CODE_LENGTH)).padStart(CODE_LENGTH, '0');
}

/**
 * Generates a code, emails it, and stores its hash.
 *
 * deps: { db, sendMail(email, code), now(), randomInt? }
 */
async function sendEmailCode(rawEmail, deps) {
  const email = normalizeEmail(rawEmail);
  const now = deps.now();
  const ref = deps.db.collection('emailOtps').doc(docIdFor(email));

  const snap = await ref.get();
  const prev = snap.exists ? snap.data() : {};

  if (prev.lastSentAt && now - prev.lastSentAt < RESEND_GAP_MS) {
    const wait = Math.ceil((RESEND_GAP_MS - (now - prev.lastSentAt)) / 1000);
    throw new OtpError(
      'resource-exhausted',
      `Please wait ${wait} seconds before requesting another code.`,
    );
  }

  const windowOpen =
    prev.windowStart && now - prev.windowStart < SEND_WINDOW_MS;
  const sendCount = windowOpen ? prev.sendCount || 0 : 0;
  if (sendCount >= MAX_SENDS_PER_WINDOW) {
    throw new OtpError(
      'resource-exhausted',
      'Too many codes requested for this email. Please try again in an hour.',
    );
  }

  const code = newCode(deps.randomInt);
  const salt = crypto.randomBytes(16).toString('hex');

  // Send first: if the email fails, nothing is stored and the user isn't
  // rate-limited for an email that never arrived.
  await deps.sendMail(email, code);

  await ref.set({
    hash: hashCode(salt, code),
    salt,
    expiresAt: now + CODE_TTL_MS,
    attempts: 0,
    lastSentAt: now,
    windowStart: windowOpen ? prev.windowStart : now,
    sendCount: sendCount + 1,
  });

  return { sent: true, expiresInSeconds: CODE_TTL_MS / 1000 };
}

/**
 * Checks a code. On success, finds or creates the Firebase user for the email
 * and returns a custom token the app signs in with.
 *
 * deps: { db, auth, now() }
 */
async function verifyEmailCode(rawEmail, rawCode, deps) {
  const email = normalizeEmail(rawEmail);
  const code = String(rawCode || '').replace(/\D/g, '');
  if (code.length !== CODE_LENGTH) {
    throw new OtpError('invalid-argument', 'Enter the 6-digit code from the email.');
  }

  const ref = deps.db.collection('emailOtps').doc(docIdFor(email));

  // The transaction returns an outcome instead of throwing, because a throw
  // would roll back the attempt counter — and the counter is what stops
  // someone guessing all million codes.
  const outcome = await deps.db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const d = snap.exists ? snap.data() : null;
    if (!d || !d.hash) return { error: 'missing' };
    if (deps.now() > d.expiresAt) return { error: 'expired' };
    if ((d.attempts || 0) >= MAX_ATTEMPTS) return { error: 'locked' };

    const expected = Buffer.from(d.hash, 'hex');
    const actual = Buffer.from(hashCode(d.salt, code), 'hex');
    if (!crypto.timingSafeEqual(expected, actual)) {
      const attempts = (d.attempts || 0) + 1;
      tx.update(ref, { attempts });
      return { error: 'wrong', left: MAX_ATTEMPTS - attempts };
    }

    // Single use: clear the code but keep the send counters for rate limiting.
    tx.update(ref, { hash: null, salt: null, attempts: 0, expiresAt: 0 });
    return { ok: true };
  });

  switch (outcome.error) {
    case 'missing':
      throw new OtpError('failed-precondition', 'No active code for this email. Request a new one.');
    case 'expired':
      throw new OtpError('deadline-exceeded', 'This code has expired. Request a new one.');
    case 'locked':
      throw new OtpError('resource-exhausted', 'Too many wrong attempts. Request a new code.');
    case 'wrong':
      throw new OtpError(
        'invalid-argument',
        outcome.left > 0
          ? `That code isn't right. ${outcome.left} attempt${outcome.left === 1 ? '' : 's'} left.`
          : 'Too many wrong attempts. Request a new code.',
      );
  }

  // Same email → same account, whether it first signed up with a code or with
  // Google. A code proves the person owns the inbox, so mark it verified.
  let user;
  let isNewUser = false;
  try {
    user = await deps.auth.getUserByEmail(email);
  } catch (err) {
    if (err && err.code === 'auth/user-not-found') {
      user = await deps.auth.createUser({ email, emailVerified: true });
      isNewUser = true;
    } else {
      throw err;
    }
  }
  if (user.disabled) {
    throw new OtpError('permission-denied', 'This account has been disabled.');
  }
  if (!user.emailVerified) {
    await deps.auth.updateUser(user.uid, { emailVerified: true });
  }

  // `role: authenticated` is what Supabase reads to treat this Firebase login
  // as a signed-in user (see SUPABASE_SETUP.md). Custom-token claims are
  // copied into every ID token the app gets for this session.
  const token = await deps.auth.createCustomToken(user.uid, SUPABASE_CLAIMS);
  await ensureSupabaseRole(user.uid, deps.auth, user.customClaims);
  return { token, isNewUser };
}

/** Claims Supabase needs on every Firebase ID token. */
const SUPABASE_CLAIMS = Object.freeze({ role: 'authenticated' });

/**
 * Stores `role: authenticated` on the Firebase user permanently, so tokens
 * from any sign-in method (Google included) carry it. Merges with existing
 * custom claims instead of replacing them. Returns true when it changed
 * anything — the app then refreshes its ID token to pick the claim up.
 */
async function ensureSupabaseRole(uid, auth, knownClaims) {
  const claims =
    knownClaims !== undefined ? knownClaims || {} : (await auth.getUser(uid)).customClaims || {};
  if (claims.role === SUPABASE_CLAIMS.role) return false;
  await auth.setCustomUserClaims(uid, { ...claims, ...SUPABASE_CLAIMS });
  return true;
}

/** The email body. Plain and short so it reads well in notification previews. */
function emailContent(code) {
  const minutes = CODE_TTL_MS / 60000;
  return {
    subject: `${code} is your Home8 code`,
    text:
      `Your Home8 verification code is ${code}\n\n` +
      `It expires in ${minutes} minutes. If you didn't request it, you can ignore this email.`,
    html: `<div style="font-family:Arial,Helvetica,sans-serif;max-width:420px;margin:0 auto;padding:24px;color:#1A2B34">
  <h2 style="margin:0 0 12px">Your Home8 code</h2>
  <p style="margin:0 0 20px;color:#55666E">Enter this code in the app to continue:</p>
  <div style="font-size:34px;font-weight:bold;letter-spacing:8px;padding:16px;background:#E4F0F0;border-radius:12px;text-align:center;color:#0C7B7D">${code}</div>
  <p style="margin:20px 0 0;color:#55666E;font-size:13px">It expires in ${minutes} minutes. If you didn't request it, you can ignore this email.</p>
</div>`,
  };
}

module.exports = {
  OtpError,
  normalizeEmail,
  docIdFor,
  newCode,
  sendEmailCode,
  verifyEmailCode,
  ensureSupabaseRole,
  SUPABASE_CLAIMS,
  emailContent,
  CODE_TTL_MS,
  MAX_ATTEMPTS,
};

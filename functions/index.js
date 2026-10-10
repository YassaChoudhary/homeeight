'use strict';

/**
 * Home8 Cloud Functions.
 *
 *   sendEmailCode   { email }        → emails a 6-digit code
 *   verifyEmailCode { email, code }  → { token, isNewUser }
 *   ensureSupabaseRole {}            → { updated } — adds the claim Supabase
 *                                      needs; called by the app after any
 *                                      sign-in (Google users need it)
 *
 * The app signs in with `signInWithCustomToken(token)`. The same two calls
 * serve sign-up and login: an unknown email gets an account on first verify.
 *
 * Config (set once, see FIREBASE_SETUP.md):
 *   BREVO_API_KEY  secret  → firebase functions:secrets:set BREVO_API_KEY
 *   MAIL_FROM      param   → the verified sender address in Brevo; the CLI
 *                            asks for it on the first deploy
 */

const { initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore } = require('firebase-admin/firestore');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { defineSecret, defineString } = require('firebase-functions/params');
const logger = require('firebase-functions/logger');

const otp = require('./otp');

initializeApp();

const BREVO_API_KEY = defineSecret('BREVO_API_KEY');
const MAIL_FROM = defineString('MAIL_FROM', {
  description: 'Sender email verified in Brevo, e.g. no-reply@yourdomain.com',
});

/** Must match `_functionsRegion` in lib/state/auth_controller.dart. */
const REGION = 'europe-west1';

const options = {
  region: REGION,
  secrets: [BREVO_API_KEY],
  maxInstances: 10, // caps cost if someone hammers the endpoint
};

async function sendMail(email, code) {
  const content = otp.emailContent(code);
  const res = await fetch('https://api.brevo.com/v3/smtp/email', {
    method: 'POST',
    headers: {
      'api-key': BREVO_API_KEY.value(),
      'content-type': 'application/json',
      accept: 'application/json',
    },
    body: JSON.stringify({
      sender: { name: 'Home8', email: MAIL_FROM.value() },
      to: [{ email }],
      subject: content.subject,
      textContent: content.text,
      htmlContent: content.html,
    }),
  });
  if (!res.ok) {
    const body = await res.text().catch(() => '');
    logger.error('Brevo send failed', { status: res.status, body });
    throw new otp.OtpError(
      'unavailable',
      "We couldn't send the email right now. Please try again in a minute.",
    );
  }
}

/** Turns OtpError into the HttpsError the app reads; hides anything else. */
function toHttps(err) {
  if (err instanceof otp.OtpError) return new HttpsError(err.code, err.message);
  logger.error('Unexpected error', err);
  return new HttpsError('internal', 'Something went wrong. Please try again.');
}

exports.sendEmailCode = onCall(options, async (request) => {
  try {
    return await otp.sendEmailCode(request.data && request.data.email, {
      db: getFirestore(),
      sendMail,
      now: Date.now,
    });
  } catch (err) {
    throw toHttps(err);
  }
});

exports.verifyEmailCode = onCall(options, async (request) => {
  const data = request.data || {};
  try {
    return await otp.verifyEmailCode(data.email, data.code, {
      db: getFirestore(),
      auth: getAuth(),
      now: Date.now,
    });
  } catch (err) {
    throw toHttps(err);
  }
});

/**
 * Adds `role: authenticated` to the caller's Firebase account so Supabase
 * accepts their token as a signed-in user. Needs a signed-in caller; cheap
 * no-op when the claim is already there. No secrets needed.
 */
exports.ensureSupabaseRole = onCall({ region: REGION, maxInstances: 10 }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Sign in first.');
  }
  if (request.auth.token.role === otp.SUPABASE_CLAIMS.role) {
    return { updated: false };
  }
  try {
    const updated = await otp.ensureSupabaseRole(request.auth.uid, getAuth());
    return { updated };
  } catch (err) {
    throw toHttps(err);
  }
});

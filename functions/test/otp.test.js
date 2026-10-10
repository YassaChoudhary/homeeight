'use strict';

// Run with: npm test   (from the functions folder)
// Uses in-memory fakes for Firestore and Auth — no Firebase project needed.

const test = require('node:test');
const assert = require('node:assert/strict');
const otp = require('../otp');

function fakeDb() {
  const docs = new Map();
  const ref = (id) => ({
    id,
    async get() {
      return snap(id);
    },
    async set(data) {
      docs.set(id, { ...data });
    },
  });
  const snap = (id) => ({
    exists: docs.has(id),
    data: () => (docs.has(id) ? { ...docs.get(id) } : undefined),
  });
  return {
    docs,
    collection: () => ({ doc: ref }),
    async runTransaction(fn) {
      const writes = [];
      const result = await fn({
        get: async (r) => snap(r.id),
        update: (r, data) => writes.push([r.id, data]),
      });
      for (const [id, data] of writes) docs.set(id, { ...docs.get(id), ...data });
      return result;
    },
  };
}

function fakeAuth() {
  const users = new Map();
  let n = 0;
  return {
    users,
    async getUserByEmail(email) {
      for (const u of users.values()) if (u.email === email) return { ...u };
      const e = new Error('not found');
      e.code = 'auth/user-not-found';
      throw e;
    },
    async createUser({ email, emailVerified }) {
      const u = { uid: `u${++n}`, email, emailVerified, disabled: false };
      users.set(u.uid, u);
      return { ...u };
    },
    async updateUser(uid, patch) {
      Object.assign(users.get(uid), patch);
    },
    async createCustomToken(uid, claims) {
      this.lastTokenClaims = claims;
      return `token-for-${uid}`;
    },
    async getUser(uid) {
      return { ...users.get(uid) };
    },
    async setCustomUserClaims(uid, claims) {
      users.get(uid).customClaims = claims;
    },
  };
}

function setup() {
  let clock = 1_000_000;
  const sent = [];
  const deps = {
    db: fakeDb(),
    auth: fakeAuth(),
    now: () => clock,
    sendMail: async (email, code) => sent.push({ email, code }),
  };
  return { deps, sent, advance: (ms) => (clock += ms) };
}

test('sign-up: new email gets a code, verifies, and an account is created', async () => {
  const { deps, sent } = setup();
  await otp.sendEmailCode('  New@Example.com ', deps);
  assert.equal(sent.length, 1);
  assert.equal(sent[0].email, 'new@example.com');
  assert.match(sent[0].code, /^\d{6}$/);

  const res = await otp.verifyEmailCode('new@example.com', sent[0].code, deps);
  assert.equal(res.isNewUser, true);
  assert.equal(res.token, 'token-for-u1');
  assert.equal(deps.auth.users.get('u1').emailVerified, true);
});

test('login: existing email signs into the same account', async () => {
  const { deps, sent, advance } = setup();
  const existing = await deps.auth.createUser({ email: 'a@b.com', emailVerified: false });
  await otp.sendEmailCode('a@b.com', deps);
  const res = await otp.verifyEmailCode('a@b.com', sent[0].code, deps);
  assert.equal(res.isNewUser, false);
  assert.equal(res.token, `token-for-${existing.uid}`);
  assert.equal(deps.auth.users.get(existing.uid).emailVerified, true);

  // and again later
  advance(60_000);
  await otp.sendEmailCode('a@b.com', deps);
  const again = await otp.verifyEmailCode('a@b.com', sent[1].code, deps);
  assert.equal(again.token, `token-for-${existing.uid}`);
});

test('code is single use', async () => {
  const { deps, sent } = setup();
  await otp.sendEmailCode('a@b.com', deps);
  await otp.verifyEmailCode('a@b.com', sent[0].code, deps);
  await assert.rejects(otp.verifyEmailCode('a@b.com', sent[0].code, deps), {
    code: 'failed-precondition',
  });
});

test('wrong code counts attempts and locks after the limit', async () => {
  const { deps, sent } = setup();
  await otp.sendEmailCode('a@b.com', deps);
  const wrong = sent[0].code === '000000' ? '111111' : '000000';
  for (let i = 1; i < otp.MAX_ATTEMPTS; i++) {
    await assert.rejects(otp.verifyEmailCode('a@b.com', wrong, deps), (e) => {
      assert.equal(e.code, 'invalid-argument');
      assert.match(e.message, new RegExp(`${otp.MAX_ATTEMPTS - i} attempt`));
      return true;
    });
  }
  await assert.rejects(otp.verifyEmailCode('a@b.com', wrong, deps));
  // even the right code is refused now
  await assert.rejects(otp.verifyEmailCode('a@b.com', sent[0].code, deps), {
    code: 'resource-exhausted',
  });
});

test('expired code is refused', async () => {
  const { deps, sent, advance } = setup();
  await otp.sendEmailCode('a@b.com', deps);
  advance(otp.CODE_TTL_MS + 1);
  await assert.rejects(otp.verifyEmailCode('a@b.com', sent[0].code, deps), {
    code: 'deadline-exceeded',
  });
});

test('resend: new code replaces the old one', async () => {
  const { deps, sent, advance } = setup();
  await otp.sendEmailCode('a@b.com', deps);
  advance(31_000);
  await otp.sendEmailCode('a@b.com', deps);
  if (sent[0].code !== sent[1].code) {
    await assert.rejects(otp.verifyEmailCode('a@b.com', sent[0].code, deps));
  }
  const res = await otp.verifyEmailCode('a@b.com', sent[1].code, deps);
  assert.ok(res.token);
});

test('rate limits: 30 s gap and 5 per hour', async () => {
  const { deps, advance } = setup();
  await otp.sendEmailCode('a@b.com', deps);
  await assert.rejects(otp.sendEmailCode('a@b.com', deps), { code: 'resource-exhausted' });
  for (let i = 0; i < 4; i++) {
    advance(31_000);
    await otp.sendEmailCode('a@b.com', deps);
  }
  advance(31_000);
  await assert.rejects(otp.sendEmailCode('a@b.com', deps), /Too many codes/);
  advance(60 * 60 * 1000);
  await otp.sendEmailCode('a@b.com', deps); // window reset
});

test('failed email send stores nothing and does not rate-limit', async () => {
  const { deps } = setup();
  deps.sendMail = async () => {
    throw new otp.OtpError('unavailable', 'down');
  };
  await assert.rejects(otp.sendEmailCode('a@b.com', deps), { code: 'unavailable' });
  assert.equal(deps.db.docs.size, 0);
});

test('bad input is rejected', async () => {
  const { deps } = setup();
  await assert.rejects(otp.sendEmailCode('not-an-email', deps), { code: 'invalid-argument' });
  await assert.rejects(otp.verifyEmailCode('a@b.com', '12', deps), { code: 'invalid-argument' });
});

test('disabled account cannot sign in', async () => {
  const { deps, sent } = setup();
  const u = await deps.auth.createUser({ email: 'a@b.com', emailVerified: true });
  deps.auth.users.get(u.uid).disabled = true;
  await otp.sendEmailCode('a@b.com', deps);
  await assert.rejects(otp.verifyEmailCode('a@b.com', sent[0].code, deps), {
    code: 'permission-denied',
  });
});

test('codes are always 6 digits', () => {
  assert.equal(otp.newCode(() => 42), '000042');
  assert.equal(otp.newCode(() => 999999), '999999');
});

test('tokens and accounts get the Supabase role claim', async () => {
  const { deps, sent } = setup();
  await otp.sendEmailCode('a@b.com', deps);
  await otp.verifyEmailCode('a@b.com', sent[0].code, deps);
  assert.deepEqual(deps.auth.lastTokenClaims, { role: 'authenticated' });
  assert.equal(deps.auth.users.get('u1').customClaims.role, 'authenticated');
});

test('ensureSupabaseRole keeps existing claims and is idempotent', async () => {
  const { deps } = setup();
  const u = await deps.auth.createUser({ email: 'g@b.com', emailVerified: true });
  deps.auth.users.get(u.uid).customClaims = { admin: true };
  assert.equal(await otp.ensureSupabaseRole(u.uid, deps.auth), true);
  assert.deepEqual(deps.auth.users.get(u.uid).customClaims, { admin: true, role: 'authenticated' });
  assert.equal(await otp.ensureSupabaseRole(u.uid, deps.auth), false);
});

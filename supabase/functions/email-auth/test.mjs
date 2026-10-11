// Tests for the email-auth Edge Function. No Supabase, Firebase or Brevo needed.
//
//   node --experimental-strip-types --test supabase/functions/email-auth/test.mjs
//
// (Node 22.6+.) Covers the sign-in flows with in-memory fakes, and the real
// crypto: Firebase custom tokens and ID-token verification with a generated
// RSA key.

import test from 'node:test';
import assert from 'node:assert/strict';
import {
  createHandler, sendCode, verifyCode, ensureRoleForToken, firebaseAdmin,
  normalizeEmail, randomCode, signJwt, sha256Hex, serviceAccountFromEnv, signInWithGoogle,
} from './index.ts';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/** Same rules as the SQL functions in 20261011010000_email_otp.sql. */
function fakeRpc(clock) {
  const rows = new Map();
  const fn = async (name, args) => {
    const r = rows.get(args.p_id);
    const now = clock.now;
    if (name === 'otp_rate_check') {
      if (!r) return { ok: true };
      if (r.lastSent && now - r.lastSent < 30_000) return { ok: false, error: 'wait', wait: Math.ceil((30_000 - (now - r.lastSent)) / 1000) };
      if (r.windowStart && now - r.windowStart < 3_600_000 && r.sendCount >= 5) return { ok: false, error: 'hourly' };
      return { ok: true };
    }
    if (name === 'otp_store') {
      const fresh = !r || !r.windowStart || now - r.windowStart >= 3_600_000;
      rows.set(args.p_id, {
        code: args.p_code, expires: now + 600_000, attempts: 0, lastSent: now,
        windowStart: fresh ? now : r.windowStart, sendCount: fresh ? 1 : r.sendCount + 1,
      });
      return null;
    }
    if (name === 'otp_verify') {
      if (!r || r.code == null) return { result: 'missing' };
      if (now > r.expires) return { result: 'expired' };
      if (r.attempts >= 5) return { result: 'locked' };
      if (r.code !== args.p_code) { r.attempts++; return { result: 'wrong', left: 5 - r.attempts }; }
      r.code = null;
      return { result: 'ok' };
    }
    throw new Error(`unknown rpc ${name}`);
  };
  fn.rows = rows;
  return fn;
}

function fakeFirebase() {
  const users = new Map();
  let n = 0;
  const api = {
    users,
    async lookupByEmail(email) { for (const u of users.values()) if (u.email === email) return { ...u }; return null; },
    async lookupById(uid) { return users.has(uid) ? { ...users.get(uid) } : null; },
    async createUser(email, profile = {}) { const u = { localId: `u${++n}`, email, emailVerified: true, ...profile }; users.set(u.localId, u); return { ...u }; },
    async updateUser(uid, patch) { Object.assign(users.get(uid), patch); },
    async createCustomToken(uid, claims) { api.lastClaims = claims; return `token-for-${uid}`; },
    async verifyGoogleIdToken(t) {
      if (!t.startsWith('google:')) throw new Error('bad google token');
      const [, email, name] = t.split(':');
      return { email, name, picture: name ? `https://pic/${name}` : undefined };
    },
    async verifyIdToken(t) {
      if (!t.startsWith('valid:')) throw new Error('bad');
      const uid = t.split(':')[1];
      return { uid, claims: JSON.parse(users.get(uid)?.customAttributes ?? '{}') };
    },
  };
  return api;
}

function setup() {
  const clock = { now: 1_000_000_000 };
  const sent = [];
  const deps = {
    rpc: fakeRpc(clock),
    sendMail: async (email, code) => { sent.push({ email, code }); },
    firebase: fakeFirebase(),
  };
  return { deps, sent, clock };
}

const fb = (deps) => deps.firebase;

// ---------------------------------------------------------------------------
// Flows
// ---------------------------------------------------------------------------

test('sign-up: new email → code → account created, verified, with Supabase role', async () => {
  const { deps, sent } = setup();
  await sendCode(deps, '  New@Example.com ');
  assert.equal(sent[0].email, 'new@example.com');
  assert.match(sent[0].code, /^\d{6}$/);
  const res = await verifyCode(deps, 'new@example.com', sent[0].code);
  assert.deepEqual(res, { token: 'token-for-u1', isNewUser: true });
  assert.deepEqual(fb(deps).lastClaims, { role: 'authenticated' });
  assert.equal(JSON.parse(fb(deps).users.get('u1').customAttributes).role, 'authenticated');
});

test('login: existing (e.g. Google) account → same uid, email marked verified, claims merged', async () => {
  const { deps, sent } = setup();
  fb(deps).users.set('g1', { localId: 'g1', email: 'a@b.com', emailVerified: false, customAttributes: '{"admin":true}' });
  await sendCode(deps, 'a@b.com');
  const res = await verifyCode(deps, 'a@b.com', sent[0].code);
  assert.deepEqual(res, { token: 'token-for-g1', isNewUser: false });
  const u = fb(deps).users.get('g1');
  assert.equal(u.emailVerified, true);
  assert.deepEqual(JSON.parse(u.customAttributes), { admin: true, role: 'authenticated' });
});

test('wrong code counts down, then locks', async () => {
  const { deps, sent } = setup();
  await sendCode(deps, 'a@b.com');
  const wrong = sent[0].code === '000000' ? '111111' : '000000';
  for (const left of [4, 3, 2, 1]) {
    await assert.rejects(verifyCode(deps, 'a@b.com', wrong), (e) => e.code === 'wrong-code' && e.message.includes(`${left} attempt`));
  }
  await assert.rejects(verifyCode(deps, 'a@b.com', wrong), /Too many wrong attempts/);
  await assert.rejects(verifyCode(deps, 'a@b.com', sent[0].code), (e) => e.code === 'locked' && e.status === 429);
});

test('code is single use; expired code refused', async () => {
  const { deps, sent, clock } = setup();
  await sendCode(deps, 'a@b.com');
  await verifyCode(deps, 'a@b.com', sent[0].code);
  await assert.rejects(verifyCode(deps, 'a@b.com', sent[0].code), (e) => e.code === 'no-code');
  clock.now += 31_000;
  await sendCode(deps, 'a@b.com');
  clock.now += 601_000;
  await assert.rejects(verifyCode(deps, 'a@b.com', sent[1].code), (e) => e.code === 'expired');
});

test('rate limits: 30 s gap and 5 per hour', async () => {
  const { deps, clock } = setup();
  await sendCode(deps, 'a@b.com');
  await assert.rejects(sendCode(deps, 'a@b.com'), (e) => e.status === 429 && /wait \d+ seconds/.test(e.message));
  for (let i = 0; i < 4; i++) { clock.now += 31_000; await sendCode(deps, 'a@b.com'); }
  clock.now += 31_000;
  await assert.rejects(sendCode(deps, 'a@b.com'), /in an hour/);
});

test('failed email stores nothing and does not count', async () => {
  const { deps } = setup();
  deps.sendMail = async () => { throw new Error('brevo down'); };
  await assert.rejects(sendCode(deps, 'a@b.com'));
  assert.equal(deps.rpc.rows.size, 0);
});

test('disabled account cannot sign in', async () => {
  const { deps, sent } = setup();
  fb(deps).users.set('d1', { localId: 'd1', email: 'a@b.com', emailVerified: true, disabled: true });
  await sendCode(deps, 'a@b.com');
  await assert.rejects(verifyCode(deps, 'a@b.com', sent[0].code), (e) => e.status === 403);
});

test('ensure-role: adds claim once for a Google user; rejects bad tokens', async () => {
  const { deps } = setup();
  fb(deps).users.set('g1', { localId: 'g1', email: 'g@b.com' });
  const token = 'valid:g1:' + 'x'.repeat(40); // real ID tokens are ~900 chars
  assert.deepEqual(await ensureRoleForToken(deps, token), { updated: true });
  assert.equal(JSON.parse(fb(deps).users.get('g1').customAttributes).role, 'authenticated');
  assert.deepEqual(await ensureRoleForToken(deps, token), { updated: false });
  await assert.rejects(ensureRoleForToken(deps, 'not-a-valid-token-at-all'), (e) => e.status === 401);
  await assert.rejects(ensureRoleForToken(deps, undefined), (e) => e.status === 401);
});

test('input validation', async () => {
  const { deps } = setup();
  assert.throws(() => normalizeEmail('nope'), (e) => e.code === 'invalid-email');
  await assert.rejects(verifyCode(deps, 'a@b.com', '12'), (e) => e.code === 'invalid-code');
  for (let i = 0; i < 200; i++) assert.match(randomCode(), /^\d{6}$/);
  assert.equal(await sha256Hex('abc'), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
});

test('HTTP handler: statuses and error bodies', async () => {
  const { deps, sent } = setup();
  const handle = createHandler(() => deps);
  const post = (body) => handle(new Request('http://x/email-auth', { method: 'POST', body: JSON.stringify(body) }));

  let res = await post({ action: 'send', email: 'a@b.com' });
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { sent: true, expiresInSeconds: 600 });

  res = await post({ action: 'verify', email: 'a@b.com', code: '999999' === sent[0].code ? '000000' : '999999' });
  assert.equal(res.status, 400);
  assert.equal((await res.json()).error.code, 'wrong-code');

  res = await post({ action: 'verify', email: 'a@b.com', code: sent[0].code });
  assert.equal(res.status, 200);
  assert.ok((await res.json()).token);

  res = await post({ action: 'nope' });
  assert.equal(res.status, 400);
  res = await handle(new Request('http://x', { method: 'OPTIONS' }));
  assert.equal(res.status, 200);
  res = await handle(new Request('http://x', { method: 'GET' }));
  assert.equal(res.status, 405);

  deps.rpc = async () => { throw new Error('db down'); };
  res = await post({ action: 'send', email: 'b@b.com' });
  assert.equal(res.status, 500);
  assert.equal((await res.json()).error.code, 'internal');
});

// ---------------------------------------------------------------------------
// Real crypto + Google endpoints (faked fetch)
// ---------------------------------------------------------------------------

async function rsaKeys() {
  const pair = await crypto.subtle.generateKey(
    { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' },
    true, ['sign', 'verify']);
  const pkcs8 = new Uint8Array(await crypto.subtle.exportKey('pkcs8', pair.privateKey));
  const b64 = Buffer.from(pkcs8).toString('base64').match(/.{1,64}/g).join('\n');
  // As in the downloaded JSON: newlines escaped as \n inside the string.
  const pem = `-----BEGIN PRIVATE KEY-----\\n${b64.replace(/\n/g, '\\n')}\\n-----END PRIVATE KEY-----\\n`;
  const jwk = await crypto.subtle.exportKey('jwk', pair.publicKey);
  return { pair, pem, jwk };
}

const decode = (jwt) => jwt.split('.').slice(0, 2).map((p) => JSON.parse(Buffer.from(p, 'base64url').toString()));

test('custom token: RS256, signed by the service account, carries uid + claims', async () => {
  const { pair, pem } = await rsaKeys();
  const sa = { project_id: 'home8-61d48', client_email: 'sa@home8-61d48.iam.gserviceaccount.com', private_key: pem };
  const admin = firebaseAdmin(sa, async () => { throw new Error('no network'); }, () => 1_700_000_000_000);
  const token = await admin.createCustomToken('uid123', { role: 'authenticated' });
  const [header, payload] = decode(token);
  assert.equal(header.alg, 'RS256');
  assert.equal(payload.iss, sa.client_email);
  assert.equal(payload.sub, sa.client_email);
  assert.equal(payload.aud, 'https://identitytoolkit.googleapis.com/google.identity.identitytoolkit.v1.IdentityToolkit');
  assert.equal(payload.uid, 'uid123');
  assert.deepEqual(payload.claims, { role: 'authenticated' });
  assert.equal(payload.exp - payload.iat, 3600);
  const [h, p, s] = token.split('.');
  assert.ok(await crypto.subtle.verify('RSASSA-PKCS1-v1_5', pair.publicKey, Buffer.from(s, 'base64url'), new TextEncoder().encode(`${h}.${p}`)));
});

test('ID token verification: accepts valid, rejects wrong project / expired / tampered', async () => {
  const google = await rsaKeys(); // plays Google's securetoken key
  const { pem } = await rsaKeys();
  const sa = { project_id: 'home8-61d48', client_email: 'sa@x', private_key: pem };
  const now = 1_700_000_000_000;
  const fetchFn = async (url) => {
    assert.match(String(url), /securetoken@system\.gserviceaccount\.com/);
    return new Response(JSON.stringify({ keys: [{ ...google.jwk, kid: 'k1' }] }), { headers: { 'cache-control': 'max-age=600' } });
  };
  const admin = firebaseAdmin(sa, fetchFn, () => now);
  const t = Math.floor(now / 1000);
  const base = { iss: 'https://securetoken.google.com/home8-61d48', aud: 'home8-61d48', sub: 'g1', iat: t - 10, exp: t + 3000 };
  const sign = (payload) => signJwt(payload, google.pair.privateKey, 'k1');

  const ok = await admin.verifyIdToken(await sign(base));
  assert.equal(ok.uid, 'g1');
  await assert.rejects(admin.verifyIdToken(await sign({ ...base, aud: 'evil-proj' })), /aud/);
  await assert.rejects(admin.verifyIdToken(await sign({ ...base, iss: 'https://securetoken.google.com/evil' })), /iss/);
  await assert.rejects(admin.verifyIdToken(await sign({ ...base, exp: t - 1 })), /time/);
  const good = await sign(base);
  const [h, , s] = good.split('.');
  const forged = `${h}.${Buffer.from(JSON.stringify({ ...base, sub: 'victim' })).toString('base64url')}.${s}`;
  await assert.rejects(admin.verifyIdToken(forged), /signature/);
  const other = await rsaKeys();
  await assert.rejects(admin.verifyIdToken(await signJwt(base, other.pair.privateKey, 'k1')), /signature/);
});

test('Identity Toolkit calls: OAuth token cached, correct URLs and bodies', async () => {
  const { pem } = await rsaKeys();
  const sa = { project_id: 'home8-61d48', client_email: 'sa@x', private_key: pem, private_key_id: 'kid9' };
  const calls = [];
  const fetchFn = async (url, init) => {
    calls.push({ url: String(url), init });
    if (String(url) === 'https://oauth2.googleapis.com/token') {
      const assertion = new URLSearchParams(init.body).get('assertion');
      const [hdr, payload] = decode(assertion);
      assert.equal(hdr.kid, 'kid9');
      assert.equal(payload.aud, 'https://oauth2.googleapis.com/token');
      assert.match(payload.scope, /identitytoolkit/);
      return new Response(JSON.stringify({ access_token: 'AT', expires_in: 3599 }));
    }
    assert.equal(init.headers.Authorization, 'Bearer AT');
    if (String(url).endsWith('/accounts:lookup')) return new Response(JSON.stringify({ users: [{ localId: 'u1', email: 'a@b.com' }] }));
    if (String(url).endsWith('/accounts')) return new Response(JSON.stringify({ localId: 'new1' }));
    if (String(url).endsWith('/accounts:update')) return new Response('{}');
    throw new Error(`unexpected ${url}`);
  };
  const admin = firebaseAdmin(sa, fetchFn, () => 1_700_000_000_000);
  assert.equal((await admin.lookupByEmail('a@b.com')).localId, 'u1');
  assert.equal((await admin.createUser('n@b.com')).localId, 'new1');
  await admin.updateUser('u1', { customAttributes: '{"role":"authenticated"}' });
  const tokenCalls = calls.filter((c) => c.url.includes('oauth2'));
  assert.equal(tokenCalls.length, 1, 'access token reused');
  const urls = calls.filter((c) => !c.url.includes('oauth2')).map((c) => c.url);
  assert.deepEqual(urls, [
    'https://identitytoolkit.googleapis.com/v1/projects/home8-61d48/accounts:lookup',
    'https://identitytoolkit.googleapis.com/v1/projects/home8-61d48/accounts',
    'https://identitytoolkit.googleapis.com/v1/projects/home8-61d48/accounts:update',
  ]);
  assert.deepEqual(JSON.parse(calls[1].init.body), { email: ['a@b.com'] });
  assert.deepEqual(JSON.parse(calls[2].init.body), { email: 'n@b.com', emailVerified: true });
  assert.deepEqual(JSON.parse(calls[3].init.body), { localId: 'u1', customAttributes: '{"role":"authenticated"}' });
});

test('service account secret: one-line JSON, base64, separate secrets; clear error when mangled', () => {
  const sa = { type: 'service_account', project_id: 'home8-61d48', client_email: 'sa@x.iam.gserviceaccount.com',
    private_key: '-----BEGIN PRIVATE KEY-----\nABC\n-----END PRIVATE KEY-----\n' };
  const env = (o) => (n) => o[n];
  assert.equal(serviceAccountFromEnv(env({ FIREBASE_SERVICE_ACCOUNT: JSON.stringify(sa) })).project_id, 'home8-61d48');
  assert.equal(serviceAccountFromEnv(env({ FIREBASE_SERVICE_ACCOUNT: JSON.stringify(sa, null, 2) })).client_email, sa.client_email);
  assert.equal(serviceAccountFromEnv(env({ FIREBASE_SERVICE_ACCOUNT: Buffer.from(JSON.stringify(sa)).toString('base64') })).project_id, 'home8-61d48');
  const sep = serviceAccountFromEnv(env({ FIREBASE_PROJECT_ID: 'home8-61d48', FIREBASE_CLIENT_EMAIL: sa.client_email,
    FIREBASE_PRIVATE_KEY: '"' + sa.private_key + '"' }));
  assert.ok(sep.private_key.startsWith('-----BEGIN'));
  // what the dashboard produced from a multi-line paste:
  assert.throws(() => serviceAccountFromEnv(env({ FIREBASE_SERVICE_ACCOUNT: '\t\ntype\t"service_account"' })), /ONE line/);
});

// ---------------------------------------------------------------------------
// One account per email, across email code and Google
// ---------------------------------------------------------------------------

const gtoken = (email, name = '') => `google:${email}:${name}:${'_'.repeat(30)}`;

test('email code first, then Google → SAME account; Google fills missing name/photo', async () => {
  const { deps, sent } = setup();
  await sendCode(deps, 'yassa@gmail.com');
  const first = await verifyCode(deps, 'yassa@gmail.com', sent[0].code);
  assert.equal(first.isNewUser, true);
  const second = await signInWithGoogle(deps, gtoken('Yassa@Gmail.com', 'Yassa'));
  assert.equal(second.token, first.token, 'same uid → same token');
  assert.equal(second.isNewUser, false);
  assert.equal(fb(deps).users.size, 1, 'no second account');
  const u = fb(deps).users.get('u1');
  assert.equal(u.displayName, 'Yassa');
  assert.equal(u.photoUrl, 'https://pic/Yassa');
});

test('Google first, then email code → SAME account', async () => {
  const { deps, sent } = setup();
  const g = await signInWithGoogle(deps, gtoken('a@b.com', 'Ali'));
  assert.equal(g.isNewUser, true);
  assert.equal(fb(deps).users.get('u1').displayName, 'Ali');
  await sendCode(deps, 'a@b.com');
  const e = await verifyCode(deps, 'a@b.com', sent[0].code);
  assert.equal(e.token, g.token);
  assert.equal(e.isNewUser, false);
  assert.equal(fb(deps).users.size, 1);
});

test('Google never overwrites a name/photo the user set; claims include Supabase role', async () => {
  const { deps } = setup();
  fb(deps).users.set('k1', { localId: 'k1', email: 'k@b.com', emailVerified: true, displayName: 'My Name', photoUrl: 'mine.jpg' });
  await signInWithGoogle(deps, gtoken('k@b.com', 'Google Name'));
  const u = fb(deps).users.get('k1');
  assert.equal(u.displayName, 'My Name');
  assert.equal(u.photoUrl, 'mine.jpg');
  assert.deepEqual(fb(deps).lastClaims, { role: 'authenticated' });
});

test('bad Google tokens are refused with 401; HTTP action "google" works', async () => {
  const { deps } = setup();
  await assert.rejects(signInWithGoogle(deps, 'not-google-token-xxxxxxxxxxxxxxxxxxxx'), (e) => e.status === 401);
  await assert.rejects(signInWithGoogle(deps, 'short'), (e) => e.status === 400);
  const handle = createHandler(() => deps);
  const res = await handle(new Request('http://x', { method: 'POST', body: JSON.stringify({ action: 'google', idToken: gtoken('h@b.com') }) }));
  assert.equal(res.status, 200);
  assert.equal((await res.json()).isNewUser, true);
});

test('Google ID token verification (real crypto): aud, iss, email_verified, expiry, signature', async () => {
  const google = await rsaKeys();
  const { pem } = await rsaKeys();
  const sa = { project_id: 'home8-61d48', client_email: 'sa@x', private_key: pem };
  const now = 1_700_000_000_000;
  const fetchFn = async (url) => {
    assert.equal(String(url), 'https://www.googleapis.com/oauth2/v3/certs');
    return new Response(JSON.stringify({ keys: [{ ...google.jwk, kid: 'g1' }] }));
  };
  const admin = firebaseAdmin(sa, fetchFn, () => now);
  const t = Math.floor(now / 1000);
  const aud = '515552573780-1iddeggktedl30hiuc87vr8rkdkrlj13.apps.googleusercontent.com';
  const base = { iss: 'https://accounts.google.com', aud, sub: '1234', email: 'p@gmail.com', email_verified: true,
    name: 'P', picture: 'https://lh3/p', iat: t - 5, exp: t + 3000 };
  const sign = (p) => signJwt(p, google.pair.privateKey, 'g1');
  assert.deepEqual(await admin.verifyGoogleIdToken(await sign(base)), { email: 'p@gmail.com', name: 'P', picture: 'https://lh3/p' });
  assert.equal((await admin.verifyGoogleIdToken(await sign({ ...base, iss: 'accounts.google.com' }))).email, 'p@gmail.com');
  await assert.rejects(admin.verifyGoogleIdToken(await sign({ ...base, aud: 'someone-elses-app.apps.googleusercontent.com' })), /aud/);
  await assert.rejects(admin.verifyGoogleIdToken(await sign({ ...base, iss: 'https://evil.com' })), /iss/);
  await assert.rejects(admin.verifyGoogleIdToken(await sign({ ...base, email_verified: false })), /not verified/);
  await assert.rejects(admin.verifyGoogleIdToken(await sign({ ...base, exp: t - 1 })), /time/);
  const other = await rsaKeys();
  await assert.rejects(admin.verifyGoogleIdToken(await signJwt(base, other.pair.privateKey, 'g1')), /signature/);
});

test('lookupByEmail: if duplicates exist, the OLDEST account is used', async () => {
  const { pem } = await rsaKeys();
  const sa = { project_id: 'home8-61d48', client_email: 'sa@x', private_key: pem };
  const fetchFn = async (url) => {
    if (String(url).includes('oauth2.googleapis.com/token')) return new Response(JSON.stringify({ access_token: 'AT', expires_in: 3600 }));
    return new Response(JSON.stringify({ users: [
      { localId: 'googleDup', email: 'a@b.com', createdAt: '1791665900000' },
      { localId: 'emailFirst', email: 'a@b.com', createdAt: '1791665800000' },
    ] }));
  };
  const admin = firebaseAdmin(sa, fetchFn, () => 1_700_000_000_000);
  assert.equal((await admin.lookupByEmail('a@b.com')).localId, 'emailFirst');
});

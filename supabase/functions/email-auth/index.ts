// =============================================================================
// Home8 — `email-auth` Supabase Edge Function (free plan, no Firebase billing).
//
// One function, three actions (POST JSON body):
//   { "action": "send",        "email": "a@b.com" }                 → { sent: true }
//   { "action": "verify",      "email": "a@b.com", "code": "123456" } → { token, isNewUser }
//   { "action": "ensure-role", "idToken": "<Firebase ID token>" }    → { updated }
//
// "verify" returns a Firebase custom token; the app signs in with
// FirebaseAuth.signInWithCustomToken(token). Google login stays 100% Firebase —
// "ensure-role" only adds the `role: authenticated` claim Supabase needs.
//
// Secrets (Supabase dashboard → Edge Functions → Secrets):
//   FIREBASE_SERVICE_ACCOUNT  the whole JSON from Firebase → Project settings →
//                             Service accounts → Generate new private key
//   BREVO_API_KEY             Brevo → SMTP & API → API keys
//   MAIL_FROM                 sender address verified in Brevo
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided automatically.
//
// Deploy with "Verify JWT" OFF (the app calls it before anyone is signed in).
// Code storage, rate limits and attempt counting live in SQL:
// supabase/migrations/20261011010000_email_otp.sql.
//
// Only web-standard APIs are used (fetch, crypto.subtle), so the same file is
// unit-tested in Node: supabase/functions/email-auth/test.mjs
// =============================================================================

// Deno's global, read via globalThis so this file also loads in Node for tests
// (and doesn't redeclare Deno's own type).
// deno-lint-ignore no-explicit-any
const DenoGlobal: any = (globalThis as any).Deno;

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface FirebaseUser {
  localId: string;
  email?: string;
  emailVerified?: boolean;
  disabled?: boolean;
  customAttributes?: string; // JSON string, as the Identity Toolkit returns it
}

export interface Deps {
  rpc: (fn: string, args: Record<string, unknown>) => Promise<any>;
  sendMail: (email: string, code: string) => Promise<void>;
  firebase: {
    lookupByEmail: (email: string) => Promise<FirebaseUser | null>;
    lookupById: (uid: string) => Promise<FirebaseUser | null>;
    createUser: (email: string) => Promise<FirebaseUser>;
    updateUser: (uid: string, patch: { emailVerified?: boolean; customAttributes?: string }) => Promise<void>;
    createCustomToken: (uid: string, claims: Record<string, unknown>) => Promise<string>;
    verifyIdToken: (idToken: string) => Promise<{ uid: string; claims: Record<string, unknown> }>;
  };
  newCode?: () => string;
}

export class AuthError extends Error {
  status: number;
  code: string;
  constructor(status: number, code: string, message: string) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

export const SUPABASE_CLAIMS = { role: 'authenticated' } as const;

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

export function normalizeEmail(raw: unknown): string {
  const email = String(raw ?? '').trim().toLowerCase();
  if (email.length > 254 || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
    throw new AuthError(400, 'invalid-email', "That email address doesn't look right.");
  }
  return email;
}

export async function sha256Hex(text: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

/** Uniform 6-digit code (rejection sampling avoids modulo bias). */
export function randomCode(): string {
  const buf = new Uint32Array(1);
  const limit = Math.floor(0xffffffff / 1_000_000) * 1_000_000;
  do {
    crypto.getRandomValues(buf);
  } while (buf[0] >= limit);
  return String(buf[0] % 1_000_000).padStart(6, '0');
}

function parseClaims(user: FirebaseUser): Record<string, unknown> {
  try {
    return user.customAttributes ? JSON.parse(user.customAttributes) : {};
  } catch {
    return {};
  }
}

/** Adds role: authenticated to the user's stored claims. True if it changed. */
async function ensureRole(deps: Deps, user: FirebaseUser): Promise<boolean> {
  const claims = parseClaims(user);
  if (claims.role === SUPABASE_CLAIMS.role) return false;
  await deps.firebase.updateUser(user.localId, {
    customAttributes: JSON.stringify({ ...claims, ...SUPABASE_CLAIMS }),
  });
  return true;
}

// ---------------------------------------------------------------------------
// Actions
// ---------------------------------------------------------------------------

export async function sendCode(deps: Deps, rawEmail: unknown) {
  const email = normalizeEmail(rawEmail);
  const id = await sha256Hex(email);

  const check = await deps.rpc('otp_rate_check', { p_id: id });
  if (!check?.ok) {
    if (check?.error === 'hourly') {
      throw new AuthError(429, 'rate-limited',
        'Too many codes requested for this email. Please try again in an hour.');
    }
    throw new AuthError(429, 'rate-limited',
      `Please wait ${check?.wait ?? 30} seconds before requesting another code.`);
  }

  const code = (deps.newCode ?? randomCode)();
  // Send first: if the email fails, nothing is stored and the user isn't
  // rate-limited for an email that never arrived.
  await deps.sendMail(email, code);
  await deps.rpc('otp_store', { p_id: id, p_code: code });
  return { sent: true, expiresInSeconds: 600 };
}

export async function verifyCode(deps: Deps, rawEmail: unknown, rawCode: unknown) {
  const email = normalizeEmail(rawEmail);
  const code = String(rawCode ?? '').replace(/\D/g, '');
  if (code.length !== 6) {
    throw new AuthError(400, 'invalid-code', 'Enter the 6-digit code from the email.');
  }

  const outcome = await deps.rpc('otp_verify', { p_id: await sha256Hex(email), p_code: code });
  switch (outcome?.result) {
    case 'ok':
      break;
    case 'expired':
      throw new AuthError(400, 'expired', 'This code has expired. Request a new one.');
    case 'locked':
      throw new AuthError(429, 'locked', 'Too many wrong attempts. Request a new code.');
    case 'wrong': {
      const left = Number(outcome.left ?? 0);
      throw new AuthError(400, 'wrong-code', left > 0
        ? `That code isn't right. ${left} attempt${left === 1 ? '' : 's'} left.`
        : 'Too many wrong attempts. Request a new code.');
    }
    default:
      throw new AuthError(400, 'no-code', 'No active code for this email. Request a new one.');
  }

  // Same email → same account, whether it first signed up with a code or Google.
  let user = await deps.firebase.lookupByEmail(email);
  let isNewUser = false;
  if (!user) {
    user = await deps.firebase.createUser(email);
    isNewUser = true;
  }
  if (user.disabled) {
    throw new AuthError(403, 'disabled', 'This account has been disabled.');
  }
  if (!user.emailVerified) {
    // A code proves the person owns the inbox.
    await deps.firebase.updateUser(user.localId, { emailVerified: true });
  }
  await ensureRole(deps, user);

  const token = await deps.firebase.createCustomToken(user.localId, { ...SUPABASE_CLAIMS });
  return { token, isNewUser };
}

export async function ensureRoleForToken(deps: Deps, idToken: unknown) {
  if (typeof idToken !== 'string' || idToken.length < 20) {
    throw new AuthError(401, 'unauthenticated', 'Sign in first.');
  }
  let verified;
  try {
    verified = await deps.firebase.verifyIdToken(idToken);
  } catch {
    throw new AuthError(401, 'unauthenticated', 'Your session has expired. Please sign in again.');
  }
  if (verified.claims.role === SUPABASE_CLAIMS.role) return { updated: false };
  const user = await deps.firebase.lookupById(verified.uid);
  if (!user) throw new AuthError(401, 'unauthenticated', 'Account not found.');
  return { updated: await ensureRole(deps, user) };
}

// ---------------------------------------------------------------------------
// HTTP
// ---------------------------------------------------------------------------

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  });
}

export function createHandler(getDeps: () => Deps) {
  return async (req: Request): Promise<Response> => {
    if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
    if (req.method !== 'POST') return json(405, { error: { code: 'method', message: 'POST only' } });
    try {
      const body = await req.json().catch(() => ({}));
      const deps = getDeps();
      switch (body?.action) {
        case 'send':
          return json(200, await sendCode(deps, body.email));
        case 'verify':
          return json(200, await verifyCode(deps, body.email, body.code));
        case 'ensure-role':
          return json(200, await ensureRoleForToken(deps, body.idToken));
        default:
          return json(400, { error: { code: 'bad-action', message: 'Unknown action.' } });
      }
    } catch (err) {
      if (err instanceof AuthError) {
        return json(err.status, { error: { code: err.code, message: err.message } });
      }
      console.error('email-auth failed:', err);
      return json(500, { error: { code: 'internal', message: 'Something went wrong. Please try again.' } });
    }
  };
}

// ---------------------------------------------------------------------------
// Real dependencies: Supabase RPC, Brevo, Firebase (Identity Toolkit REST)
// ---------------------------------------------------------------------------

const b64url = (bytes: Uint8Array) =>
  btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const b64urlJson = (obj: unknown) => b64url(new TextEncoder().encode(JSON.stringify(obj)));
const b64urlDecode = (s: string) =>
  Uint8Array.from(atob(s.replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((s.length + 3) % 4)), (c) => c.charCodeAt(0));

export async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const body = pem.replace(/\\n/g, '\n').replace(/-----[^-]+-----/g, '').replace(/\s+/g, '');
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey('pkcs8', der, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
}

export async function signJwt(payload: Record<string, unknown>, key: CryptoKey, kid?: string): Promise<string> {
  const header = { alg: 'RS256', typ: 'JWT', ...(kid ? { kid } : {}) };
  const input = `${b64urlJson(header)}.${b64urlJson(payload)}`;
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(input));
  return `${input}.${b64url(new Uint8Array(sig))}`;
}

export interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
  private_key_id?: string;
}

const CUSTOM_TOKEN_AUD =
  'https://identitytoolkit.googleapis.com/google.identity.identitytoolkit.v1.IdentityToolkit';
const SECURETOKEN_JWKS =
  'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com';

export function firebaseAdmin(sa: ServiceAccount, fetchFn: typeof fetch = fetch, now = () => Date.now()) {
  let keyPromise: Promise<CryptoKey> | null = null;
  const key = () => (keyPromise ??= importPrivateKey(sa.private_key));
  let access: { token: string; exp: number } | null = null;
  let jwks: { keys: Record<string, CryptoKey>; exp: number } | null = null;
  const base = `https://identitytoolkit.googleapis.com/v1/projects/${sa.project_id}`;

  async function accessToken(): Promise<string> {
    const t = Math.floor(now() / 1000);
    if (access && access.exp - 60 > t) return access.token;
    const assertion = await signJwt({
      iss: sa.client_email,
      scope: 'https://www.googleapis.com/auth/identitytoolkit https://www.googleapis.com/auth/cloud-platform',
      aud: 'https://oauth2.googleapis.com/token',
      iat: t,
      exp: t + 3600,
    }, await key(), sa.private_key_id);
    const res = await fetchFn('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: `grant_type=${encodeURIComponent('urn:ietf:params:oauth:grant-type:jwt-bearer')}&assertion=${assertion}`,
    });
    if (!res.ok) throw new Error(`Google token ${res.status}: ${await res.text()}`);
    const data = await res.json();
    access = { token: data.access_token, exp: t + Number(data.expires_in ?? 3600) };
    return access.token;
  }

  async function call(path: string, body: unknown) {
    const res = await fetchFn(`${base}${path}`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${await accessToken()}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    if (!res.ok) throw new Error(`Identity Toolkit ${path} ${res.status}: ${await res.text()}`);
    return res.json();
  }

  async function lookup(body: unknown): Promise<FirebaseUser | null> {
    const data = await call('/accounts:lookup', body);
    return data?.users?.[0] ?? null;
  }

  async function signingKeys(): Promise<Record<string, CryptoKey>> {
    if (jwks && jwks.exp > now()) return jwks.keys;
    const res = await fetchFn(SECURETOKEN_JWKS);
    if (!res.ok) throw new Error(`JWKS ${res.status}`);
    const data = await res.json();
    const keys: Record<string, CryptoKey> = {};
    for (const k of data.keys ?? []) {
      keys[k.kid] = await crypto.subtle.importKey(
        'jwk', { kty: k.kty, n: k.n, e: k.e, alg: 'RS256', ext: true },
        { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify']);
    }
    const maxAge = Number(/max-age=(\d+)/.exec(res.headers.get('cache-control') ?? '')?.[1] ?? 3600);
    jwks = { keys, exp: now() + maxAge * 1000 };
    return keys;
  }

  return {
    lookupByEmail: (email: string) => lookup({ email: [email] }),
    lookupById: (uid: string) => lookup({ localId: [uid] }),
    async createUser(email: string): Promise<FirebaseUser> {
      const data = await call('/accounts', { email, emailVerified: true });
      return { localId: data.localId, email, emailVerified: true };
    },
    async updateUser(uid: string, patch: { emailVerified?: boolean; customAttributes?: string }) {
      await call('/accounts:update', { localId: uid, ...patch });
    },
    async createCustomToken(uid: string, claims: Record<string, unknown>) {
      const t = Math.floor(now() / 1000);
      return signJwt({
        iss: sa.client_email, sub: sa.client_email, aud: CUSTOM_TOKEN_AUD,
        iat: t, exp: t + 3600, uid, claims,
      }, await key());
    },
    async verifyIdToken(idToken: string) {
      const [h, p, s] = idToken.split('.');
      if (!h || !p || !s) throw new Error('malformed');
      const header = JSON.parse(new TextDecoder().decode(b64urlDecode(h)));
      const payload = JSON.parse(new TextDecoder().decode(b64urlDecode(p)));
      if (header.alg !== 'RS256') throw new Error('alg');
      const k = (await signingKeys())[header.kid];
      if (!k) throw new Error('kid');
      const ok = await crypto.subtle.verify('RSASSA-PKCS1-v1_5', k, b64urlDecode(s),
        new TextEncoder().encode(`${h}.${p}`));
      const t = Math.floor(now() / 1000);
      if (!ok) throw new Error('signature');
      if (payload.iss !== `https://securetoken.google.com/${sa.project_id}`) throw new Error('iss');
      if (payload.aud !== sa.project_id) throw new Error('aud');
      if (typeof payload.sub !== 'string' || !payload.sub) throw new Error('sub');
      if (payload.exp <= t || payload.iat > t + 300) throw new Error('time');
      return { uid: payload.sub, claims: payload };
    },
  };
}

function supabaseRpc(url: string, key: string, fetchFn: typeof fetch = fetch) {
  return async (fn: string, args: Record<string, unknown>) => {
    const headers: Record<string, string> = { apikey: key, 'Content-Type': 'application/json' };
    if (key.startsWith('eyJ')) headers.Authorization = `Bearer ${key}`;
    const res = await fetchFn(`${url}/rest/v1/rpc/${fn}`, {
      method: 'POST', headers, body: JSON.stringify(args),
    });
    if (!res.ok) throw new Error(`rpc ${fn} ${res.status}: ${await res.text()}`);
    const text = await res.text();
    return text ? JSON.parse(text) : null;
  };
}

export function emailContent(code: string) {
  return {
    subject: `${code} is your Home8 code`,
    text: `Your Home8 verification code is ${code}\n\nIt expires in 10 minutes. ` +
      `If you didn't request it, you can ignore this email.`,
    html: `<div style="font-family:Arial,Helvetica,sans-serif;max-width:420px;margin:0 auto;padding:24px;color:#1A2B34">
  <h2 style="margin:0 0 12px">Your Home8 code</h2>
  <p style="margin:0 0 20px;color:#55666E">Enter this code in the app to continue:</p>
  <div style="font-size:34px;font-weight:bold;letter-spacing:8px;padding:16px;background:#E4F0F0;border-radius:12px;text-align:center;color:#0C7B7D">${code}</div>
  <p style="margin:20px 0 0;color:#55666E;font-size:13px">It expires in 10 minutes. If you didn't request it, you can ignore this email.</p>
</div>`,
  };
}

function brevoSender(apiKey: string, from: string, fetchFn: typeof fetch = fetch) {
  return async (email: string, code: string) => {
    const content = emailContent(code);
    const res = await fetchFn('https://api.brevo.com/v3/smtp/email', {
      method: 'POST',
      headers: { 'api-key': apiKey, 'Content-Type': 'application/json', Accept: 'application/json' },
      body: JSON.stringify({
        sender: { name: 'Home8', email: from },
        to: [{ email }],
        subject: content.subject,
        textContent: content.text,
        htmlContent: content.html,
      }),
    });
    if (!res.ok) {
      console.error('Brevo send failed', res.status, await res.text().catch(() => ''));
      throw new AuthError(503, 'email-failed',
        "We couldn't send the email right now. Please try again in a minute.");
    }
  };
}

let realDeps: Deps | null = null;

function depsFromEnv(): Deps {
  if (realDeps) return realDeps;
  const env = (name: string) => {
    const v = DenoGlobal.env.get(name);
    if (!v) throw new Error(`Missing secret ${name}`);
    return v;
  };
  const sa = JSON.parse(env('FIREBASE_SERVICE_ACCOUNT')) as ServiceAccount;
  realDeps = {
    rpc: supabaseRpc(env('SUPABASE_URL'), env('SUPABASE_SERVICE_ROLE_KEY')),
    sendMail: brevoSender(env('BREVO_API_KEY'), env('MAIL_FROM')),
    firebase: firebaseAdmin(sa),
  };
  return realDeps;
}

if (DenoGlobal && typeof DenoGlobal.serve === 'function') {
  DenoGlobal.serve(createHandler(depsFromEnv));
}

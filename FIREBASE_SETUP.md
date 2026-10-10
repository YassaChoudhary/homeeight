# Firebase — how login works

Firebase project: `home8-61d48` · Android package: `com.home8.app` · plan: **Spark (free)**

Setup steps are in **SETUP.md**. This file explains the design.

## Login methods

| Method | How |
|---|---|
| Continue with Google | Plain Firebase Auth (google_sign_in 7 → `signInWithCredential`) |
| Email + 6-digit code | Supabase Edge Function `email-auth` checks the code and returns a Firebase **custom token** → `signInWithCustomToken` |
| Phone OTP | Not yet — shows "coming soon" (Firebase phone auth needs Blaze) |
| Sign in with Apple | Not yet — needs an Apple Developer account |

Every user is a Firebase user, whichever method they used. **Same email = same
account**: an email-code login finds the existing Google account by email and
signs into it.

The session persists across restarts (Firebase keeps it). New accounts get
"What brings you to Home8?"; returning users go straight in.

## Why the code check runs on Supabase
Firebase has no built-in email-code login, and Firebase Cloud Functions need the
paid Blaze plan. Supabase Edge Functions are free. The function signs Firebase
custom tokens with the project's service account key (stored only as a Supabase
secret), which works on Firebase's free plan.

Code rules (enforced in SQL, `supabase/migrations/20261011010000_email_otp.sql`):
6 digits, valid 10 minutes, single use, 5 wrong attempts locks it, one email per
30 s and 5 per hour per address. Codes are stored only as salted hashes, and the
app's roles can't read the table at all.

## Supabase access
Supabase only treats a Firebase token as "signed in" if it carries
`role: authenticated`. Email-code tokens include it. For Google users the app
calls `email-auth` with `action: ensure-role` once; the function verifies the ID
token and stores the claim on the account. See `_ensureSupabaseRole` in
`lib/state/auth_controller.dart`.

## The user record — Firestore `users/{uid}`

| Field | Notes |
|---|---|
| `uid`, `email`, `authMethod` | From Firebase Auth (`email` / `google`) |
| `name`, `phone`, `photoUrl` | Editable from Edit Profile. Code sign-ups start with the part of the email before `@` |
| `intent` | `findProperty` / `listProperty` (screen 27) |
| `lister` | Lister profile map (type, company, licence, status…) |
| `emailVerified`, `phoneVerified` | Copied at sign-up; the app reads the live value from Firebase Auth |
| `memberSince` | Year the account was created |
| `guestState` | Market, language, searches etc. captured from the guest session |
| `createdAt`, `updatedAt` | Server timestamps |

Rules: `firestore.rules` — each user reads and writes only their own record.

## Where the code is
- `lib/state/auth_controller.dart` — Firebase Auth, Firestore user record, calls to `email-auth`
- `lib/screens/email_login_screen.dart` — email → Continue
- `lib/screens/otp_screen.dart` — code boxes, resend, errors
- `lib/screens/login_screen.dart` — Google, plus Phone/Apple "coming soon"
- `lib/screens/purpose_screen.dart` — `continueAfterSignIn`
- `supabase/functions/email-auth/index.ts` — the code sender/checker (+ `test.mjs`)
- `android/app/google-services.json`; Gradle plugin in `android/settings.gradle.kts` and `android/app/build.gradle.kts`

## Before publishing to Google Play
Add the SHA-1 of your **upload key** and of **Play App Signing** (Play Console →
App integrity) under Project settings → Your apps, or Google login fails in the
store build.

# Home8 — backend setup (all free plans)

**Firebase (Spark, free):** login (Google + email code), user records in Firestore.
**Supabase (Free):** listings, search, saved hearts, and the `email-auth` Edge
Function that sends and checks email codes.
**Brevo (Free):** delivers the code emails.

No billing account or card is needed anywhere. Do the steps in order; each
takes a few minutes. Everything is done in web dashboards — no command-line
tools except Flutter.

---

## Part A — Firebase (`home8-61d48`)

**A1. Sign-in methods**
Firebase console → **Authentication → Sign-in method** → enable **Google**.
(Email/Password is *not* needed — email codes come from Supabase.)

**A2. Firestore database**
**Firestore Database → Create database** → Standard edition → a nearby region
(e.g. `me-central1` Doha or `asia-south1` Mumbai; can't be changed later) →
production mode.
Then **Rules** tab → replace everything with the contents of `firestore.rules`
→ **Publish**.

**A3. Service account key** (lets the Supabase function log users into Firebase)
⚙️ **Project settings → Service accounts → Generate new private key** →
a `.json` file downloads.
⚠️ This file is a master key to your Firebase project. Never put it in the app,
in the project folder, on GitHub, or in chat. It goes only into Supabase
secrets (step C2). If it ever leaks, delete it on the same page and make a new one.

**A4. SHA-1** (Google login) — already added for your debug key. Before Play
Store release, also add your upload key's and Play App Signing's SHA-1.

---

## Part B — Brevo (email sending)

1. Sign up at **brevo.com** (free).
2. **Senders, Domains & Dedicated IPs → Senders → Add a sender** — e.g. your
   Gmail — and confirm it from your inbox. (For launch, use your own domain and
   authenticate it in Brevo, or codes may land in spam.)
3. **SMTP & API → API Keys → Generate a new API key** → copy it.

---

## Part C — Supabase (`bageehfzmwuyfaehaaon`)

**C1. Database** — **SQL Editor → New query**, run these files one at a time
(paste the whole file → **Run**):
1. `supabase/migrations/20261011000000_listings.sql`
2. `supabase/migrations/20261011010000_email_otp.sql`
3. `supabase/seed.sql` (demo listings)

**C2. Secrets** — **Edge Functions → Secrets** (or *Manage secrets*) → add:

| Name | Value |
|---|---|
| `FIREBASE_SERVICE_ACCOUNT` | the **entire contents** of the JSON file from A3 |
| `BREVO_API_KEY` | the key from B3 |
| `MAIL_FROM` | the sender email you confirmed in B2 |

**C3. Deploy the function** — **Edge Functions → Deploy a new function →
Via Editor**:
- Name: `email-auth` (exactly)
- Delete the sample code, paste all of `supabase/functions/email-auth/index.ts`
- **Deploy**
- Open the function's **Details/Settings** → turn **OFF "Verify JWT" /
  "Enforce JWT verification"** → Save. (The app calls it before anyone is
  signed in; the function checks everything itself.)

**C4. Accept Firebase logins** — **Authentication → Sign In / Providers →
Third-party auth → Add provider → Firebase** → Project ID `home8-61d48` → Save.

**C5. App key** — **Project Settings → API Keys** → copy the **anon / public**
key (never the service_role / secret key). In the project folder copy
`env.example.json` to `env.json` and paste it:
```json
{
  "SUPABASE_URL": "https://bageehfzmwuyfaehaaon.supabase.co",
  "SUPABASE_ANON_KEY": "eyJ...anon key..."
}
```

---

## Part D — Run the app

```
flutter clean
flutter pub get
adb connect 127.0.0.1:5555
flutter run -d 127.0.0.1:5555 --dart-define-from-file=env.json
```
VS Code: use the **"Home8 (with Supabase)"** run configuration instead.

The console should print `Firebase initialised` and
`Supabase initialised: https://bageehfzmwuyfaehaaon.supabase.co`.

---

## Troubleshooting

| What you see | Fix |
|---|---|
| "Email sign-in isn't set up on the server yet" | Function not deployed or not named `email-auth` (C3) |
| "turn off Verify JWT" | C3 last bullet |
| "Email sign-in needs the Supabase connection" | Run with `--dart-define-from-file=env.json` (D) |
| "Something went wrong" after Continue | Supabase → Edge Functions → `email-auth` → **Logs**. "Missing secret …" → C2. Brevo error → B2/B3. "rpc otp_… 404" → C1 step 2 |
| Code email never arrives | Check spam; Brevo → Logs; sender confirmed (B2) |
| "Something went wrong" after entering the code | Function logs. "Identity Toolkit … has not been used / disabled" → open the link in the log and click **Enable**, wait 2 min. "invalid_grant" → re-paste the JSON in C2 |
| Google: error 10 / "isn't set up correctly" | SHA-1 (A4), Google enabled (A1), Google account added in BlueStacks |
| Signed in but hearts don't save | C4 done? Sign out and in again |

## Tests (for developers)
- Edge Function: `node --experimental-strip-types --test supabase/functions/email-auth/test.mjs` (13 tests, Node 22.6+)
- SQL: `supabase/tests/` — run `supabase_stub.sql`, the migrations, `seed.sql`, then `tests.sql` (50 checks) and `otp_tests.sql` (18 checks) on a local Postgres 16.

See `FIREBASE_SETUP.md` and `SUPABASE_SETUP.md` for how each side works.

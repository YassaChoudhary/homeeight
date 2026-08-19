# Supabase — step 1: connect

Project: **home8 Project** · region **Central EU (Frankfurt)**
URL: `https://bageehfzmwuyfaehaaon.supabase.co`

This step only proves the connection. The app still runs entirely on mock data
and looks identical. Nothing reads from Supabase yet — that's deliberate.

## One-time local setup

1. Copy the example config and paste your anon key into it:

   ```
   cp env.example.json env.json
   ```

   Get the key from **Settings → API Keys → anon / public**.
   `env.json` is git-ignored, so it stays on your machine.

2. Install the new dependency:

   ```
   flutter pub get
   ```

3. Run with the config:

   ```
   flutter run --dart-define-from-file=env.json
   ```

## What you should see

In the console, on launch:

```
Supabase initialised: https://bageehfzmwuyfaehaaon.supabase.co
```

The app itself behaves exactly as before. That's success.

If you run plain `flutter run` without the config, you'll instead see:

```
No SUPABASE_ANON_KEY defined — running on mock data.
```

That's also fine — the app is built to keep working without credentials, so a
teammate cloning the repo gets a working build rather than a crash.

## About the anon key

It is **publishable, not secret**. It ships inside every app binary and anyone
can extract it from an APK. What actually protects your data is Row Level
Security on the tables — which is why RLS was enabled at project creation.

Keeping the key out of the repo is still worth doing: it makes rotation
possible and stops it leaking into forks and CI logs. But never treat it as the
security boundary.

The **`service_role` key is genuinely secret** and must never appear in this
app. It bypasses RLS completely. It belongs only in server-side Edge Functions.

## Also save

The **database password** from project creation. Supabase won't show it again,
and you'll need it for migrations and direct SQL access. Password manager, not
a notes app.

## Files changed in this step

| File | Change |
|---|---|
| `pubspec.yaml` | added `supabase_flutter: ^2.8.0` |
| `lib/core/env.dart` | new — build-time config, `Env.hasSupabase` switch |
| `lib/main.dart` | `Supabase.initialize()`, guarded and non-fatal |
| `env.example.json` | new — committed template, no key |
| `.gitignore` | ignores `env.json` |

## Next

1. **Auth** — phone OTP, rebuilding `AuthController` on real Supabase sessions
   instead of the current "any six digits" mock.
2. Tables + RLS policies, written together.
3. `SupabaseListingRepository`, swapped in at the marked line in `main.dart`.

Auth comes before tables because every RLS policy keys off `auth.uid()`. Build
tables first and you'll write those policies twice.

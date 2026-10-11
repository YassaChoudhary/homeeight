/// Build-time configuration.
///
/// Nothing secret is hardcoded here. Values arrive through `--dart-define` at
/// compile time, so the anon key never lands in the repository:
///
/// ```
/// flutter run \
///   --dart-define=SUPABASE_URL=https://bageehfzmwuyfaehaaon.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=<your anon key>
/// ```
///
/// The repeated flags get tedious, so there is also a `--dart-define-from-file`
/// form — see `env.example.json` in the project root. Copy it to `env.json`,
/// fill in the key, and run:
///
/// ```
/// flutter run --dart-define-from-file=env.json
/// ```
///
/// `env.json` is git-ignored. `env.example.json` is committed and holds no key.
///
/// A note on the anon key: it is *publishable*, not secret — it ships inside
/// every app binary and anyone can extract it. What protects your data is Row
/// Level Security on the tables, not the key. Keeping it out of the repo is
/// good hygiene (it makes rotation possible, and stops it leaking into forks
/// and CI logs), but never treat it as the security boundary. The `service_role`
/// key IS secret and must never appear in this app at all — it bypasses RLS
/// entirely and belongs only in server-side Edge Functions.
class Env {
  Env._();

  /// Supabase project URL, e.g. https://bageehfzmwuyfaehaaon.supabase.co
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://bageehfzmwuyfaehaaon.supabase.co',
  );

  /// Supabase anon / publishable key. No default — an empty value means the
  /// app runs on mock data rather than silently pointing at nothing.
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );

  /// True when both values are present.
  ///
  /// This is the switch the app reads. With no key configured the app keeps
  /// running on `MockListingRepository` exactly as before — so a teammate who
  /// clones the repo without credentials still gets a working build instead of
  /// a crash on launch.
  static bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Mapbox *public* access token (starts with `pk.`). From the Mapbox
  /// account page → Tokens → "Default public token". Publishable by design —
  /// restrict it to the app's package name in Mapbox before launch.
  ///
  /// Empty means maps show a "map unavailable" panel instead of crashing.
  static const String mapboxToken = String.fromEnvironment(
    'MAPBOX_ACCESS_TOKEN',
  );

  static bool get hasMapbox => mapboxToken.startsWith('pk.');
}

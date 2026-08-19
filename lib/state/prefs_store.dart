import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Local, on-device storage for everything the app needs to remember about a
/// user who has **not** signed in.
///
/// Why the phone and not Supabase: reading this has to be instant and has to
/// work offline. Putting guest state on the server would mean the splash screen
/// waits on a network round-trip before it can decide whether to show
/// onboarding — a spinner on a weak connection, and a broken launch with no
/// connection at all.
///
/// Nothing here is sensitive. It is preferences and UI state, not credentials.
/// The Supabase session token is stored separately by `supabase_flutter`, which
/// uses the platform's secure storage.
///
/// Everything is read once at launch into memory (see [Prefs.load]) so no
/// screen ever awaits a disk read mid-render.
class Prefs {
  Prefs._(this._prefs);

  final SharedPreferences _prefs;

  static Prefs? _instance;

  /// Available after [load]. Throws if read before then, which would be a bug
  /// rather than something to handle at runtime.
  static Prefs get instance {
    final i = _instance;
    if (i == null) {
      throw StateError('Prefs.load() must be awaited before Prefs.instance');
    }
    return i;
  }

  static bool get isReady => _instance != null;

  static Future<Prefs> load() async {
    final prefs = await SharedPreferences.getInstance();
    return _instance = Prefs._(prefs);
  }

  // --- Keys ----------------------------------------------------------------
  // Namespaced so a future migration can find and clear them as a group.
  static const _kOnboardingSeen = 'h8.onboarding_seen';
  static const _kMarket = 'h8.market';
  static const _kLanguage = 'h8.language';
  static const _kCurrency = 'h8.currency_override';
  static const _kLocationGranted = 'h8.location_granted';
  static const _kDetectedCity = 'h8.detected_city';
  static const _kDetectedCountry = 'h8.detected_country';
  static const _kRecentSearches = 'h8.recent_searches';
  static const _kPush = 'h8.notif_push';
  static const _kEmail = 'h8.notif_email';
  static const _kSms = 'h8.notif_sms';
  static const _kDarkTheme = 'h8.dark_theme';
  static const _kNotifTopics = 'h8.notif_topics';
  static const _kPendingMigration = 'h8.pending_migration';

  // --- Reads ---------------------------------------------------------------
  bool get onboardingSeen => _prefs.getBool(_kOnboardingSeen) ?? false;
  String? get market => _prefs.getString(_kMarket);
  String? get language => _prefs.getString(_kLanguage);
  String? get currencyOverride => _prefs.getString(_kCurrency);
  bool get locationGranted => _prefs.getBool(_kLocationGranted) ?? false;
  String? get detectedCity => _prefs.getString(_kDetectedCity);
  String? get detectedCountry => _prefs.getString(_kDetectedCountry);
  List<String> get recentSearches =>
      _prefs.getStringList(_kRecentSearches) ?? const [];
  bool get pushEnabled => _prefs.getBool(_kPush) ?? true;
  bool get emailEnabled => _prefs.getBool(_kEmail) ?? true;
  bool get smsEnabled => _prefs.getBool(_kSms) ?? false;
  bool get darkTheme => _prefs.getBool(_kDarkTheme) ?? false;
  List<String> get notifTopics =>
      _prefs.getStringList(_kNotifTopics) ??
      const ['matches', 'price_drops', 'messages'];

  /// Guest data waiting to be pushed to the user's account. See
  /// `guest_migration.dart`.
  Map<String, dynamic>? get pendingMigration {
    final raw = _prefs.getString(_kPendingMigration);
    if (raw == null || raw.isEmpty) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  // --- Writes --------------------------------------------------------------
  // Fire-and-forget: SharedPreferences already caches in memory, so the value
  // is readable immediately and the disk write settles in the background.
  // Nothing here is important enough to block a frame on.
  Future<void> setOnboardingSeen(bool v) => _prefs.setBool(_kOnboardingSeen, v);
  Future<void> setMarket(String v) => _prefs.setString(_kMarket, v);
  Future<void> setLanguage(String v) => _prefs.setString(_kLanguage, v);
  Future<void> setLocationGranted(bool v) =>
      _prefs.setBool(_kLocationGranted, v);
  Future<void> setDetectedCity(String? v) => v == null
      ? _prefs.remove(_kDetectedCity)
      : _prefs.setString(_kDetectedCity, v);
  Future<void> setDetectedCountry(String? v) => v == null
      ? _prefs.remove(_kDetectedCountry)
      : _prefs.setString(_kDetectedCountry, v);
  Future<void> setRecentSearches(List<String> v) =>
      _prefs.setStringList(_kRecentSearches, v);
  Future<void> setPushEnabled(bool v) => _prefs.setBool(_kPush, v);
  Future<void> setEmailEnabled(bool v) => _prefs.setBool(_kEmail, v);
  Future<void> setSmsEnabled(bool v) => _prefs.setBool(_kSms, v);
  Future<void> setDarkTheme(bool v) => _prefs.setBool(_kDarkTheme, v);
  Future<void> setNotifTopics(List<String> v) =>
      _prefs.setStringList(_kNotifTopics, v);

  Future<void> setCurrencyOverride(String? v) =>
      v == null ? _prefs.remove(_kCurrency) : _prefs.setString(_kCurrency, v);

  Future<void> setPendingMigration(Map<String, dynamic>? v) => v == null
      ? _prefs.remove(_kPendingMigration)
      : _prefs.setString(_kPendingMigration, jsonEncode(v));

  /// Wipes everything under the `h8.` namespace. For "reset app" in settings —
  /// not called anywhere automatically.
  Future<void> clearAll() async {
    final keys = _prefs.getKeys().where((k) => k.startsWith('h8.')).toList();
    for (final key in keys) {
      await _prefs.remove(key);
    }
  }
}

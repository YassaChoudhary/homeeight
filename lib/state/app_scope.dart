import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../data/listing_repository.dart';
import 'location_service.dart';
import 'prefs_store.dart';
import 'auth_controller.dart';

/// The market the user picked on screen 3. Drives currency, permit rules and
/// (later) which backend partition to query.
enum Market {
  uae('UAE', 'AE', 'AED', 'assets/images/flags/uae.png'),
  ksa('KSA', 'SA', 'SAR', 'assets/images/flags/ksa.png'),
  qatar('Qatar', 'QA', 'QAR', 'assets/images/flags/qatar.png'),
  pakistan('Pakistan', 'PK', 'PKR', 'assets/images/flags/pakistan.png'),
  canada('Canada', 'CA', 'CAD', 'assets/images/flags/canada.png'),
  usa('USA', 'US', 'USD', 'assets/images/flags/usa.png'),
  uk('UK', 'GB', 'GBP', 'assets/images/flags/uk.png'),
  australia('Australia', 'AU', 'AUD', 'assets/images/flags/australia.png'),
  newZealand('New Zealand', 'NZ', 'NZD', 'assets/images/flags/newzealand.png');

  final String label;
  final String code;
  final String currency;
  final String flagAsset;
  const Market(this.label, this.code, this.currency, this.flagAsset);

  /// Which markets actually have listings.
  ///
  /// Only UAE is live. The others stay visible in the picker but are marked
  /// "launching soon" — a user who picks a market and lands on zero results
  /// reads that as a broken app, not an empty one.
  bool get isLaunched => this == Market.uae;

  /// Matches an ISO country code from the device location to a market.
  /// Returns null for anywhere we don't operate.
  static Market? fromCountryCode(String? code) {
    if (code == null || code.isEmpty) return null;
    final upper = code.toUpperCase();
    for (final market in Market.values) {
      if (market.code == upper) return market;
    }
    return null;
  }
}

enum AppLanguage {
  english('International English', 'en', TextDirection.ltr),
  arabic('العربية', 'ar', TextDirection.rtl),
  urdu('اردو', 'ur', TextDirection.rtl),
  bengali('বাংলা', 'bn', TextDirection.ltr);

  final String label;
  final String code;
  final TextDirection direction;
  const AppLanguage(this.label, this.code, this.direction);
}

/// Session-level preferences that outlive any single screen.
///
/// Kept deliberately small: every listener rebuilds when this changes, so
/// high-frequency things (saved hearts, search results) live in their own
/// notifiers rather than here.
///
/// Persisting this is a one-file change — add shared_preferences, hydrate in
/// [restore] and write in [_persist].
class AppState extends ChangeNotifier {
  Market _market = Market.uae;
  AppLanguage _language = AppLanguage.english;
  String? _currencyOverride;
  bool _locationGranted = false;
  bool _onboardingSeen = false;

  /// City resolved from the device's GPS, e.g. "Karachi". Null until location
  /// is granted and resolved. This is where the user actually is — which is
  /// not necessarily the market they're browsing. See [headerCity].
  String? _detectedCity;

  /// ISO country code from the same lookup, e.g. "PK".
  String? _detectedCountry;

  // Settings toggles (screens F05, F09). Local-only, like everything else on
  // AppState — these become a PATCH /me/preferences call with the backend.
  bool _pushEnabled = true;
  bool _emailEnabled = true;
  bool _smsEnabled = false;
  bool _darkTheme = false;
  final Set<String> _notifTopics = {'matches', 'price_drops', 'messages'};

  Market get market => _market;
  AppLanguage get language => _language;
  bool get locationGranted => _locationGranted;
  bool get onboardingSeen => _onboardingSeen;
  String? get detectedCity => _detectedCity;
  String? get detectedCountry => _detectedCountry;

  /// True when the user is physically inside the market they're browsing.
  bool get inDetectedMarket =>
      _detectedCountry != null && _detectedCountry == _market.code;

  bool get pushEnabled => _pushEnabled;
  bool get emailEnabled => _emailEnabled;
  bool get smsEnabled => _smsEnabled;
  bool get darkTheme => _darkTheme;

  /// Topic keys: 'matches', 'price_drops', 'messages', 'offers'.
  bool notifTopic(String key) => _notifTopics.contains(key);

  void setPushEnabled(bool v) {
    if (_pushEnabled == v) return;
    _pushEnabled = v;
    _persist((p) => p.setPushEnabled(v));
    notifyListeners();
  }

  void setEmailEnabled(bool v) {
    if (_emailEnabled == v) return;
    _emailEnabled = v;
    _persist((p) => p.setEmailEnabled(v));
    notifyListeners();
  }

  void setSmsEnabled(bool v) {
    if (_smsEnabled == v) return;
    _smsEnabled = v;
    _persist((p) => p.setSmsEnabled(v));
    notifyListeners();
  }

  /// Dark theme is a preference only — `AppTheme.dark` doesn't exist yet, so
  /// this stores the choice without changing the palette. Wire it into
  /// `MaterialApp.themeMode` once a dark palette is designed.
  void setDarkTheme(bool v) {
    if (_darkTheme == v) return;
    _darkTheme = v;
    _persist((p) => p.setDarkTheme(v));
    notifyListeners();
  }

  void setNotifTopic(String key, bool enabled) {
    final changed =
        enabled ? _notifTopics.add(key) : _notifTopics.remove(key);
    if (changed) {
      _persist((p) => p.setNotifTopics(_notifTopics.toList()));
      notifyListeners();
    }
  }

  /// The currency actually shown. Defaults to the market's own currency until
  /// the user overrides it on the listing detail or in settings.
  String get currency => _currencyOverride ?? _market.currency;

  /// City shown in the Home hero — **where the user physically is**.
  ///
  /// Location and market are independent. Location answers "where am I";
  /// market answers "whose listings am I browsing", and is chosen in
  /// onboarding or settings. Someone sitting in Lahore with UAE selected sees
  /// "Lahore" in the hero and UAE properties below it; the note driven by
  /// [outsideLaunchedMarket] is what explains the difference.
  ///
  /// Falls back to the market's own city only when there's no GPS fix at all.
  String get headerCity => _detectedCity ?? marketCity;

  /// True when the user is standing outside the market they're browsing — so
  /// the hero says one city and the results are from another. Drives a short
  /// explanatory note; without it the mismatch reads as a bug.
  bool get outsideLaunchedMarket {
    if (_detectedCountry == null) return false;
    return _detectedCountry != _market.code;
  }

  /// The market the device location points at, whether or not it's launched.
  Market? get detectedMarket => Market.fromCountryCode(_detectedCountry);

  /// Default city per market, used when there's no GPS city to show.
  String get marketCity => switch (_market) {
        Market.uae => 'Dubai',
        Market.ksa => 'Riyadh',
        Market.qatar => 'Doha',
        Market.pakistan => 'Karachi',
        Market.canada => 'Toronto',
        Market.usa => 'New York',
        Market.uk => 'London',
        Market.australia => 'Sydney',
        Market.newZealand => 'Auckland',
      };

  TextDirection get textDirection => _language.direction;
  bool get isRtl => _language.direction == TextDirection.rtl;

  void setMarket(Market value) {
    if (_market == value) return;
    _market = value;
    _currencyOverride = null;
    _persist((p) async {
      await p.setMarket(value.name);
      await p.setCurrencyOverride(null);
    });
    notifyListeners();
  }

  void setLanguage(AppLanguage value) {
    if (_language == value) return;
    _language = value;
    _persist((p) => p.setLanguage(value.name));
    notifyListeners();
  }

  void setCurrency(String? code) {
    if (_currencyOverride == code) return;
    _currencyOverride = code;
    _persist((p) => p.setCurrencyOverride(code));
    notifyListeners();
  }

  void setLocationGranted(bool value) {
    if (_locationGranted == value) return;
    _locationGranted = value;
    _persist((p) => p.setLocationGranted(value));
    notifyListeners();
  }

  /// Applies a resolved GPS position.
  ///
  /// If the detected country is a market we've launched, we switch to it — a
  /// user in Dubai should not have to pick UAE by hand. If it isn't launched
  /// (Karachi today), the market is left alone so they still see real listings,
  /// and [outsideLaunchedMarket] lets the UI say why.
  void applyDetectedPlace(DetectedPlace place) {
    _detectedCity = place.city;
    _detectedCountry = place.countryCode;

    // Deliberately does NOT change the market. The market is the user's
    // choice, made in onboarding and changeable in settings; silently
    // switching it because someone crossed a border would swap their currency
    // and their whole result set without asking.
    _persist((p) async {
      await p.setDetectedCity(_detectedCity);
      await p.setDetectedCountry(_detectedCountry);
    });
    notifyListeners();
  }

  void markOnboardingSeen() {
    if (_onboardingSeen) return;
    _onboardingSeen = true;
    _persist((p) => p.setOnboardingSeen(true));
    notifyListeners();
  }

  // --- Persistence -------------------------------------------------------

  /// Fire-and-forget write. SharedPreferences caches in memory, so the value is
  /// readable straight away and the disk write settles in the background —
  /// nothing here is worth blocking a frame for.
  void _persist(Future<void> Function(Prefs prefs) write) {
    if (!Prefs.isReady) return;
    write(Prefs.instance);
  }

  /// Loads saved state from the device. Called once, before `runApp`.
  ///
  /// Everything is read synchronously off the already-loaded [Prefs], so the
  /// splash screen can decide between onboarding and the app without waiting
  /// on anything.
  void restore() {
    if (!Prefs.isReady) return;
    final p = Prefs.instance;

    _onboardingSeen = p.onboardingSeen;
    _locationGranted = p.locationGranted;
    _detectedCity = p.detectedCity;
    _detectedCountry = p.detectedCountry;
    _currencyOverride = p.currencyOverride;

    final savedMarket = p.market;
    if (savedMarket != null) {
      for (final m in Market.values) {
        if (m.name == savedMarket) {
          _market = m;
          break;
        }
      }
    }

    final savedLanguage = p.language;
    if (savedLanguage != null) {
      for (final l in AppLanguage.values) {
        if (l.name == savedLanguage) {
          _language = l;
          break;
        }
      }
    }

    _pushEnabled = p.pushEnabled;
    _emailEnabled = p.emailEnabled;
    _smsEnabled = p.smsEnabled;
    _darkTheme = p.darkTheme;
    _notifTopics
      ..clear()
      ..addAll(p.notifTopics);
  }
}

/// Saved / favourited listing ids.
///
/// Separate from [AppState] so tapping a heart repaints only the hearts, not
/// every screen listening for market or language.
class SavedListingsStore extends ValueNotifier<Set<String>> {
  final ListingRepository repository;

  SavedListingsStore(this.repository) : super(const {});

  bool contains(String id) => value.contains(id);

  /// Optimistic: flips locally, calls the repository, rolls back on failure.
  Future<void> toggle(String id) async {
    final wasSaved = value.contains(id);
    final next = Set<String>.from(value);
    wasSaved ? next.remove(id) : next.add(id);
    value = next;

    try {
      await repository.toggleSaved(id, saved: !wasSaved);
    } catch (_) {
      final rollback = Set<String>.from(value);
      wasSaved ? rollback.add(id) : rollback.remove(id);
      value = rollback;
    }
  }
}

/// Makes the repository and the shared notifiers available to the whole tree.
///
/// Deliberately built on InheritedWidget rather than a package: swapping in
/// provider / riverpod later means changing this file and the `of` call sites,
/// not the screens' logic.
class AppScope extends InheritedWidget {
  final AppState appState;
  final SavedListingsStore savedListings;
  final ListingRepository repository;
  final AuthController auth;

  const AppScope({
    super.key,
    required this.appState,
    required this.savedListings,
    required this.repository,
    required this.auth,
    required super.child,
  });

  /// Read + subscribe. Use in `build` when the widget shows market/language.
  static AppState watch(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing above this widget');
    return scope!.appState;
  }

  /// Read without subscribing. Use in callbacks and initState.
  static AppScope of(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing above this widget');
    return scope!;
  }

  static ListingRepository repositoryOf(BuildContext context) =>
      of(context).repository;

  static SavedListingsStore savedOf(BuildContext context) =>
      of(context).savedListings;

  static AuthController authOf(BuildContext context) => of(context).auth;

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      appState != oldWidget.appState ||
      savedListings != oldWidget.savedListings ||
      repository != oldWidget.repository ||
      auth != oldWidget.auth;
}

/// Rebuilds its child whenever [AppState] changes, without rebuilding the rest
/// of the tree. Wrap only the parts that actually display market/language.
class AppStateBuilder extends StatelessWidget {
  final Widget Function(BuildContext context, AppState state) builder;
  const AppStateBuilder({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context).appState;
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => builder(context, state),
    );
  }
}

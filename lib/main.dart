import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' show MapboxOptions;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/env.dart';
import 'data/chat_service.dart';
import 'data/listing_repository.dart';
import 'data/mock_listing_repository.dart';
import 'data/supabase_listing_repository.dart';
import 'screens/no_connection_screen.dart';
import 'screens/splash_screen.dart';
import 'state/app_scope.dart';
import 'state/auth_controller.dart';
import 'state/connectivity_controller.dart';
import 'state/guest_migration.dart';
import 'state/prefs_store.dart';
import 'state/presence_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  // Required before any plugin work happens ahead of runApp().
  WidgetsFlutterBinding.ensureInitialized();

  // Local guest state — market, language, onboarding-seen. Loaded before the
  // first frame so the splash screen can route without waiting on disk.
  try {
    await Prefs.load();
  } catch (error) {
    debugPrint('Prefs load failed, running with defaults: $error');
  }

  // Firebase powers login and the user record. On Android the config comes
  // from android/app/google-services.json, so no options are passed. Platforms
  // that aren't configured yet (iOS, web) throw here — the app then falls back
  // to the local, frontend-only sign-in instead of crashing.
  var firebaseReady = false;
  try {
    await Firebase.initializeApp();
    firebaseReady = true;
    debugPrint('Firebase initialised');
  } catch (error) {
    debugPrint('Firebase unavailable, using local sign-in: $error');
  }

  // Maps (Mapbox). Without a token, maps show a "Map unavailable" panel.
  if (Env.hasMapbox) {
    MapboxOptions.setAccessToken(Env.mapboxToken);
    debugPrint('Mapbox token set');
  } else {
    debugPrint('No MAPBOX_ACCESS_TOKEN — maps disabled. Add it to env.json.');
  }

  // Supabase serves listings and search. It doesn't run its own login: it
  // receives the user's Firebase ID token through `accessToken`, and Supabase
  // (Authentication → Third-party auth → Firebase) verifies it. Signed-out
  // visitors get null, which Supabase treats as anonymous — enough to browse.
  //
  // Tolerant on purpose: with no SUPABASE_ANON_KEY (a fresh clone, CI) or a
  // failed init, the app keeps running on mock data instead of crashing.
  var supabaseReady = false;
  if (Env.hasSupabase) {
    try {
      await Supabase.initialize(
        url: Env.supabaseUrl,
        anonKey: Env.supabaseAnonKey,
        accessToken: firebaseReady
            ? () async => FirebaseAuth.instance.currentUser?.getIdToken()
            : null,
      );
      supabaseReady = true;
      debugPrint('Supabase initialised: ${Env.supabaseUrl}');
    } catch (error, stack) {
      debugPrint('Supabase init failed, continuing on mock data: $error');
      debugPrintStack(stackTrace: stack);
    }
  } else {
    debugPrint('No SUPABASE_ANON_KEY defined — running on mock data. '
        'Run with --dart-define-from-file=env.json');
  }

  // The one place the app decides where its data comes from. Every screen
  // goes through the ListingRepository interface, so nothing else changes.
  // The seller side still runs on the mock inside SupabaseListingRepository.
  final ListingRepository repository = supabaseReady
      ? SupabaseListingRepository(
          Supabase.instance.client,
          // Anonymous connection for browsing: `accessToken` returning null
          // means "send the anon key", and no login state is involved at all.
          // Logged-out visitors and logged-in users see listings the same way.
          publicClient: SupabaseClient(
            Env.supabaseUrl,
            Env.supabaseAnonKey,
            accessToken: () async => null,
          ),
          fallback: MockListingRepository(),
        )
      : MockListingRepository();

  // Retry any guest data captured at a previous sign-in that never made it to
  // the server. No-ops when there's nothing pending.
  unawaited(GuestMigration.flush());

  runApp(Home8App(
    repository: repository,
    firebaseReady: firebaseReady,
    supabaseReady: supabaseReady,
  ));
}

class Home8App extends StatefulWidget {
  final ListingRepository repository;

  /// True when Firebase initialised — switches sign-in from the local
  /// stand-in to real Firebase Auth.
  final bool firebaseReady;

  /// True when Supabase initialised — listings come from it, and the email
  /// code login runs on its `email-auth` Edge Function.
  final bool supabaseReady;

  const Home8App({
    super.key,
    required this.repository,
    this.firebaseReady = false,
    this.supabaseReady = false,
  });

  @override
  State<Home8App> createState() => _Home8AppState();
}

class _Home8AppState extends State<Home8App> {
  late final AppState _appState;
  late final SavedListingsStore _savedListings;
  late final AuthController _auth;
  late final ConnectivityController _connectivity;

  /// Needed because [OfflineGate] sits above the Navigator and still has to be
  /// able to push the Saved screen. See the class doc on OfflineGate.
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _appState = AppState()..restore();
    _auth = AuthController(
      useFirebase: widget.firebaseReady,
      useSupabase: widget.supabaseReady,
    );
    _savedListings = SavedListingsStore(widget.repository);
    _connectivity = ConnectivityController();
    // Fill the hearts from the server whenever a different user signs in
    // (or the session is restored on launch); empty them on sign-out.
    _auth.addListener(_syncSavedWithAccount);
    _syncSavedWithAccount();
  }

  String? _savedFor;

  void _syncSavedWithAccount() {
    // Chat badge + online status follow the Firebase account.
    if (widget.firebaseReady) {
      final chatUid = _auth.isSignedIn ? ChatService.instance.myUid : null;
      ChatUnread.instance.follow(chatUid);
      PresenceService.instance.follow(chatUid);
    }
    final uid = _auth.user?.id;
    if (uid == _savedFor) return;
    _savedFor = uid;
    if (uid == null) {
      _savedListings.clear();
    } else {
      _savedListings.hydrate();
    }
  }

  @override
  void dispose() {
    _appState.dispose();
    _auth.removeListener(_syncSavedWithAccount);
    _auth.dispose();
    _savedListings.dispose();
    _connectivity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      appState: _appState,
      savedListings: _savedListings,
      repository: widget.repository,
      auth: _auth,
      // Connectivity is its own scope rather than a field on AppScope: it
      // changes on a timer and has nothing to do with session or market state,
      // so folding it in would make every AppScope consumer a connectivity
      // consumer too.
      child: ConnectivityScope(
        controller: _connectivity,
        // Only the Directionality + MaterialApp rebuild when the language
        // changes; screens below are untouched until they read AppState.
        child: ListenableBuilder(
          listenable: _appState,
          builder: (context, _) {
            return MaterialApp(
              title: 'Home8',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light,
              navigatorKey: _navigatorKey,
              builder: (context, child) {
                // Order matters. Directionality is outermost so the offline
                // screen mirrors correctly in Arabic and Urdu, and the gate
                // wraps `child` — which *is* the Navigator — so going offline
                // never unwinds the user's navigation stack.
                return Directionality(
                  textDirection: _appState.textDirection,
                  child: OfflineGate(
                    controller: _connectivity,
                    navigatorKey: _navigatorKey,
                    child: child ?? const SizedBox.shrink(),
                  ),
                );
              },
              home: const SplashScreen(),
            );
          },
        ),
      ),
    );
  }
}

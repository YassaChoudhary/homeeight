import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/env.dart';
import 'data/listing_repository.dart';
import 'data/mock_listing_repository.dart';
import 'screens/no_connection_screen.dart';
import 'screens/splash_screen.dart';
import 'state/app_scope.dart';
import 'state/auth_controller.dart';
import 'state/connectivity_controller.dart';
import 'state/guest_migration.dart';
import 'state/prefs_store.dart';
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

  // Connect to Supabase when credentials are present. This is deliberately
  // tolerant: with no key configured (a fresh clone, or CI) the app carries on
  // with mock data rather than crashing on launch.
  //
  // Nothing reads from Supabase yet — this step only proves the connection and
  // gives later work (auth, then listings) something to build on.
  if (Env.hasSupabase) {
    try {
      await Supabase.initialize(
        url: Env.supabaseUrl,
        anonKey: Env.supabaseAnonKey,
      );
      debugPrint('Supabase initialised: ${Env.supabaseUrl}');
    } catch (error, stack) {
      // A bad key or no network must not block launch while the app is still
      // running on mock data.
      debugPrint('Supabase init failed, continuing on mock data: $error');
      debugPrintStack(stackTrace: stack);
    }
  } else {
    debugPrint('No SUPABASE_ANON_KEY defined — running on mock data.');
  }

  // The one place the app decides where its data comes from.
  //
  // Once SupabaseListingRepository exists, this becomes:
  //   final repository = Env.hasSupabase
  //       ? SupabaseListingRepository(Supabase.instance.client)
  //       : MockListingRepository();
  // and nothing above this line changes — every screen goes through the
  // ListingRepository interface.
  final ListingRepository repository = MockListingRepository();

  // Retry any guest data captured at a previous sign-in that never made it to
  // the server. No-ops when there's nothing pending.
  unawaited(GuestMigration.flush());

  runApp(Home8App(repository: repository));
}

class Home8App extends StatefulWidget {
  final ListingRepository repository;
  const Home8App({super.key, required this.repository});

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
    _auth = AuthController();
    _savedListings = SavedListingsStore(widget.repository);
    _connectivity = ConnectivityController();
  }

  @override
  void dispose() {
    _appState.dispose();
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

import 'dart:async';

import 'package:flutter/material.dart';

import '../state/app_scope.dart';
import '../state/location_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/home_nav_bar.dart';
import 'main_shell.dart';
import 'onboarding_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 1600), _route);
  }

  /// Sends a returning user straight into the app and a first-time user into
  /// onboarding.
  ///
  /// The check is a synchronous read of already-loaded preferences, so there is
  /// no second delay here — the 1.6s above is the brand moment, not a wait.
  void _route() {
    if (!mounted) return;
    final appState = AppScope.of(context).appState;

    if (!appState.onboardingSeen) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const OnboardingScreen()),
      );
      return;
    }

    // Returning user. Refresh the city quietly in the background if they
    // already granted location — no dialog, and the app doesn't wait for it.
    if (appState.locationGranted) {
      unawaited(_refreshLocation(appState));
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const MainShell(initialTab: NavTab.reels),
      ),
      (route) => false,
    );
  }

  Future<void> _refreshLocation(AppState appState) async {
    final result = await const LocationService().resolveIfPermitted();
    final place = result.place;
    if (place != null) appState.applyDetectedPlace(place);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.primary, AppColors.primaryDark],
          ),
        ),
        child: SizedBox(
          width: double.infinity,
          height: double.infinity,
          child: SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 5),
                Text.rich(
                  TextSpan(
                    style: AppTextStyles.display(color: Colors.white)
                        .copyWith(fontSize: 44, fontWeight: FontWeight.w800),
                    children: const [
                      TextSpan(text: 'home'),
                      TextSpan(
                        text: '8',
                        style: TextStyle(color: AppColors.accent),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Find, trust & close on a home',
                  style: AppTextStyles.body(color: Colors.white70),
                ),
                const Spacer(flex: 4),
                SizedBox(
                  width: 44,
                  height: 44,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Colors.white.withValues(alpha: 0.85),
                    ),
                    backgroundColor: Colors.white.withValues(alpha: 0.18),
                  ),
                ),
                const Spacer(flex: 3),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

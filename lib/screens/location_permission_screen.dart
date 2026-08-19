import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../state/app_scope.dart';
import '../state/location_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../widgets/home_nav_bar.dart';
import '../widgets/pill_button.dart';
import 'main_shell.dart';

/// Screen 4. Asks the OS for location, resolves the city, and records both on
/// [AppState].
///
/// Nothing here blocks the user from reaching the app. Every failure path —
/// denied, services off, geocoder unreachable — still lands on the feed, just
/// without a detected city. A permission prompt is not worth a dead end.
class LocationPermissionScreen extends StatefulWidget {
  const LocationPermissionScreen({super.key});

  @override
  State<LocationPermissionScreen> createState() =>
      _LocationPermissionScreenState();
}

class _LocationPermissionScreenState extends State<LocationPermissionScreen> {
  bool _busy = false;

  /// Triggers the real OS dialog, then resolves the city.
  Future<void> _allow() async {
    if (_busy) return;
    setState(() => _busy = true);

    final result = await const LocationService().requestAndResolve();
    if (!mounted) return;

    final appState = AppScope.of(context).appState;
    final place = result.place;
    if (place != null) appState.applyDetectedPlace(place);

    // "Granted" means the OS said yes, even if the city lookup then failed —
    // so we don't re-prompt someone who already agreed.
    _finish(context, granted: result.granted);
  }

  void _finish(BuildContext context, {required bool granted}) {
    final scope = AppScope.of(context);
    scope.appState.setLocationGranted(granted);
    scope.appState.markOnboardingSeen();
    // Onboarding hands off to the Reels feed, not Home. MainShell still
    // *defaults* to Home for every other entry point (deep links, back-out of
    // a detail screen); this is the one place that asks for Reels explicitly.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const MainShell(initialTab: NavTab.reels),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 3),
              const Center(child: _LocationGraphic()),
              const Spacer(flex: 2),
              Text('See homes near you',
                  style: AppTextStyles.h1(), textAlign: TextAlign.center),
              const SizedBox(height: 14),
              Text(
                'Allow location to sort results by distance, show your commute '
                'and surface nearby communities first. Your location is never '
                'shared with agents.',
                style: AppTextStyles.body(color: AppColors.inkMuted),
                textAlign: TextAlign.center,
              ),
              const Spacer(flex: 3),
              PrimaryButton(
                label: 'Allow location',
                loading: _busy,
                onTap: _allow,
              ),
              const SizedBox(height: 8),
              TertiaryButton(
                label: 'Not now',
                onTap: _busy ? null : () => _finish(context, granted: false),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}

/// Concentric rings around the pin, pulsing like a heartbeat.
///
/// One controller drives everything. The two rings read the same animation at
/// staggered intervals, so you get a wave travelling outward rather than two
/// circles breathing in unison. `_beat` shapes the curve: a quick double-thump
/// (systole/diastole) and then a rest, instead of a plain sine — that's what
/// makes it read as a pulse rather than a throb.
///
/// The whole thing is inside a [RepaintBoundary] and only transforms/opacities
/// animate, so no layout work happens per frame.
class _LocationGraphic extends StatefulWidget {
  const _LocationGraphic();

  @override
  State<_LocationGraphic> createState() => _LocationGraphicState();
}

class _LocationGraphicState extends State<_LocationGraphic>
    with SingleTickerProviderStateMixin {
  static const double _size = 260;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Two-beat cardiac envelope over t in 0..1, returning 0..1.
  double _beat(double t) {
    if (t < 0.16) return Curves.easeOutCubic.transform(t / 0.16);
    if (t < 0.34) return 1 - 0.55 * Curves.easeInOut.transform((t - 0.16) / 0.18);
    if (t < 0.46) {
      return 0.45 + 0.42 * Curves.easeOutCubic.transform((t - 0.34) / 0.12);
    }
    if (t < 0.68) {
      return 0.87 * (1 - Curves.easeInOutCubic.transform((t - 0.46) / 0.22));
    }
    return 0;
  }

  double _phase(double base, double offset) {
    final t = (base + offset) % 1.0;
    return _beat(t);
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: _size,
        height: _size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value;
            final outer = _phase(t, 0.0);
            final middle = _phase(t, 0.10);
            final core = _phase(t, 0.16);

            return Stack(
              alignment: Alignment.center,
              children: [
                // Outermost halo — largest travel, faintest.
                _Ring(
                  diameter: _size,
                  color: AppColors.primaryTint,
                  scale: 0.90 + 0.10 * outer,
                  opacity: 0.45 + 0.55 * outer,
                ),
                _Ring(
                  diameter: 190,
                  color: AppColors.primary.withValues(alpha: 0.25),
                  scale: 0.88 + 0.12 * middle,
                  opacity: 0.55 + 0.45 * middle,
                ),
                // The solid teal disc with the pin. Scales least — the pin
                // should stay legible, so this is a nudge, not a bounce.
                Transform.scale(
                  scale: 1 + 0.045 * core,
                  child: Container(
                    width: 118,
                    height: 118,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary
                              .withValues(alpha: 0.20 + 0.30 * core),
                          blurRadius: 18 + 16 * core,
                          spreadRadius: 2 * core,
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(30),
                    child: SvgPicture.asset(
                      'assets/icons/location_pin.svg',
                      colorFilter: const ColorFilter.mode(
                          Colors.white, BlendMode.srcIn),
                    ),
                  ),
                ),
                const Positioned(
                  right: 8,
                  top: 40,
                  child: _CountBadge(label: '96k', dark: false),
                ),
                const Positioned(
                  left: 4,
                  bottom: 46,
                  child: _CountBadge(label: '118k', dark: true),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// A single pulsing circle. Kept separate so the transform and opacity are the
/// only things rebuilt per frame.
class _Ring extends StatelessWidget {
  final double diameter;
  final Color color;
  final double scale;
  final double opacity;

  const _Ring({
    required this.diameter,
    required this.color,
    required this.scale,
    required this.opacity,
  });

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: scale,
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Container(
          width: diameter,
          height: diameter,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  final String label;
  final bool dark;
  const _CountBadge({required this.label, required this.dark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: dark ? AppColors.navDark : Colors.white,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Text(
        label,
        style: AppTextStyles.bodyStrong(
            color: dark ? Colors.white : AppColors.ink),
      ),
    );
  }
}

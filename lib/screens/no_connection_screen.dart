import 'package:flutter/material.dart';

import '../state/connectivity_controller.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import 'saved_screen.dart';

// ---------------------------------------------------------------------------
// F08 — No connection
// ---------------------------------------------------------------------------

/// Screen F08.
///
/// Now driven by real connectivity via [OfflineGate] — see that class for how it
/// gets shown. Still usable standalone (in place of a failed list, say), which is
/// why [onRetry] and [onViewSaved] are injected rather than reached for from
/// here.
class NoConnectionScreen extends StatelessWidget {
  final Future<void> Function()? onRetry;
  final VoidCallback? onViewSaved;

  /// Shows the dark "You're offline" pill at the top of the frame.
  final bool showBanner;

  const NoConnectionScreen({
    super.key,
    this.onRetry,
    this.onViewSaved,
    this.showBanner = true,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            if (showBanner) const OfflineBanner(),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 150,
                        height: 150,
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          // The squircle from the frames — a plain circle reads
                          // as an avatar, a plain square as a card.
                          borderRadius: BorderRadius.circular(52),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.ink.withValues(alpha: 0.07),
                              blurRadius: 22,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.wifi_off_rounded,
                            size: 58, color: AppColors.amber),
                      ),
                      const SizedBox(height: 24),
                      Text('No connection',
                          style:
                              AppTextStyles.display().copyWith(fontSize: 25)),
                      const SizedBox(height: 10),
                      Text(
                        'Check your Wi-Fi or mobile data. Your saved homes and '
                        'recent searches still work offline.',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.body(color: AppColors.inkMuted),
                      ),
                      const SizedBox(height: 24),
                      _RetryButton(onRetry: onRetry),
                      if (onViewSaved != null) ...[
                        const SizedBox(height: 16),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: onViewSaved,
                          child: Text(
                            'View saved homes',
                            style: AppTextStyles.body(color: AppColors.ink)
                                .copyWith(
                                    decoration: TextDecoration.underline),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dark pill shown when offline. Public so any screen can put it above a list.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(
          AppSpacing.screenPadding, 8, AppSpacing.screenPadding, 4),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.navDark,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.amber,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "You're offline — showing cached results",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.body(color: Colors.white)
                  .copyWith(fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }
}

/// Spins while the retry runs, so a slow reconnect doesn't look like a dead tap.
class _RetryButton extends StatefulWidget {
  final Future<void> Function()? onRetry;
  const _RetryButton({required this.onRetry});

  @override
  State<_RetryButton> createState() => _RetryButtonState();
}

class _RetryButtonState extends State<_RetryButton> {
  bool _busy = false;

  Future<void> _run() async {
    final retry = widget.onRetry;
    if (retry == null) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() => _busy = true);
    try {
      await retry();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _busy ? null : _run,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 30),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.32),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_busy)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            else
              const Icon(Icons.refresh_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Text('Try again',
                style: AppTextStyles.bodyStrong(color: Colors.white)
                    .copyWith(fontSize: 17)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The gate
// ---------------------------------------------------------------------------

/// Shows [NoConnectionScreen] over the app whenever the device is offline.
///
/// ## Where it sits, and why that matters
///
/// This is installed **inside** `MaterialApp.builder`, wrapping the app's
/// `Navigator` rather than replacing it. Two consequences worth knowing:
///
/// 1. **Navigation state survives.** The user's stack — the listing they were
///    reading, the filters they'd set — is still mounted underneath. When the
///    connection returns the overlay disappears and they're exactly where they
///    were, rather than back at the splash screen.
/// 2. **It can't push routes itself.** Being above the `Navigator` means
///    `Navigator.of(context)` won't find one, which is why "View saved homes"
///    goes through [navigatorKey] instead. That link works offline precisely
///    because saved homes are the one thing that doesn't need the network.
///
/// The overlay is skipped until the controller has a real measurement
/// (`hasResult`), so the app never flashes the offline screen at launch before
/// anything has been probed.
class OfflineGate extends StatelessWidget {
  final ConnectivityController controller;

  /// The app's navigator, used for the "View saved homes" escape hatch.
  final GlobalKey<NavigatorState> navigatorKey;

  final Widget child;

  const OfflineGate({
    super.key,
    required this.controller,
    required this.navigatorKey,
    required this.child,
  });

  void _openSaved() {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;
    navigator.push(
      MaterialPageRoute(builder: (_) => const SavedScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: controller,
      builder: (context, online, _) {
        final showOverlay = !online && controller.hasResult;

        return Stack(
          children: [
            child,
            if (showOverlay)
              Positioned.fill(
                // A route-less overlay, so the navigator below keeps its stack.
                // TextDirection is inherited from the Directionality that
                // MaterialApp.builder already installs above this.
                child: _OfflineOverlay(
                  onRetry: controller.check,
                  onViewSaved: _openSaved,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Fades the offline screen in so a blip that outlives the debounce doesn't
/// slam a full-screen change into view.
class _OfflineOverlay extends StatefulWidget {
  final Future<void> Function() onRetry;
  final VoidCallback onViewSaved;

  const _OfflineOverlay({required this.onRetry, required this.onViewSaved});

  @override
  State<_OfflineOverlay> createState() => _OfflineOverlayState();
}

class _OfflineOverlayState extends State<_OfflineOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..forward();

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      // Opaque so the app underneath isn't visible or tappable through it.
      child: Material(
        color: AppColors.bg,
        child: NoConnectionScreen(
          onRetry: widget.onRetry,
          onViewSaved: widget.onViewSaved,
        ),
      ),
    );
  }
}

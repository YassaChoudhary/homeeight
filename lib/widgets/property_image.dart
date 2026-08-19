import 'package:flutter/material.dart';

import '../models/property.dart';

/// Renders listing media.
///
/// When [url] is null (which is the case for every mock listing today, since no
/// photography shipped with the handoff) it falls back to a deterministic
/// brand-gradient tile keyed by [seed], so cards stay visually distinct.
///
/// When the backend starts returning URLs, nothing at the call sites changes:
/// pass `url: property.photos.firstOrNull` and this widget handles decode
/// sizing, fade-in and the error fallback.
class PropertyImage extends StatelessWidget {
  final int seed;
  final String? url;
  final BorderRadius? borderRadius;
  final Widget? child;
  final BoxFit fit;

  /// Logical width the image will occupy. Passed to `cacheWidth` so large
  /// remote files are decoded down before they hit memory — the single biggest
  /// source of jank in an image-heavy list.
  final double? decodeWidth;

  const PropertyImage({
    super.key,
    required this.seed,
    this.url,
    this.borderRadius,
    this.child,
    this.fit = BoxFit.cover,
    this.decodeWidth,
  });

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.zero;
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;

    return ClipRRect(
      borderRadius: radius,
      child: RepaintBoundary(
        child: Stack(
          fit: StackFit.expand,
          children: [
            _GradientTile(seed: seed),
            if (url != null && url!.isNotEmpty)
              Image.network(
                url!,
                fit: fit,
                cacheWidth:
                    decodeWidth == null ? null : (decodeWidth! * dpr).round(),
                gaplessPlayback: true,
                frameBuilder: (context, child, frame, wasSync) {
                  if (wasSync || frame != null) {
                    return AnimatedOpacity(
                      opacity: 1,
                      duration: const Duration(milliseconds: 180),
                      child: child,
                    );
                  }
                  return const SizedBox.shrink();
                },
                // Falls through to the gradient underneath.
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ?child,
          ],
        ),
      ),
    );
  }
}

class _GradientTile extends StatelessWidget {
  final int seed;
  const _GradientTile({required this.seed});

  @override
  Widget build(BuildContext context) {
    final colors = kPhotoGradients[seed.abs() % kPhotoGradients.length];
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            right: -18,
            bottom: -18,
            child: Icon(
              Icons.villa_rounded,
              size: 110,
              color: Colors.white.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }
}

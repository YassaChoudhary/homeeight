import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/geo.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/home8_map.dart';
import '../../widgets/pill_button.dart';

/// Pick a search area by framing it on the map. Pops with the [GeoBounds] on
/// screen, or null if the user backs out.
///
/// Used by Search ("Choose area on map") and Filters ("Select on map").
/// A rectangle is what search filters on today (`min_lat`…`max_lng`);
/// freehand drawing later returns a polygon from this same screen.
class MapAreaScreen extends StatefulWidget {
  /// Area to start from (an existing filter), if any.
  final GeoBounds? initialBounds;

  /// Where to centre when there's no [initialBounds] — usually the market.
  final GeoPoint fallbackCenter;

  const MapAreaScreen({
    super.key,
    required this.fallbackCenter,
    this.initialBounds,
  });

  @override
  State<MapAreaScreen> createState() => _MapAreaScreenState();
}

class _MapAreaScreenState extends State<MapAreaScreen> {
  final Home8MapController _map = Home8MapController();
  MapViewport? _viewport;

  /// Zoom that roughly fits [bounds] across a screen [widthPx] wide.
  static double _zoomFor(GeoBounds bounds, double widthPx) {
    final span = (bounds.maxLng - bounds.minLng).abs();
    if (span <= 0) return 13;
    final z = math.log(360 * (widthPx / 256) / span) / math.ln2;
    return z.clamp(3, 17).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final width = MediaQuery.sizeOf(context).width;
    final initial = widget.initialBounds;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          Positioned.fill(
            child: Home8Map(
              controller: _map,
              initialCenter: initial?.center ?? widget.fallbackCenter,
              initialZoom: initial == null ? 12 : _zoomFor(initial, width),
              showMyLocation: true,
              onViewportIdle: (v) => setState(() => _viewport = v),
            ),
          ),
          // Header: back + what to do.
          Positioned(
            left: AppSpacing.screenPadding,
            right: AppSpacing.screenPadding,
            top: top + 10,
            child: Row(
              children: [
                MapCircleButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: 'Back',
                  onTap: () => Navigator.of(context).maybePop(),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.14),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Choose your area',
                            style: AppTextStyles.bodyStrong()),
                        Text(
                          "Move and zoom. We'll search what's on screen.",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.caption(),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: AppSpacing.screenPadding,
            right: AppSpacing.screenPadding,
            bottom: bottom + 16,
            child: PrimaryButton(
              label: 'Search this area',
              leadingIcon: Icons.search_rounded,
              onTap: _viewport == null
                  ? null
                  : () => Navigator.of(context).pop(_viewport!.bounds),
            ),
          ),
        ],
      ),
    );
  }
}

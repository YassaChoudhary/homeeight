import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/geo.dart';
import '../models/property.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../widgets/home8_map.dart';
import '../widgets/listing_card.dart';
import '../widgets/map_marker_images.dart';
import '../widgets/pill_button.dart';
import '../widgets/property_image.dart';

/// Screen 15 — results on a map.
///
/// * Every result with a location is a price pin ("AED 96K").
/// * Tapping a pin selects it (teal) and shows a compact card; tapping the
///   card opens the listing.
/// * Moving the map shows **Search this area**, which re-runs the search for
///   what's on screen (the query's [GeoBounds]). An active area shows a chip
///   to clear it.
///
/// Pins sit at each listing's approximate spot ([Property.mapLocation]), never
/// the exact address — see `approximateLocation`.
class ResultsMapView extends StatefulWidget {
  final List<Property> items;
  final bool loading;
  final GeoBounds? activeArea;
  final GeoPoint fallbackCenter;

  /// Listing to select and centre on when the map opens (from a card's Map
  /// button). Null centres on the area, or the first result.
  final String? focusId;

  final ValueChanged<GeoBounds> onSearchArea;
  final VoidCallback onClearArea;
  final ValueChanged<Property> onOpenDetail;

  /// Space to keep clear at the bottom (nav bar + List/Map toggle).
  final double bottomInset;

  const ResultsMapView({
    super.key,
    required this.items,
    required this.loading,
    required this.activeArea,
    required this.fallbackCenter,
    required this.onSearchArea,
    required this.onClearArea,
    required this.onOpenDetail,
    this.focusId,
    this.bottomInset = 0,
  });

  @override
  State<ResultsMapView> createState() => _ResultsMapViewState();
}

class _ResultsMapViewState extends State<ResultsMapView> {
  final Home8MapController _map = Home8MapController();
  late String? _selectedId = widget.focusId;
  MapViewport? _pendingArea;

  @override
  void didUpdateWidget(ResultsMapView old) {
    super.didUpdateWidget(old);
    // A card's Map button while the map is already open: move to it.
    if (widget.focusId != null && widget.focusId != old.focusId) {
      _selectedId = widget.focusId;
      final p = _byId(widget.focusId!);
      final loc = p?.mapLocation;
      if (loc != null) _map.flyTo(loc, zoom: 14);
    }
    // New results: drop a selection that's no longer in them.
    if (_selectedId != null && _byId(_selectedId!) == null) {
      _selectedId = null;
    }
    // A new set of results (e.g. a different search): frame them all —
    // unless the user is working inside a map area they picked.
    if (widget.focusId == null &&
        widget.activeArea == null &&
        !_sameIds(old.items, widget.items)) {
      final fit = _fit(_points, MediaQuery.sizeOf(context));
      if (fit != null) _map.flyTo(fit.$1, zoom: fit.$2, durationMs: 700);
    }
  }

  static bool _sameIds(List<Property> a, List<Property> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  List<GeoPoint> get _points =>
      widget.items.map((p) => p.mapLocation).whereType<GeoPoint>().toList();

  /// Centre + zoom that shows every point on a screen of [size], with room
  /// for the chips and the card.
  static (GeoPoint, double)? _fit(List<GeoPoint> points, Size size) {
    if (points.isEmpty) return null;
    if (points.length == 1) return (points.first, 14);
    var minLat = points.first.lat, maxLat = minLat;
    var minLng = points.first.lng, maxLng = minLng;
    for (final p in points) {
      minLat = math.min(minLat, p.lat);
      maxLat = math.max(maxLat, p.lat);
      minLng = math.min(minLng, p.lng);
      maxLng = math.max(maxLng, p.lng);
    }
    final center = GeoPoint((minLat + maxLat) / 2, (minLng + maxLng) / 2);
    final w = size.width * 0.75;
    final h = size.height * 0.5;
    final lngSpan = math.max(maxLng - minLng, 0.004);
    final latSpan = math.max(maxLat - minLat, 0.004);
    final cosLat = math.cos(center.lat * math.pi / 180).abs().clamp(0.2, 1.0);
    final zLng = math.log(360 * (w / 256) / lngSpan) / math.ln2;
    final zLat = math.log(360 * (h / 256) * cosLat / latSpan) / math.ln2;
    return (center, math.min(zLng, zLat).clamp(3.0, 15.0).toDouble());
  }

  Property? _byId(String id) {
    for (final p in widget.items) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Where the map opens: the focused listing, else the picked area, else
  /// framing all results, else the market.
  (GeoPoint, double) _initialCamera(Size size) {
    final focus = widget.focusId == null ? null : _byId(widget.focusId!);
    final focusLoc = focus?.mapLocation;
    if (focusLoc != null) return (focusLoc, 14);
    final area = widget.activeArea;
    if (area != null) {
      return _fit([area.southwest, area.northeast], size) ??
          (area.center, 12);
    }
    return _fit(_points, size) ?? (widget.fallbackCenter, 11.5);
  }

  (GeoPoint, double)? _camera;

  List<MapPin> get _pins => [
        for (final p in widget.items)
          if (p.mapLocation != null)
            MapPin(
              id: p.id,
              point: p.mapLocation!,
              label: compactPrice(p.currency, p.price),
            ),
      ];

  void _searchHere() {
    final area = _pendingArea;
    if (area == null) return;
    setState(() {
      _pendingArea = null;
      _selectedId = null;
    });
    widget.onSearchArea(area.bounds);
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedId == null ? null : _byId(_selectedId!);
    final withoutLocation =
        widget.items.where((p) => p.mapLocation == null).length;
    // Fixed at first build: the map only reads its initial camera once.
    final camera = _camera ??= _initialCamera(MediaQuery.sizeOf(context));

    return Stack(
      children: [
        Positioned.fill(
          child: Home8Map(
            controller: _map,
            initialCenter: camera.$1,
            initialZoom: camera.$2,
            pins: _pins,
            selectedPinId: _selectedId,
            onPinTap: (id) => setState(() => _selectedId = id),
            onTap: () {
              if (_selectedId != null) setState(() => _selectedId = null);
            },
            showMyLocation: true,
            onViewportIdle: (viewport) {
              if (viewport.movedByUser) {
                setState(() => _pendingArea = viewport);
              }
            },
          ),
        ),

        // Top: "Search this area", or the active-area chip, plus loading.
        Positioned(
          top: 12,
          left: 0,
          right: 0,
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: widget.loading
                  ? const _MapChip(
                      key: ValueKey('loading'),
                      icon: null,
                      label: 'Searching…',
                      busy: true,
                    )
                  : _pendingArea != null
                      ? _MapChip(
                          key: const ValueKey('search'),
                          icon: Icons.search_rounded,
                          label: 'Search this area',
                          primary: true,
                          onTap: _searchHere,
                        )
                      : widget.activeArea != null
                          ? _MapChip(
                              key: const ValueKey('area'),
                              icon: Icons.close_rounded,
                              label: 'Map area · Clear',
                              onTap: widget.onClearArea,
                            )
                          : const SizedBox.shrink(key: ValueKey('none')),
            ),
          ),
        ),

        // Bottom: selected listing card, or a hint when nothing to show.
        Positioned(
          left: AppSpacing.screenPadding,
          right: AppSpacing.screenPadding,
          bottom: widget.bottomInset + 12,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            switchInCurve: Curves.easeOutCubic,
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(
                position: Tween(begin: const Offset(0, 0.25), end: Offset.zero)
                    .animate(a),
                child: child,
              ),
            ),
            child: selected != null
                ? _MapListingCard(
                    key: ValueKey(selected.id),
                    property: selected,
                    onTap: () => widget.onOpenDetail(selected),
                  )
                : !widget.loading && widget.items.isEmpty
                    ? const _MapHint(
                        key: ValueKey('empty'),
                        text: 'No homes here. Move the map and tap '
                            '"Search this area".',
                      )
                    : withoutLocation > 0 && _pins.isEmpty
                        ? const _MapHint(
                            key: ValueKey('nolocation'),
                            text: "These listings don't have a map location yet.",
                          )
                        : const SizedBox.shrink(key: ValueKey('nothing')),
          ),
        ),
      ],
    );
  }
}

class _MapChip extends StatelessWidget {
  final IconData? icon;
  final String label;
  final bool primary;
  final bool busy;
  final VoidCallback? onTap;

  const _MapChip({
    super.key,
    required this.icon,
    required this.label,
    this.primary = false,
    this.busy = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = primary ? Colors.white : AppColors.ink;
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: primary ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: AppColors.ink.withValues(alpha: 0.18),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              )
            else if (icon != null)
              Icon(icon, size: 17, color: fg),
            const SizedBox(width: 8),
            Text(label, style: AppTextStyles.bodyStrong(color: fg)),
          ],
        ),
      ),
    );
  }
}

/// Compact card for the selected pin: photo, title, price, specs.
class _MapListingCard extends StatelessWidget {
  final Property property;
  final VoidCallback onTap;

  const _MapListingCard({super.key, required this.property, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = property;
    final period = p.period == null ? '' : ' / ${p.period!.label}';
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          boxShadow: [
            BoxShadow(
              color: AppColors.ink.withValues(alpha: 0.18),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            SizedBox(
              width: 96,
              height: 96,
              child: PropertyImage(
                seed: p.gradientSeed,
                url: p.photos.isEmpty ? null : p.photos.first,
                decodeWidth: 96,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodyStrong(),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    p.area,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption(),
                  ),
                  const SizedBox(height: 8),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${p.currency} ${p.priceFormatted}',
                          style: AppTextStyles.bodyStrong(
                              color: AppColors.primary),
                        ),
                        TextSpan(
                          text: period,
                          style: AppTextStyles.caption(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (p.beds > 0) '${p.beds} bd',
                      if (p.baths > 0) '${p.baths} ba',
                      if (p.sqft > 0) '${formatThousands(p.sqft)} sqft',
                    ].join(' · '),
                    style: AppTextStyles.caption(),
                  ),
                ],
              ),
            ),
            if (p.verified) const VerifiedPill(),
          ],
        ),
      ),
    );
  }
}

class _MapHint extends StatelessWidget {
  final String text;
  const _MapHint({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: 0.14),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Text(text, style: AppTextStyles.body(color: AppColors.inkMuted)),
    );
  }
}

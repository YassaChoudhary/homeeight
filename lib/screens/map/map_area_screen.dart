import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/geocoding_service.dart';
import '../../models/geo.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/home8_map.dart';
import '../../widgets/pill_button.dart';

/// Pick a search area on the map. Pops with the [GeoBounds] on screen, or
/// null if the user backs out.
///
/// The search box finds **any** area, community, city or address (Mapbox
/// geocoding) and flies there; then the user fine-tunes by moving / zooming
/// and taps "Search this area". Used by Search ("Search on the map") and
/// Filters ("Select on map").
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
  final GeocodingService _geocoder = GeocodingService();
  final TextEditingController _search = TextEditingController();
  final FocusNode _focus = FocusNode();

  MapViewport? _viewport;
  List<PlaceSuggestion> _results = const [];
  bool _searching = false;
  Timer? _debounce;
  int _requestId = 0;

  /// Name of the place picked from search, shown on the button.
  String? _placeName;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Zoom that roughly fits [bounds] across a screen [widthPx] wide.
  static double _zoomFor(GeoBounds bounds, double widthPx) {
    final span = (bounds.maxLng - bounds.minLng).abs();
    if (span <= 0) return 13;
    final z = math.log(360 * (widthPx / 256) / span) / math.ln2;
    return z.clamp(3, 17).toDouble();
  }

  void _onType(String text) {
    _debounce?.cancel();
    if (text.trim().length < 3) {
      setState(() {
        _results = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final id = ++_requestId;
      final results = await _geocoder.search(
        text,
        near: _viewport?.center ?? widget.fallbackCenter,
      );
      if (!mounted || id != _requestId) return;
      setState(() {
        _results = results;
        _searching = false;
      });
    });
  }

  void _pick(PlaceSuggestion place) {
    _focus.unfocus();
    setState(() {
      _results = const [];
      _search.text = place.name;
      _placeName = place.name;
    });
    // A city gets a wider view than a building or street.
    final isWide = place.community.isEmpty && place.city == place.name;
    _map.flyTo(place.point, zoom: isWide ? 11 : 14, durationMs: 1200);
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final width = MediaQuery.sizeOf(context).width;
    final initial = widget.initialBounds;

    return Scaffold(
      backgroundColor: AppColors.bg,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(
            child: Home8Map(
              controller: _map,
              initialCenter: initial?.center ?? widget.fallbackCenter,
              initialZoom: initial == null ? 12 : _zoomFor(initial, width),
              showMyLocation: true,
              onViewportIdle: (v) {
                setState(() {
                  _viewport = v;
                  // Moved away by hand: the place name may no longer fit.
                  if (v.movedByUser) _placeName = null;
                });
              },
              onTap: () => _focus.unfocus(),
            ),
          ),
          // Header: back + search box + results.
          Positioned(
            left: AppSpacing.screenPadding,
            right: AppSpacing.screenPadding,
            top: top + 10,
            child: Column(
              children: [
                Row(
                  children: [
                    MapCircleButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: 'Back',
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.14),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: TextField(
                          controller: _search,
                          focusNode: _focus,
                          textInputAction: TextInputAction.search,
                          onChanged: _onType,
                          onSubmitted: (_) {
                            if (_results.isNotEmpty) _pick(_results.first);
                          },
                          style: AppTextStyles.bodyStrong(),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: 'Search area, community or city',
                            hintStyle:
                                AppTextStyles.body(color: AppColors.inkMuted),
                            prefixIcon: const Icon(Icons.search_rounded,
                                color: AppColors.inkMuted),
                            suffixIcon: _searching
                                ? const Padding(
                                    padding: EdgeInsets.all(14),
                                    child: SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                                AppColors.primary),
                                      ),
                                    ),
                                  )
                                : _search.text.isEmpty
                                    ? null
                                    : IconButton(
                                        icon: const Icon(Icons.close_rounded,
                                            color: AppColors.inkMuted,
                                            size: 20),
                                        onPressed: () {
                                          _search.clear();
                                          _onType('');
                                        },
                                      ),
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_results.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    margin: const EdgeInsets.only(left: 54),
                    constraints: const BoxConstraints(maxHeight: 300),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.14),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: _results.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, color: AppColors.line),
                      itemBuilder: (context, i) {
                        final r = _results[i];
                        return InkWell(
                          onTap: () => _pick(r),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            child: Row(
                              children: [
                                const Icon(Icons.place_outlined,
                                    size: 20, color: AppColors.primary),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(r.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppTextStyles.bodyStrong()),
                                      if (r.context.isNotEmpty)
                                        Text(r.context,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: AppTextStyles.caption()),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ] else if (!_searching &&
                    _search.text.trim().length >= 3 &&
                    _focus.hasFocus) ...[
                  const SizedBox(height: 8),
                  Container(
                    margin: const EdgeInsets.only(left: 54),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Text('No places found. Try another name.',
                        style: AppTextStyles.caption()),
                  ),
                ],
              ],
            ),
          ),
          // Hint + CTA.
          Positioned(
            left: AppSpacing.screenPadding,
            right: AppSpacing.screenPadding,
            bottom: bottom + 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.navDark.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    "Move and zoom — we'll search what's on screen",
                    style: AppTextStyles.caption(color: Colors.white)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 12),
                PrimaryButton(
                  label: _placeName == null
                      ? 'Search this area'
                      : 'Search in $_placeName',
                  leadingIcon: Icons.search_rounded,
                  onTap: _viewport == null
                      ? null
                      : () => Navigator.of(context).pop(_viewport!.bounds),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

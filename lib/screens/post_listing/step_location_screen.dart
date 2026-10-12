import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/geocoding_service.dart';
import '../../models/geo.dart';
import '../../state/app_scope.dart';
import '../../state/location_service.dart';
import '../../state/post_listing_controller.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/home8_map.dart';
import '../../widgets/pill_button.dart';

/// Step 4 — "Where is your property?" (prototype screen 42).
///
/// Country · City · address (with 🔍 search) · a real Mapbox map with a fixed
/// pin: the seller moves the map until the pin sits on the entrance. The
/// centre is saved as the exact location — private; buyers only ever see the
/// community and an approximate area.
///
/// When the address field is empty, the address under the pin is filled in
/// for them (reverse geocoding).
class StepLocation extends StatefulWidget {
  final PostListingController controller;

  const StepLocation({super.key, required this.controller});

  @override
  State<StepLocation> createState() => _StepLocationState();
}

class _StepLocationState extends State<StepLocation> {
  PostListingController get _c => widget.controller;

  late final TextEditingController _address =
      TextEditingController(text: _c.draft.address);

  final Home8MapController _map = Home8MapController();
  final GeocodingService _geocoder = GeocodingService();

  bool _locating = false;
  Timer? _lookupDebounce;
  int _lookupId = 0;

  List<PlaceSuggestion> _results = const [];
  bool _searching = false;

  /// The camera is about to move for the seller (my location, a search
  /// result) — that move places the pin too.
  bool _appMove = false;

  late final GeoPoint _start =
      _c.draft.latitude != null && _c.draft.longitude != null
          ? GeoPoint(_c.draft.latitude!, _c.draft.longitude!)
          : marketCenter(_c.draft.countryCode);

  late final bool _startedWithPin = _c.draft.latitude != null;

  @override
  void dispose() {
    _lookupDebounce?.cancel();
    _address.dispose();
    super.dispose();
  }

  /// Cities per market — a short curated list so the same city is always
  /// spelled the same way (search matches on it).
  List<String> get _cities => switch (_c.draft.countryCode) {
        'AE' => const ['Dubai', 'Abu Dhabi', 'Sharjah', 'Ajman', 'Ras Al Khaimah'],
        'SA' => const ['Riyadh', 'Jeddah', 'Dammam', 'Mecca', 'Medina'],
        'QA' => const ['Doha', 'Al Rayyan', 'Al Wakrah'],
        'PK' => const ['Karachi', 'Lahore', 'Islamabad', 'Rawalpindi', 'Multan'],
        'GB' => const ['London', 'Manchester', 'Birmingham'],
        'US' => const ['New York', 'Los Angeles', 'Chicago'],
        'CA' => const ['Toronto', 'Vancouver', 'Montreal'],
        'AU' => const ['Sydney', 'Melbourne', 'Brisbane'],
        'NZ' => const ['Auckland', 'Wellington', 'Christchurch'],
        _ => const [],
      };

  Future<void> _moveTo(GeoPoint point, {double zoom = 17}) async {
    _appMove = true;
    await _map.flyTo(point, zoom: zoom);
  }

  void _onMapIdle(MapViewport viewport) {
    if (!viewport.movedByUser && !_appMove) return;
    _appMove = false;
    _c.edit((d) => d.copyWith(
          latitude: double.parse(viewport.center.lat.toStringAsFixed(6)),
          longitude: double.parse(viewport.center.lng.toStringAsFixed(6)),
        ));
    if (_results.isNotEmpty) setState(() => _results = const []);
    _lookupDebounce?.cancel();
    _lookupDebounce = Timer(
      const Duration(milliseconds: 400),
      () => _lookUp(viewport.center),
    );
  }

  /// Address under the pin → fills the field when it's empty, and the
  /// community (what buyers see) from the map.
  Future<void> _lookUp(GeoPoint point) async {
    final id = ++_lookupId;
    final place = await _geocoder.reverse(point);
    if (!mounted || id != _lookupId || place == null) return;
    final fillAddress = _address.text.trim().isEmpty;
    if (fillAddress) _address.text = place.addressLine;
    _c.edit((d) => d.copyWith(
          address: fillAddress ? place.addressLine : null,
          community: place.community.isNotEmpty ? place.community : null,
          city: _cities.contains(place.city) ? place.city : null,
        ));
  }

  Future<void> _searchAddress() async {
    FocusScope.of(context).unfocus();
    final q = _address.text.trim();
    if (q.length < 3) return;
    setState(() => _searching = true);
    final d = _c.draft;
    final results = await _geocoder.search(
      [q, if (d.city.isNotEmpty) d.city].join(', '),
      countryCode: d.countryCode,
      near: d.latitude != null ? GeoPoint(d.latitude!, d.longitude!) : _start,
    );
    if (!mounted) return;
    setState(() {
      _searching = false;
      _results = results;
    });
    if (results.isEmpty) {
      _tell('No match. Move the map so the pin is on your entrance instead.');
    }
  }

  void _pickResult(PlaceSuggestion place) {
    setState(() => _results = const []);
    _address.text = place.addressLine;
    _c.edit((d) => d.copyWith(
          address: place.addressLine,
          community: place.community.isNotEmpty ? place.community : null,
          city: _cities.contains(place.city) ? place.city : null,
        ));
    _moveTo(place.point);
  }

  Future<void> _useMyLocation() async {
    setState(() => _locating = true);
    final result = await const LocationService().requestAndResolve();
    if (!mounted) return;
    setState(() => _locating = false);

    final place = result.place;
    if (place != null) {
      _c.edit((d) => d.copyWith(
            city: _cities.contains(place.city) ? place.city : null,
            latitude: place.latitude,
            longitude: place.longitude,
          ));
      _moveTo(GeoPoint(place.latitude, place.longitude));
      return;
    }
    _tell(switch (result.outcome) {
      LocationOutcome.denied ||
      LocationOutcome.deniedForever =>
        'Location is off for Home8. Move the map to your entrance instead.',
      LocationOutcome.serviceDisabled =>
        'Turn on location services, or move the map to your entrance.',
      _ => "Couldn't get your location. Move the map to your entrance.",
    });
  }

  void _tell(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.navDark,
      ));
  }

  @override
  Widget build(BuildContext context) {
    final draft = _c.draft;
    final appMarket = AppScope.watch(context).market;
    final cities = _cities;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: AppSelectField<Market>(
                value: Market.values.firstWhere(
                  (m) => m.code == draft.countryCode,
                  orElse: () => appMarket,
                ),
                options: Market.values,
                labelOf: (m) => m.label,
                leadingOf: (m) => Image.asset(
                  m.flagAsset,
                  width: 24,
                  height: 18,
                  fit: BoxFit.cover,
                  cacheWidth: 72,
                ),
                onChanged: (m) {
                  if (m.code == draft.countryCode) return;
                  _c.edit((d) => d.copyWith(
                        countryCode: m.code,
                        city: '',
                        currency: m.currency,
                        community: '',
                        // A pin in the old country means nothing now.
                        clearLocation: true,
                      ));
                  setState(() => _results = const []);
                  _map.flyTo(marketCenter(m.code), zoom: 11);
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: cities.isEmpty
                  ? const _EmptyCityField()
                  : AppSelectField<String>(
                      value:
                          cities.contains(draft.city) ? draft.city : cities.first,
                      options: cities,
                      labelOf: (c) => c,
                      onChanged: (c) => _c.edit((d) => d.copyWith(city: c)),
                    ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        AppTextField(
          controller: _address,
          pill: true,
          icon: Icons.apartment_rounded,
          hint: 'Building, street and community',
          textCapitalization: TextCapitalization.words,
          onChanged: (text) => _c.edit((d) => d.copyWith(address: text)),
          trailing: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _searching ? null : _searchAddress,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: _searching
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(AppColors.primary),
                      ),
                    )
                  : const Icon(Icons.search_rounded,
                      size: 22, color: AppColors.inkMuted),
            ),
          ),
        ),
        if (_results.isNotEmpty) ...[
          const SizedBox(height: 8),
          _SearchResults(results: _results, onPick: _pickResult),
        ],
        const SizedBox(height: 16),
        _PinMap(
          controller: _map,
          start: _start,
          startZoom: _startedWithPin ? 17 : 11,
          locating: _locating,
          onUseMyLocation: _useMyLocation,
          onIdle: _onMapIdle,
        ),
        if (draft.latitude == null) ...[
          const SizedBox(height: 10),
          Text('Move the map so the pin sits on your entrance.',
              style: AppTextStyles.caption()),
        ],
      ],
    );
  }
}

/// Shown for a market with no city list yet.
class _EmptyCityField extends StatelessWidget {
  const _EmptyCityField();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: AlignmentDirectional.centerStart,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.line),
      ),
      child: Text('Launching soon',
          style: AppTextStyles.body(color: AppColors.inkMuted)),
    );
  }
}

/// The map with the fixed pin and the "Drag pin to exact entrance" tooltip,
/// as designed. The pin never moves; the map moves under it.
class _PinMap extends StatelessWidget {
  final Home8MapController controller;
  final GeoPoint start;
  final double startZoom;
  final bool locating;
  final VoidCallback onUseMyLocation;
  final ValueChanged<MapViewport> onIdle;

  const _PinMap({
    required this.controller,
    required this.start,
    required this.startZoom,
    required this.locating,
    required this.onUseMyLocation,
    required this.onIdle,
  });

  static const double _pin = 48;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg + 4),
      child: AspectRatio(
        aspectRatio: 1.2,
        child: LayoutBuilder(
          builder: (context, box) {
            final cy = box.maxHeight / 2;
            return Stack(
              children: [
                Positioned.fill(
                  child: Home8Map(
                    controller: controller,
                    initialCenter: start,
                    initialZoom: startZoom,
                    // Inside a scrolling page: drags move the map.
                    claimGestures: true,
                    onViewportIdle: onIdle,
                  ),
                ),
                // Tooltip + stem, sitting on top of the pin.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: box.maxHeight - (cy - _pin / 2),
                  child: IgnorePointer(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 9),
                          decoration: BoxDecoration(
                            color: AppColors.navDark,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'Drag pin to exact entrance',
                            style: AppTextStyles.caption(color: Colors.white)
                                .copyWith(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13.5),
                          ),
                        ),
                        Container(
                            width: 2, height: 12, color: AppColors.navDark),
                      ],
                    ),
                  ),
                ),
                // The pin, centred exactly on the map centre.
                Positioned(
                  left: box.maxWidth / 2 - _pin / 2,
                  top: cy - _pin / 2,
                  child: IgnorePointer(
                    child: Container(
                      width: _pin,
                      height: _pin,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 5),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.ink.withValues(alpha: 0.28),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                PositionedDirectional(
                  end: 12,
                  bottom: 12,
                  child: Pressable(
                    onTap: locating ? null : onUseMyLocation,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 11),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.ink.withValues(alpha: 0.12),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (locating)
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    AppColors.primary),
                              ),
                            )
                          else
                            const Icon(Icons.my_location_rounded,
                                size: 17, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Text('Use my location',
                              style: AppTextStyles.bodyStrong()
                                  .copyWith(fontSize: 14.5)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Matches for the typed address.
class _SearchResults extends StatelessWidget {
  final List<PlaceSuggestion> results;
  final ValueChanged<PlaceSuggestion> onPick;

  const _SearchResults({required this.results, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          for (var i = 0; i < results.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.line),
            InkWell(
              onTap: () => onPick(results[i]),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s4, vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.place_outlined,
                        size: 20, color: AppColors.inkMuted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(results[i].name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.bodyStrong()),
                          if (results[i].context.isNotEmpty)
                            Text(results[i].context,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.caption()),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

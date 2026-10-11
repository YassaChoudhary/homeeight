import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/geocoding_service.dart';
import '../../models/geo.dart';
import '../../models/listing_draft.dart';
import '../../state/app_scope.dart';
import '../../state/location_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/home8_map.dart';
import '../../widgets/pill_button.dart';
import 'post_listing_flow.dart';

/// Screen 36 — "Where is your property?".
///
/// ## Why this is a route and not a step
///
/// The Figma numbers four steps but the Preview screen offers five edit chips,
/// Location among them. The resolution that fits both: the address lives on
/// Basics, and this screen refines it. So it's pushed from the Map link, shows
/// the same progress bar filled to step 1, and pops with the updated draft.
///
/// It returns a [ListingDraft] rather than mutating the controller, so backing
/// out with the system gesture leaves the address exactly as it was.
class StepLocationScreen extends StatefulWidget {
  final ListingDraft draft;

  const StepLocationScreen({super.key, required this.draft});

  @override
  State<StepLocationScreen> createState() => _StepLocationScreenState();
}

class _StepLocationScreenState extends State<StepLocationScreen> {
  late ListingDraft _draft = widget.draft;
  late final TextEditingController _address =
      TextEditingController(text: widget.draft.address);

  bool _locating = false;

  final Home8MapController _map = Home8MapController();
  final GeocodingService _geocoder = GeocodingService();

  /// Address under the pin, from reverse geocoding. Offered as a one-tap
  /// fill for the address field — never written without the seller seeing it.
  PlaceSuggestion? _underPin;
  bool _lookingUp = false;
  Timer? _lookupDebounce;
  int _lookupId = 0;

  /// Results of searching the typed address.
  List<PlaceSuggestion> _results = const [];
  bool _searching = false;

  /// The camera is about to move because the app moved it for the seller
  /// (my location, a search result) — that move places the pin too.
  bool _appMove = false;

  /// Where the map opens: the saved pin, else the market's main city.
  late final GeoPoint _start = _draft.latitude != null && _draft.longitude != null
      ? GeoPoint(_draft.latitude!, _draft.longitude!)
      : marketCenter(_draft.countryCode);

  bool get _hasPin => _draft.latitude != null && _draft.longitude != null;

  @override
  void dispose() {
    _lookupDebounce?.cancel();
    _address.dispose();
    super.dispose();
  }

  Future<void> _moveTo(GeoPoint point, {double zoom = 17}) async {
    _appMove = true;
    await _map.flyTo(point, zoom: zoom);
  }

  /// The map stopped. If the seller moved it (or the app did on their
  /// behalf), the centre is the new pin.
  void _onMapIdle(MapViewport viewport) {
    if (!viewport.movedByUser && !_appMove) return;
    _appMove = false;
    setState(() {
      _draft = _draft.copyWith(
        latitude: double.parse(viewport.center.lat.toStringAsFixed(6)),
        longitude: double.parse(viewport.center.lng.toStringAsFixed(6)),
      );
      _results = const [];
    });
    _lookupDebounce?.cancel();
    _lookupDebounce = Timer(
      const Duration(milliseconds: 350),
      () => _lookUp(viewport.center),
    );
  }

  Future<void> _lookUp(GeoPoint point) async {
    final id = ++_lookupId;
    setState(() => _lookingUp = true);
    final place = await _geocoder.reverse(point);
    if (!mounted || id != _lookupId) return;
    setState(() {
      _lookingUp = false;
      _underPin = place;
    });
    // An empty field gets filled straight away; a typed one is left alone
    // and the suggestion is offered instead.
    if (place != null && _address.text.trim().isEmpty) _useSuggestion(place);
  }

  void _useSuggestion(PlaceSuggestion place) {
    setState(() {
      _address.text = place.addressLine;
      _draft = _draft.copyWith(
        community: place.community.isNotEmpty ? place.community : null,
        city: _cities.contains(place.city) ? place.city : null,
      );
    });
  }

  Future<void> _searchAddress() async {
    FocusScope.of(context).unfocus();
    final q = _address.text.trim();
    if (q.length < 3) return;
    setState(() => _searching = true);
    final results = await _geocoder.search(
      q,
      countryCode: _draft.countryCode,
      near: _hasPin ? GeoPoint(_draft.latitude!, _draft.longitude!) : _start,
    );
    if (!mounted) return;
    setState(() {
      _searching = false;
      _results = results;
    });
    if (results.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('No match. Move the map to place the pin instead.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.navDark,
        ));
    }
  }

  void _pickResult(PlaceSuggestion place) {
    setState(() {
      _results = const [];
      _address.text = place.addressLine;
      _draft = _draft.copyWith(
        community: place.community.isNotEmpty ? place.community : null,
        city: _cities.contains(place.city) ? place.city : null,
      );
    });
    _moveTo(place.point);
  }

  /// Cities offered per market.
  ///
  /// Deliberately a short curated list rather than a geocoder lookup: a free
  /// text city produces "dubai", "Dubai " and "DXB" as three different places
  /// in the data, and the search side matches on exact area names.
  List<String> get _cities => switch (_draft.countryCode) {
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

  /// "Use my location" — reuses the same wrapper the Home hero uses, so
  /// permission handling exists in exactly one place.
  Future<void> _useMyLocation() async {
    setState(() => _locating = true);
    final result = await const LocationService().requestAndResolve();
    if (!mounted) return;

    final place = result.place;
    setState(() {
      _locating = false;
      if (place == null) return;
      _draft = _draft.copyWith(
        city: place.city.isEmpty ? _draft.city : place.city,
        latitude: place.latitude,
        longitude: place.longitude,
      );
    });
    if (place != null) {
      _moveTo(GeoPoint(place.latitude, place.longitude));
    }

    if (place != null || !mounted) return;
    // Every failure path is a LocationOutcome, never a throw — say what
    // happened rather than leaving the pin where it was with no explanation.
    final message = switch (result.outcome) {
      LocationOutcome.denied ||
      LocationOutcome.deniedForever =>
        'Location is off for Home8. Type the address instead.',
      LocationOutcome.serviceDisabled =>
        'Turn on location services, or type the address instead.',
      _ => "Couldn't get your location. Type the address instead.",
    };
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.navDark,
        ),
      );
  }

  void _confirm() {
    final address = _address.text.trim();
    Navigator.of(context).pop(
      _draft.copyWith(
        address: address,
        // The community is what buyers see; derived from the address's last
        // meaningful segment when the user hasn't set one explicitly. A real
        // geocoder replaces this — it's a display fallback, not a data model.
        community: _draft.community.isNotEmpty
            ? _draft.community
            : _communityFrom(address),
      ),
    );
  }

  static String _communityFrom(String address) {
    final parts = address
        .split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.length < 2) return parts.isEmpty ? '' : parts.first;
    return parts[1];
  }

  @override
  Widget build(BuildContext context) {
    final markets = AppScope.watch(context);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Row(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).maybePop(),
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(Icons.arrow_back_rounded,
                          color: AppColors.ink, size: 24),
                    ),
                  ),
                  Expanded(
                    child: Text('Post a listing',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.h1().copyWith(fontSize: 21)),
                  ),
                  const SizedBox(width: 44),
                ],
              ),
            ),
            const Padding(
              padding:
                  EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
              child: StepProgressBar(current: PostStep.location),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenPadding, 18, AppSpacing.screenPadding, 24),
                children: [
                  Text('LOCATION',
                      style: AppTextStyles.micro(color: AppColors.primary)
                          .copyWith(fontSize: 12.5, letterSpacing: 0.8)),
                  const SizedBox(height: 6),
                  Text('Where is your property?',
                      style: AppTextStyles.display().copyWith(fontSize: 27)),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: AppSelectField<Market>(
                          value: Market.values.firstWhere(
                            (m) => m.code == _draft.countryCode,
                            orElse: () => markets.market,
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
                          onChanged: (m) => setState(() {
                            // Changing country invalidates the city, for the
                            // same reason changing nature invalidates the type.
                            _draft = _draft.copyWith(
                              countryCode: m.code,
                              city: '',
                              currency: m.currency,
                              // A pin in the old country is meaningless now.
                              clearLocation: m.code != _draft.countryCode,
                            );
                            _results = const [];
                            _underPin = null;
                            // Show the new country; the seller then places
                            // the pin (this move doesn't place it).
                            _map.flyTo(marketCenter(m.code), zoom: 11);
                          }),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _cities.isEmpty
                            ? const _EmptyCityField()
                            : AppSelectField<String>(
                                value: _cities.contains(_draft.city)
                                    ? _draft.city
                                    : _cities.first,
                                options: _cities,
                                labelOf: (c) => c,
                                onChanged: (c) =>
                                    setState(() => _draft = _draft.copyWith(city: c)),
                              ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  AppTextField(
                    controller: _address,
                    icon: Icons.apartment_rounded,
                    hint: 'Building, street and community',
                    onChanged: (_) => setState(() {}),
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
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      AppColors.primary),
                                ),
                              )
                            : const Icon(Icons.search_rounded,
                                size: 22, color: AppColors.primary),
                      ),
                    ),
                  ),
                  if (_results.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _SearchResults(results: _results, onPick: _pickResult),
                  ],
                  const SizedBox(height: 14),
                  _PinMap(
                    controller: _map,
                    start: _start,
                    startZoom: _hasPin ? 17 : 11,
                    hasPin: _hasPin,
                    locating: _locating,
                    onUseMyLocation: _useMyLocation,
                    onIdle: _onMapIdle,
                  ),
                  const SizedBox(height: 10),
                  _UnderPinRow(
                    hasPin: _hasPin,
                    loading: _lookingUp,
                    place: _underPin,
                    alreadyUsed: _underPin != null &&
                        _address.text.trim() == _underPin!.addressLine,
                    onUse: _underPin == null
                        ? null
                        : () => _useSuggestion(_underPin!),
                  ),
                  const SizedBox(height: 16),
                  const InfoNote(
                    message: 'Buyers see the community only — the exact pin is '
                        'revealed after you accept an enquiry.',
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenPadding, 4, AppSpacing.screenPadding, 12),
              child: PrimaryButton(
                label: 'Confirm location',
                onTap: _address.text.trim().isEmpty ? null : _confirm,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown for a market with no curated city list yet.
///
/// Reads "Launching soon" rather than rendering an empty dropdown the user can
/// tap and get nothing from — the same rule `Market.isLaunched` follows on the
/// buyer side.
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
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.line),
      ),
      child: Text('Launching soon',
          style: AppTextStyles.body(color: AppColors.inkMuted)),
    );
  }
}

/// The real map with a fixed pin in the middle: the seller moves the map
/// under the pin to the building's entrance. The centre becomes the listing's
/// exact location — stored privately; buyers see an approximate area.
class _PinMap extends StatelessWidget {
  final Home8MapController controller;
  final GeoPoint start;
  final double startZoom;
  final bool hasPin;
  final bool locating;
  final VoidCallback onUseMyLocation;
  final ValueChanged<MapViewport> onIdle;

  const _PinMap({
    required this.controller,
    required this.start,
    required this.startZoom,
    required this.hasPin,
    required this.locating,
    required this.onUseMyLocation,
    required this.onIdle,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: SizedBox(
        height: 300,
        child: Stack(
          children: [
            Positioned.fill(
              child: Home8Map(
                controller: controller,
                initialCenter: start,
                initialZoom: startZoom,
                // Inside a scrolling page: drags move the map, not the page.
                claimGestures: true,
                onViewportIdle: onIdle,
              ),
            ),
            // The pin never moves; the map moves under it. Its tip sits on
            // the exact centre of the map.
            IgnorePointer(
              child: Center(
                child: Transform.translate(
                  offset: const Offset(0, -38),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: AppColors.navDark,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Text(
                          hasPin
                              ? 'Move the map to adjust'
                              : 'Move the map to your entrance',
                          style: AppTextStyles.caption(color: Colors.white)
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Icon(Icons.location_on_rounded,
                          size: 44, color: AppColors.primary,
                          shadows: [
                            Shadow(
                              color: Color(0x55000000),
                              blurRadius: 8,
                              offset: Offset(0, 3),
                            ),
                          ]),
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
                      horizontal: 14, vertical: 10),
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
        ),
      ),
    );
  }
}

/// Under the map: the address at the pin, with "Use" to fill the field.
class _UnderPinRow extends StatelessWidget {
  final bool hasPin;
  final bool loading;
  final PlaceSuggestion? place;
  final bool alreadyUsed;
  final VoidCallback? onUse;

  const _UnderPinRow({
    required this.hasPin,
    required this.loading,
    required this.place,
    required this.alreadyUsed,
    required this.onUse,
  });

  @override
  Widget build(BuildContext context) {
    final String text;
    if (!hasPin) {
      text = 'No pin yet. Move the map or search the address.';
    } else if (loading) {
      text = 'Finding the address…';
    } else if (place != null) {
      text = place!.addressLine;
    } else {
      text = 'Pin placed.';
    }
    return Row(
      children: [
        Icon(
          hasPin ? Icons.check_circle_rounded : Icons.info_outline_rounded,
          size: 18,
          color: hasPin ? AppColors.primary : AppColors.inkMuted,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.caption(
                color: hasPin ? AppColors.ink : AppColors.inkMuted),
          ),
        ),
        if (place != null && !loading && !alreadyUsed)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onUse,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 0, 6),
              child: Text('Use address',
                  style: AppTextStyles.bodyStrong(color: AppColors.primary)),
            ),
          ),
      ],
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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

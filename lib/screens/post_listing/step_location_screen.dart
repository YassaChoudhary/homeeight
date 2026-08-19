import 'package:flutter/material.dart';

import '../../models/listing_draft.dart';
import '../../state/app_scope.dart';
import '../../state/location_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/form_fields.dart';
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

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
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
                            );
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
                    trailing: const Icon(Icons.search_rounded,
                        size: 20, color: AppColors.inkMuted),
                  ),
                  const SizedBox(height: 14),
                  _MapPin(
                    locating: _locating,
                    onUseMyLocation: _useMyLocation,
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

/// Fake map with a draggable-looking pin.
///
/// No map SDK is wired anywhere in the app — `_MapPlaceholder` on the property
/// detail screen is the same stand-in. This is deliberately one isolated
/// widget so swapping in google_maps_flutter later is a single replacement,
/// not a hunt. The tooltip and the "Use my location" chip are real affordances
/// that will survive that swap.
class _MapPin extends StatelessWidget {
  final bool locating;
  final VoidCallback onUseMyLocation;

  const _MapPin({required this.locating, required this.onUseMyLocation});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        height: 260,
        decoration: BoxDecoration(
          color: const Color(0xFFE8EEE9),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            CustomPaint(size: Size.infinite, painter: _MapGridPainter()),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: AppColors.navDark,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Text('Drag pin to exact entrance',
                        style: AppTextStyles.caption(color: Colors.white)
                            .copyWith(fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.ink.withValues(alpha: 0.25),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                  ),
                ],
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

class _MapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.12)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 22) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += 22) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

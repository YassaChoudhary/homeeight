import 'dart:async';

import 'package:flutter/material.dart';

import '../models/geo.dart';
import '../models/property.dart';
import '../models/property_category.dart';
import '../models/search_query.dart';
import '../state/app_scope.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../widgets/pill_button.dart';
import 'map/map_area_screen.dart';

/// Shown at the top of the type dropdown so a chosen type can be cleared.
/// Maps to `propertyType: null`, i.e. no type filter at all.
const _anyType = 'Any';

const _offPlanPurpose = ['All', 'Initial Sale', 'Resale', 'Assignment'];
const _percentBands = ['Under 25%', '25 to 50%', '51 to 75%', '76 to 100%'];
const _handoverYears = ['2026', '2027', '2028', '2029'];
const _projectStatus = ['Under Construction', 'Completed'];
const _amenityOptions = [
  'Shared Pool',
  'Private Gym',
  'Covered Parking',
  'Sea View',
  "Maid's Room",
];

/// Screen 13. Edits a local copy of the caller's [SearchQuery] and returns it
/// on Apply — no global mutation, and the caller decides what to do with it.
///
/// The footer count is a real query against the repository, debounced as the
/// user drags sliders. That's the same call the results screen makes, so
/// "Show N Results" can never disagree with what's on the next screen.
class FiltersSheet extends StatefulWidget {
  final SearchQuery query;
  const FiltersSheet({super.key, this.query = const SearchQuery()});

  @override
  State<FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<FiltersSheet> {
  late SearchQuery _draft = widget.query;
  late final TextEditingController _developer =
      TextEditingController(text: widget.query.developer ?? '');

  final ValueNotifier<int?> _count = ValueNotifier<int?>(null);
  Timer? _debounce;

  static const int _priceCeiling = 300000;
  static const int _buaFloor = 100;
  static const int _buaCeiling = 5000;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _recount());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _developer.dispose();
    _count.dispose();
    super.dispose();
  }

  /// Categories valid for the currently selected nature.
  List<PropertyCategory> get _types =>
      PropertyCategory.forSegment(_draft.segment);

  /// Dropdown value: the selected type's display title, or 'Any'.
  ///
  /// Resolved through the catalogue rather than stored, so a type that isn't
  /// valid for the current nature can never render as selected.
  String get _typeValue =>
      PropertyCategory.lookup(_draft.segment, _draft.propertyType)?.title ??
      _anyType;

  /// Switching nature has to clear an incompatible type.
  ///
  /// "Offices" is meaningless once you're browsing residential, and leaving it
  /// set would silently return zero results with no visible cause — the
  /// dropdown would read "Any" while the query still filtered on `office`.
  void _setSegment(PropertySegment segment) {
    if (_draft.segment == segment) return;
    final stillValid =
        PropertyCategory.lookup(segment, _draft.propertyType) != null;
    setState(() {
      _draft = _draft.copyWith(
        segment: segment,
        propertyType: stillValid ? _draft.propertyType : null,
        clearPropertyType: !stillValid,
      );
    });
    _recount();
  }

  void _setType(String title) {
    if (title == _anyType) {
      setState(() => _draft = _draft.copyWith(clearPropertyType: true));
      _recount();
      return;
    }
    final match = _types.firstWhere((c) => c.title == title);
    _patch((q) => q.copyWith(propertyType: match.wire));
  }

  void _patch(SearchQuery Function(SearchQuery q) transform) {
    setState(() => _draft = transform(_draft));
    _recount();
  }

  void _recount() {
    _debounce?.cancel();
    _count.value = null;
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      try {
        final page = await AppScope.repositoryOf(context)
            .search(_draft.copyWith(page: 1, pageSize: 1));
        if (mounted) _count.value = page.total;
      } catch (_) {
        if (mounted) _count.value = -1;
      }
    });
  }

  void _reset() {
    setState(() {
      // Nature survives a reset (it's a mode, not a filter); type does not.
      _draft = SearchQuery(
        purpose: _draft.purpose,
        segment: _draft.segment,
        community: _draft.community,
        term: _draft.term,
      );
      _developer.clear();
    });
    _recount();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (context, scrollController) {
        return ClipRRect(
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
          child: Container(
            color: AppColors.surface,
            child: Column(
              children: [
                const SheetDragHandle(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => Navigator.of(context).pop(),
                        child: const Icon(Icons.close_rounded,
                            color: AppColors.ink),
                      ),
                      Expanded(
                        child: Text('Filters',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.h1()),
                      ),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _reset,
                        child: Text('Reset',
                            style: AppTextStyles.bodyStrong(
                                color: AppColors.inkMuted)),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                    children: _draft.isOffPlan
                        ? [..._commonFields(), ..._offPlanFields()]
                        : [..._commonFields(), ..._standardFields()],
                  ),
                ),
                _Footer(
                  count: _count,
                  onApply: () => Navigator.of(context).pop(_draft),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _selectOnMap() async {
    final market = AppScope.of(context).appState.market;
    final bounds = await Navigator.of(context).push<GeoBounds>(
      MaterialPageRoute(
        builder: (_) => MapAreaScreen(
          fallbackCenter: marketCenter(market.code),
          initialBounds: _draft.bounds,
        ),
      ),
    );
    if (bounds == null || !mounted) return;
    setState(() => _draft = _draft.copyWith(bounds: bounds));
    _recount();
  }

  void _clearMapArea() {
    setState(() => _draft = _draft.copyWith(clearBounds: true));
    _recount();
  }

  List<Widget> _commonFields() {
    final hasArea = _draft.bounds != null;
    return [
      Row(
        children: [
          Text('Location', style: AppTextStyles.h2()),
          const Spacer(),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _selectOnMap,
            child: Text(hasArea ? 'Change on map' : 'Select on map',
                style: AppTextStyles.bodyStrong(color: AppColors.primary)),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          children: [
            Icon(hasArea ? Icons.map_outlined : Icons.location_on_outlined,
                color: hasArea ? AppColors.primary : AppColors.inkMuted,
                size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                hasArea
                    ? 'Area picked on map'
                    : _draft.community ?? 'Anywhere',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyStrong(),
              ),
            ),
            if (hasArea)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _clearMapArea,
                child: const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.close_rounded,
                      size: 18, color: AppColors.inkMuted),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 22),
      Text('Purpose', style: AppTextStyles.h2()),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: _PurposePill(
              label: 'For Rent',
              active: _draft.purpose == Purpose.rent,
              onTap: () => _patch((q) => q.copyWith(purpose: Purpose.rent)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _PurposePill(
              label: 'For Sale',
              active: _draft.purpose == Purpose.sale,
              onTap: () => _patch((q) => q.copyWith(purpose: Purpose.sale)),
            ),
          ),
        ],
      ),
      const SizedBox(height: 22),
      Text('Property Nature', style: AppTextStyles.h2()),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: _PurposePill(
              label: 'Residential',
              active: _draft.segment == PropertySegment.residential,
              onTap: () => _setSegment(PropertySegment.residential),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _PurposePill(
              label: 'Commercial',
              active: _draft.segment == PropertySegment.commercial,
              onTap: () => _setSegment(PropertySegment.commercial),
            ),
          ),
        ],
      ),
      const SizedBox(height: 22),
      Text('Property Type', style: AppTextStyles.h2()),
      const SizedBox(height: 10),
      // Options come from the same catalogue the Home grid renders, so a type
      // tapped on Home is always selectable here and vice versa.
      _Dropdown(
        value: _typeValue,
        options: [_anyType, for (final c in _types) c.title],
        onChanged: _setType,
      ),
      const SizedBox(height: 22),
      Row(
        children: [
          Text('Price Range', style: AppTextStyles.h2()),
          const Spacer(),
          AppStateBuilder(
            builder: (context, state) => Row(
              children: [
                Text(state.currency,
                    style: AppTextStyles.bodyStrong(color: AppColors.primary)),
                const Icon(Icons.keyboard_arrow_down_rounded,
                    color: AppColors.primary),
              ],
            ),
          ),
        ],
      ),
      RangeSlider(
        values: RangeValues(
          (_draft.priceMin ?? 0).toDouble().clamp(0, _priceCeiling.toDouble()),
          (_draft.priceMax ?? _priceCeiling)
              .toDouble()
              .clamp(0, _priceCeiling.toDouble()),
        ),
        min: 0,
        max: _priceCeiling.toDouble(),
        divisions: 60,
        activeColor: AppColors.primary,
        inactiveColor: AppColors.line,
        onChanged: (v) => _patch((q) => q.copyWith(
              priceMin: v.start.round(),
              priceMax: v.end.round(),
            )),
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('AED ${formatThousands(_draft.priceMin ?? 0)}',
              style: AppTextStyles.bodyStrong()),
          Text(
            'AED ${formatThousands(_draft.priceMax ?? _priceCeiling)}'
            '${_draft.purpose == Purpose.rent ? " / year" : ""}',
            style: AppTextStyles.bodyStrong(),
          ),
        ],
      ),
    ];
  }

  List<Widget> _standardFields() {
    return [
      const SizedBox(height: 18),
      Row(
        children: [
          Expanded(
            child: _LabeledDropdown(
              label: 'Bedrooms',
              value: _draft.beds?.toString() ?? 'Any',
              options: const ['Any', '1', '2', '3', '4', '5'],
              onChanged: (v) => _patch((q) => v == 'Any'
                  ? q.copyWith(clearBeds: true)
                  : q.copyWith(beds: int.parse(v))),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _LabeledDropdown(
              label: 'Bathrooms',
              value: _draft.baths?.toString() ?? 'Any',
              options: const ['Any', '1', '2', '3', '4'],
              onChanged: (v) => _patch((q) => v == 'Any'
                  ? q.copyWith(clearBaths: true)
                  : q.copyWith(baths: int.parse(v))),
            ),
          ),
        ],
      ),
      const SizedBox(height: 22),
      Text('Area Size (BUA, sqft)', style: AppTextStyles.h2()),
      RangeSlider(
        values: RangeValues(
          (_draft.buaMin ?? _buaFloor)
              .toDouble()
              .clamp(_buaFloor.toDouble(), _buaCeiling.toDouble()),
          (_draft.buaMax ?? 2000)
              .toDouble()
              .clamp(_buaFloor.toDouble(), _buaCeiling.toDouble()),
        ),
        min: _buaFloor.toDouble(),
        max: _buaCeiling.toDouble(),
        divisions: 49,
        activeColor: AppColors.primary,
        inactiveColor: AppColors.line,
        onChanged: (v) => _patch((q) => q.copyWith(
              buaMin: v.start.round(),
              buaMax: v.end.round(),
            )),
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('${_draft.buaMin ?? _buaFloor}',
              style: AppTextStyles.bodyStrong()),
          Text('${_draft.buaMax ?? 2000}', style: AppTextStyles.bodyStrong()),
        ],
      ),
      const SizedBox(height: 22),
      Text('Furnishing', style: AppTextStyles.h2()),
      const SizedBox(height: 10),
      Row(
        children: [
          for (final option in ['Any', 'Furnished', 'Unfurnished'])
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 10),
              child: _ChoicePill(
                label: option,
                active: (_draft.furnishing ?? 'Any') == option,
                onTap: () => _patch((q) => q.copyWith(furnishing: option)),
              ),
            ),
        ],
      ),
      const SizedBox(height: 22),
      Text('Amenities', style: AppTextStyles.h2()),
      const SizedBox(height: 10),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final amenity in _amenityOptions)
            _AmenityChip(
              label: amenity,
              selected: _draft.amenities.contains(amenity),
              onTap: () => _patch((q) {
                final next = Set<String>.from(q.amenities);
                next.contains(amenity)
                    ? next.remove(amenity)
                    : next.add(amenity);
                return q.copyWith(amenities: next);
              }),
            ),
        ],
      ),
      const SizedBox(height: 22),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.primaryTint,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.shield_rounded,
                  color: Colors.white, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Verified only', style: AppTextStyles.bodyStrong()),
                  Text('Permit-checked listings',
                      style: AppTextStyles.caption()),
                ],
              ),
            ),
            Switch(
              value: _draft.verifiedOnly,
              activeThumbColor: Colors.white,
              activeTrackColor: AppColors.primary,
              onChanged: (v) => _patch((q) => q.copyWith(verifiedOnly: v)),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _offPlanFields() {
    return [
      const SizedBox(height: 22),
      Text('Sale Type', style: AppTextStyles.h2()),
      const SizedBox(height: 10),
      _PillRow(
        options: _offPlanPurpose,
        selected: _draft.offPlanPurpose ?? 'All',
        onChanged: (v) => _patch((q) => q.copyWith(offPlanPurpose: v)),
      ),
      const SizedBox(height: 22),
      Text('Project Completion', style: AppTextStyles.h2()),
      const SizedBox(height: 10),
      _PillRow(
        options: _percentBands,
        selected: _draft.projectCompletion ?? _percentBands.first,
        onChanged: (v) => _patch((q) => q.copyWith(projectCompletion: v)),
      ),
      const SizedBox(height: 22),
      Text('Pre-handover Payment', style: AppTextStyles.h2()),
      const SizedBox(height: 10),
      _PillRow(
        options: _percentBands,
        selected: _draft.prehandoverPayment ?? _percentBands.first,
        onChanged: (v) => _patch((q) => q.copyWith(prehandoverPayment: v)),
      ),
      const SizedBox(height: 22),
      Text('Handover', style: AppTextStyles.h2()),
      const SizedBox(height: 10),
      _PillRow(
        options: _handoverYears,
        selected: _draft.handoverYear ?? _handoverYears.first,
        onChanged: (v) => _patch((q) => q.copyWith(handoverYear: v)),
      ),
      const SizedBox(height: 22),
      Text('Project Status', style: AppTextStyles.h2()),
      const SizedBox(height: 10),
      _PillRow(
        options: _projectStatus,
        selected: _draft.projectStatus ?? _projectStatus.first,
        onChanged: (v) => _patch((q) => q.copyWith(projectStatus: v)),
      ),
      const SizedBox(height: 22),
      Text('Developer', style: AppTextStyles.h2()),
      const SizedBox(height: 10),
      Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(999),
        ),
        child: TextField(
          controller: _developer,
          style: AppTextStyles.body(),
          onChanged: (v) => _patch((q) => q.copyWith(developer: v)),
          decoration: InputDecoration(
            border: InputBorder.none,
            hintText: 'e.g. Emaar Properties PJSC',
            hintStyle: AppTextStyles.body(color: AppColors.inkMuted),
          ),
        ),
      ),
    ];
  }
}

class _Footer extends StatelessWidget {
  final ValueNotifier<int?> count;
  final VoidCallback onApply;

  const _Footer({required this.count, required this.onApply});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.paddingOf(context).bottom + 16,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: ValueListenableBuilder<int?>(
        valueListenable: count,
        builder: (context, value, _) {
          final label = switch (value) {
            null => 'Show Results',
            -1 => 'Show Results',
            0 => 'No matches — adjust filters',
            _ => 'Show ${formatThousands(value)} Results',
          };
          return PrimaryButton(
            label: label,
            loading: value == null,
            onTap: onApply,
          );
        },
      ),
    );
  }
}

class _PurposePill extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _PurposePill({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? AppColors.primary : Colors.transparent,
          border: Border.all(color: active ? AppColors.primary : AppColors.line),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: AppTextStyles.bodyStrong(
              color: active ? Colors.white : AppColors.ink),
        ),
      ),
    );
  }
}

class _ChoicePill extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ChoicePill({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: active ? AppColors.primary : Colors.transparent,
          border: Border.all(color: active ? AppColors.primary : AppColors.line),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: AppTextStyles.bodyStrong(
              color: active ? Colors.white : AppColors.ink),
        ),
      ),
    );
  }
}

class _AmenityChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _AmenityChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.accentTint,
          borderRadius: BorderRadius.circular(999),
          border:
              selected ? Border.all(color: AppColors.accent, width: 1.4) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: AppTextStyles.bodyStrong(color: AppColors.ink)),
            if (selected) ...[
              const SizedBox(width: 6),
              const Icon(Icons.check_rounded, size: 15, color: AppColors.accent),
            ],
          ],
        ),
      ),
    );
  }
}

class _PillRow extends StatelessWidget {
  final List<String> options;
  final String selected;
  final ValueChanged<String> onChanged;

  const _PillRow({
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) => _ChoicePill(
          label: options[i],
          active: options[i] == selected,
          onTap: () => onChanged(options[i]),
        ),
      ),
    );
  }
}

class _Dropdown extends StatelessWidget {
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  const _Dropdown({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(999),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          borderRadius: BorderRadius.circular(AppRadius.md),
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              color: AppColors.inkMuted),
          style: AppTextStyles.bodyStrong(),
          items: [
            for (final option in options)
              DropdownMenuItem(
                value: option,
                child: Text(option, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

class _LabeledDropdown extends StatelessWidget {
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  const _LabeledDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.h2()),
        const SizedBox(height: 10),
        _Dropdown(value: value, options: options, onChanged: onChanged),
      ],
    );
  }
}

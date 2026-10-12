import 'dart:async';

import 'package:flutter/material.dart';

import '../models/amenities.dart';
import '../models/geo.dart';
import '../models/property.dart';
import '../models/property_category.dart';
import '../models/search_query.dart';
import '../state/app_scope.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../widgets/form_fields.dart';
import '../widgets/pill_button.dart';
import 'map/map_area_screen.dart';

/// Shown at the top of the type dropdown so a chosen type can be cleared.
/// Maps to `propertyType: null`, i.e. no type filter at all.
const _anyType = 'Any';

const _furnishingOptions = ['Any', 'Furnished', 'Unfurnished', 'Partly'];

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
  late final TextEditingController _priceMin = _numField(widget.query.priceMin);
  late final TextEditingController _priceMax = _numField(widget.query.priceMax);
  late final TextEditingController _buaMin = _numField(widget.query.buaMin);
  late final TextEditingController _buaMax = _numField(widget.query.buaMax);

  static TextEditingController _numField(int? v) => TextEditingController(
      text: v == null ? '' : ThousandsFormatter.group('$v'));

  final ValueNotifier<int?> _count = ValueNotifier<int?>(null);
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _recount());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _priceMin.dispose();
    _priceMax.dispose();
    _buaMin.dispose();
    _buaMax.dispose();
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

  static int? _read(TextEditingController c) {
    final v = ThousandsFormatter.parse(c.text);
    return v == null || v <= 0 ? null : v;
  }

  /// Typed min / max → the query (swapped if entered the wrong way round).
  void _syncPrice() {
    var lo = _read(_priceMin), hi = _read(_priceMax);
    if (lo != null && hi != null && lo > hi) (lo, hi) = (hi, lo);
    _patch((q) => q.copyWith(clearPrice: true, priceMin: lo, priceMax: hi));
  }

  void _syncBua() {
    var lo = _read(_buaMin), hi = _read(_buaMax);
    if (lo != null && hi != null && lo > hi) (lo, hi) = (hi, lo);
    _patch((q) => q.copyWith(clearBua: true, buaMin: lo, buaMax: hi));
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
        term: _draft.term,
        sort: _draft.sort,
      );
      for (final c in [_priceMin, _priceMax, _buaMin, _buaMax]) {
        c.clear();
      }
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
                    children: [..._commonFields(), ..._standardFields()],
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
    setState(() =>
        _draft = _draft.copyWith(bounds: bounds, clearCommunity: true));
    _recount();
  }

  void _clearMapArea() {
    setState(() => _draft =
        _draft.copyWith(clearBounds: true, clearCommunity: true));
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
            if (hasArea || _draft.community != null)
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
      AppStateBuilder(
        builder: (context, state) => Row(
          children: [
            Text('Price Range', style: AppTextStyles.h2()),
            const Spacer(),
            Text(
              _draft.purpose == Purpose.rent
                  ? '${state.currency} · per period'
                  : state.currency,
              style: AppTextStyles.caption(color: AppColors.primary)
                  .copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      _MinMaxRow(
        min: _priceMin,
        max: _priceMax,
        onChanged: _syncPrice,
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
      Text('Built-up Area (sqft)', style: AppTextStyles.h2()),
      const SizedBox(height: 10),
      _MinMaxRow(
        min: _buaMin,
        max: _buaMax,
        onChanged: _syncBua,
      ),
      const SizedBox(height: 22),
      Text('Furnishing', style: AppTextStyles.h2()),
      const SizedBox(height: 10),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final option in _furnishingOptions)
            _ChoicePill(
              label: option,
              active: (_draft.furnishing ?? 'Any') == option,
              onTap: () => _patch((q) => option == 'Any'
                  ? q.copyWith(clearFurnishing: true)
                  : q.copyWith(furnishing: option)),
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
          for (final amenity in Amenities.forSegment(_draft.segment))
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

}

/// Min – Max number inputs with thousands separators.
class _MinMaxRow extends StatelessWidget {
  final TextEditingController min;
  final TextEditingController max;
  final VoidCallback onChanged;

  const _MinMaxRow({
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    Widget field(TextEditingController c, String hint) => Expanded(
          child: AppTextField(
            controller: c,
            pill: true,
            hint: hint,
            keyboardType: TextInputType.number,
            formatters: const [ThousandsFormatter()],
            onChanged: (_) => onChanged(),
          ),
        );
    return Row(
      children: [
        field(min, 'Min'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text('–', style: AppTextStyles.h2()),
        ),
        field(max, 'Max'),
      ],
    );
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

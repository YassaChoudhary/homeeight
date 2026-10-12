import 'dart:async';

import 'package:flutter/material.dart';

import '../models/property.dart';
import '../models/search_query.dart';
import '../state/app_scope.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../widgets/form_fields.dart';
import '../widgets/pill_button.dart';

/// "Search by built-up area" — min / max size (sqft or sqm), quick ranges,
/// and a live count of matching homes. Pops with the query to search.
class BuaSearchSheet extends StatefulWidget {
  final SearchQuery query;

  const BuaSearchSheet({super.key, required this.query});

  static Future<SearchQuery?> show(BuildContext context, SearchQuery query) =>
      showModalBottomSheet<SearchQuery>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => BuaSearchSheet(query: query),
      );

  @override
  State<BuaSearchSheet> createState() => _BuaSearchSheetState();
}

class _BuaSearchSheetState extends State<BuaSearchSheet> {
  static const double _sqmToSqft = 10.7639;

  /// Quick ranges in sqft (null = open end).
  static const List<(String, int?, int?)> _presets = [
    ('Under 500', null, 500),
    ('500 – 1,000', 500, 1000),
    ('1,000 – 2,000', 1000, 2000),
    ('2,000 – 5,000', 2000, 5000),
    ('5,000+', 5000, null),
  ];

  late Purpose _purpose = widget.query.purpose;
  bool _sqm = false;
  late final TextEditingController _min = TextEditingController(
      text: widget.query.buaMin == null
          ? ''
          : ThousandsFormatter.group('${widget.query.buaMin}'));
  late final TextEditingController _max = TextEditingController(
      text: widget.query.buaMax == null
          ? ''
          : ThousandsFormatter.group('${widget.query.buaMax}'));

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
    _min.dispose();
    _max.dispose();
    _count.dispose();
    super.dispose();
  }

  int? _toSqft(String text) {
    final v = ThousandsFormatter.parse(text);
    if (v == null || v <= 0) return null;
    return _sqm ? (v * _sqmToSqft).round() : v;
  }

  SearchQuery get _result {
    var lo = _toSqft(_min.text);
    var hi = _toSqft(_max.text);
    if (lo != null && hi != null && lo > hi) (lo, hi) = (hi, lo);
    return widget.query.copyWith(
      purpose: _purpose,
      clearBua: true,
      buaMin: lo,
      buaMax: hi,
      page: 1,
    );
  }

  void _recount() {
    _debounce?.cancel();
    _count.value = null;
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final page = await AppScope.repositoryOf(context)
            .search(_result.copyWith(page: 1, pageSize: 1));
        if (mounted) _count.value = page.total;
      } catch (_) {
        if (mounted) _count.value = -1;
      }
    });
  }

  void _applyPreset(int? lo, int? hi) {
    String fmt(int? sqft) {
      if (sqft == null) return '';
      final v = _sqm ? (sqft / _sqmToSqft).round() : sqft;
      return ThousandsFormatter.group('$v');
    }

    setState(() {
      _min.text = fmt(lo);
      _max.text = fmt(hi);
    });
    _recount();
  }

  /// Same range, allowing for sqm↔sqft rounding.
  bool _isPreset(int? lo, int? hi) {
    bool same(int? a, int? b) =>
        a == null || b == null ? a == b : (a - b).abs() <= 11;
    return same(_toSqft(_min.text), lo) && same(_toSqft(_max.text), hi);
  }

  void _switchUnit(bool sqm) {
    if (sqm == _sqm) return;
    final lo = _toSqft(_min.text);
    final hi = _toSqft(_max.text);
    setState(() => _sqm = sqm);
    _applyPreset(lo, hi);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenPadding + 4, 0, AppSpacing.screenPadding + 4, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Center(child: SheetDragHandle()),
                const SizedBox(height: 4),
                Text('Search by built-up area', style: AppTextStyles.h1()),
                const SizedBox(height: 4),
                Text('Find homes by their size.',
                    style: AppTextStyles.body(color: AppColors.inkMuted)),
                const SizedBox(height: 20),
                SegmentedControl<Purpose>(
                  options: const [Purpose.rent, Purpose.sale],
                  value: _purpose,
                  labelOf: (p) => p.label,
                  onChanged: (p) {
                    setState(() => _purpose = p);
                    _recount();
                  },
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Text('Size', style: AppTextStyles.h2()),
                    const Spacer(),
                    for (final unit in const [false, true])
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: ChoicePill(
                          label: unit ? 'sqm' : 'sqft',
                          active: _sqm == unit,
                          onTap: () => _switchUnit(unit),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: AppTextField(
                        controller: _min,
                        pill: true,
                        hint: 'Min',
                        keyboardType: TextInputType.number,
                        formatters: const [ThousandsFormatter()],
                        onChanged: (_) {
                          setState(() {});
                          _recount();
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text('–', style: AppTextStyles.h2()),
                    ),
                    Expanded(
                      child: AppTextField(
                        controller: _max,
                        pill: true,
                        hint: 'Max',
                        keyboardType: TextInputType.number,
                        formatters: const [ThousandsFormatter()],
                        onChanged: (_) {
                          setState(() {});
                          _recount();
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final (label, lo, hi) in _presets)
                      ChoicePill(
                        label: _sqm ? _sqmLabel(lo, hi) : '$label sqft',
                        active: _isPreset(lo, hi),
                        onTap: () => _applyPreset(lo, hi),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                ValueListenableBuilder<int?>(
                  valueListenable: _count,
                  builder: (context, count, _) => PrimaryButton(
                    label: count == null
                        ? 'Counting…'
                        : count < 0
                            ? 'Show homes'
                            : count == 0
                                ? 'No homes match'
                                : 'Show ${formatThousands(count)} '
                                    '${count == 1 ? 'home' : 'homes'}',
                    onTap: count == 0 ? null : () => Navigator.of(context).pop(_result),
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: TertiaryButton(
                    label: 'Clear size',
                    onTap: () => _applyPreset(null, null),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _sqmLabel(int? lo, int? hi) {
    String v(int sqft) => formatThousands((sqft / _sqmToSqft).round());
    if (lo == null) return 'Under ${v(hi!)} sqm';
    if (hi == null) return '${v(lo)}+ sqm';
    return '${v(lo)} – ${v(hi)} sqm';
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/app_scope.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import 'pill_button.dart';

/// International dialling code for each market offered in onboarding.
extension MarketDialCode on Market {
  String get dialCode => switch (this) {
        Market.uae => '+971',
        Market.ksa => '+966',
        Market.qatar => '+974',
        Market.pakistan => '+92',
        Market.canada => '+1',
        Market.usa => '+1',
        Market.uk => '+44',
        Market.australia => '+61',
        Market.newZealand => '+64',
      };
}

/// Phone input with a country picker: [flag +971 ▾] [number].
///
/// The countries are the same markets as onboarding. Picking one puts its
/// code in front automatically; the user only types the local number. The
/// value reported through [onChanged] is the full international number,
/// e.g. "+971501234567" — or "" while the local part is empty.
class PhoneNumberField extends StatefulWidget {
  /// Full number to start with ("+971 50 123 4567"), or empty.
  final String initialValue;

  /// Country to show when [initialValue] has no recognisable code.
  final Market defaultMarket;

  final String hint;
  final ValueChanged<String> onChanged;

  const PhoneNumberField({
    super.key,
    required this.initialValue,
    required this.defaultMarket,
    required this.onChanged,
    this.hint = '50 123 4567',
  });

  /// Splits "+971501234567" into (UAE, "501234567"). Prefers [preferred]
  /// when two markets share a code (+1 for Canada and the USA).
  static (Market, String) split(String value, Market preferred) {
    final clean = value.replaceAll(RegExp(r'[^0-9+]'), '');
    if (!clean.startsWith('+')) {
      return (preferred, clean.replaceAll('+', ''));
    }
    final candidates = [
      preferred,
      ...Market.values.where((m) => m != preferred),
    ]..sort((a, b) => b.dialCode.length.compareTo(a.dialCode.length));
    // Longest code first, but the preferred market wins a tie.
    for (final m in candidates) {
      if (clean.startsWith(m.dialCode)) {
        final tie = candidates.firstWhere(
          (c) => c.dialCode == m.dialCode && c == preferred,
          orElse: () => m,
        );
        return (tie, clean.substring(m.dialCode.length));
      }
    }
    return (preferred, clean.replaceAll('+', ''));
  }

  @override
  State<PhoneNumberField> createState() => _PhoneNumberFieldState();
}

class _PhoneNumberFieldState extends State<PhoneNumberField> {
  late Market _market;
  late final TextEditingController _local;
  final FocusNode _focus = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    final (market, local) =
        PhoneNumberField.split(widget.initialValue, widget.defaultMarket);
    _market = market;
    // A leading 0 is the local trunk prefix — not dialled after +code.
    _local = TextEditingController(text: local.replaceFirst(RegExp(r'^0+'), ''));
    _focus.addListener(() {
      if (_focused != _focus.hasFocus) {
        setState(() => _focused = _focus.hasFocus);
      }
    });
  }

  @override
  void dispose() {
    _local.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _report() {
    final digits = _local.text
        .replaceAll(RegExp(r'[^0-9]'), '')
        .replaceFirst(RegExp(r'^0+'), '');
    widget.onChanged(digits.isEmpty ? '' : '${_market.dialCode}$digits');
  }

  Future<void> _pickCountry() async {
    final picked = await showModalBottomSheet<Market>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.7),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SheetDragHandle(),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final m in Market.values)
                      ListTile(
                        onTap: () => Navigator.of(sheetContext).pop(m),
                        leading: _FlagImage(asset: m.flagAsset),
                        title: Text(m.label, style: AppTextStyles.bodyStrong()),
                        trailing: Text(
                          m.dialCode,
                          style: AppTextStyles.bodyStrong(
                            color: m == _market
                                ? AppColors.primary
                                : AppColors.inkMuted,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || picked == _market) return;
    setState(() => _market = picked);
    _report();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      height: 64,
      padding: const EdgeInsetsDirectional.only(start: 8, end: 18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: _focused ? AppColors.primary : AppColors.line,
          width: _focused ? 1.8 : 1,
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _pickCountry,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _FlagImage(asset: _market.flagAsset),
                  const SizedBox(width: 8),
                  Text(_market.dialCode,
                      style:
                          AppTextStyles.bodyStrong().copyWith(fontSize: 16.5)),
                  const Icon(Icons.arrow_drop_down_rounded,
                      color: AppColors.inkMuted),
                ],
              ),
            ),
          ),
          Container(width: 1, height: 28, color: AppColors.line),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _local,
              focusNode: _focus,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')),
                LengthLimitingTextInputFormatter(16),
              ],
              onChanged: (_) => _report(),
              style: AppTextStyles.bodyStrong().copyWith(fontSize: 16.5),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: widget.hint,
                hintStyle: AppTextStyles.body(color: AppColors.inkMuted)
                    .copyWith(fontSize: 16.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FlagImage extends StatelessWidget {
  final String asset;
  const _FlagImage({required this.asset});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Image.asset(asset,
          width: 28, height: 20, fit: BoxFit.cover, cacheWidth: 84),
    );
  }
}

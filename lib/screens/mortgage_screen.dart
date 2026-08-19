import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/property.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../widgets/pill_button.dart';

/// Screen 20 — mortgage estimate.
///
/// The maths is a standard amortising-loan payment, done locally: there's no
/// endpoint for this and there doesn't need to be, because every input is on
/// screen. That also means it stays responsive while dragging the slider.
///
/// Rate presets are per-market rather than a free-text field, which is what the
/// Figma shows ("Rate (UAE preset)"). [_ratePresets] is the one place to edit
/// when the real numbers come from a config endpoint.
class MortgageScreen extends StatefulWidget {
  final Property property;
  final String currency;

  const MortgageScreen({
    super.key,
    required this.property,
    required this.currency,
  });

  @override
  State<MortgageScreen> createState() => _MortgageScreenState();
}

class _MortgageScreenState extends State<MortgageScreen> {
  static const List<double> _ratePresets = [3.5, 3.99, 4.2, 4.75, 5.25, 5.99];
  static const List<int> _tenures = [5, 10, 15, 20, 25, 30];

  late final TextEditingController _priceController;

  late int _price = widget.property.price;
  double _downPaymentFraction = 0.20;
  double _rate = 4.2;
  int _tenureYears = 25;

  @override
  void initState() {
    super.initState();
    _priceController =
        TextEditingController(text: formatThousands(_price));
  }

  @override
  void dispose() {
    _priceController.dispose();
    super.dispose();
  }

  // --- derived values -------------------------------------------------------

  int get _downPayment => (_price * _downPaymentFraction).round();
  int get _loanAmount => _price - _downPayment;

  /// Standard amortising payment: P·r / (1 − (1+r)^−n), with the zero-rate
  /// case handled separately so a 0% preset doesn't divide by zero.
  double get _monthlyPayment {
    final principal = _loanAmount.toDouble();
    if (principal <= 0) return 0;
    final months = _tenureYears * 12;
    final monthlyRate = _rate / 100 / 12;
    if (monthlyRate == 0) return principal / months;
    final factor = math.pow(1 + monthlyRate, -months);
    return principal * monthlyRate / (1 - factor);
  }

  int get _totalPaid => (_monthlyPayment * _tenureYears * 12).round();
  int get _totalInterest => math.max(0, _totalPaid - _loanAmount);

  double get _principalShare =>
      _totalPaid == 0 ? 0 : _loanAmount / _totalPaid;

  void _setPriceFromField(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    final parsed = int.tryParse(digits) ?? 0;
    setState(() => _price = parsed);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.currency;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _Header(onBack: () => Navigator.of(context).maybePop()),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenPadding, 6, AppSpacing.screenPadding, 24),
                children: [
                  _SummaryCard(
                    currency: c,
                    monthly: _monthlyPayment.round(),
                    loan: _loanAmount,
                    interest: _totalInterest,
                    total: _totalPaid,
                  ),
                  const SizedBox(height: 26),
                  Text('Property price',
                      style: AppTextStyles.bodyStrong().copyWith(fontSize: 16)),
                  const SizedBox(height: 10),
                  _PriceField(
                    controller: _priceController,
                    currency: c,
                    onChanged: _setPriceFromField,
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: Text('Down payment',
                            style: AppTextStyles.bodyStrong()
                                .copyWith(fontSize: 16)),
                      ),
                      Text(
                        '${(_downPaymentFraction * 100).round()}% · '
                        '$c ${formatThousands(_downPayment)}',
                        style:
                            AppTextStyles.bodyStrong(color: AppColors.primary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 5,
                      activeTrackColor: AppColors.primary,
                      inactiveTrackColor: AppColors.line,
                      thumbColor: AppColors.primary,
                      overlayColor: AppColors.primary.withValues(alpha: 0.12),
                      thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 13,
                          elevation: 2,
                          pressedElevation: 4),
                      showValueIndicator: ShowValueIndicator.never,
                    ),
                    child: Slider(
                      value: _downPaymentFraction,
                      // UAE mortgage rules floor the deposit around 15–20% for
                      // residents; 15% is a sane lower bound for the preset.
                      min: 0.15,
                      max: 0.80,
                      divisions: 13,
                      onChanged: (v) =>
                          setState(() => _downPaymentFraction = v),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _PickerField<double>(
                          label: 'Rate',
                          hint: '(UAE preset)',
                          value: _rate,
                          values: _ratePresets,
                          display: (v) => '$v%',
                          onChanged: (v) => setState(() => _rate = v),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _PickerField<int>(
                          label: 'Tenure',
                          value: _tenureYears,
                          values: _tenures,
                          display: (v) => '$v years',
                          onChanged: (v) => setState(() => _tenureYears = v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text('Payment breakdown',
                      style: AppTextStyles.bodyStrong().copyWith(fontSize: 16)),
                  const SizedBox(height: 12),
                  _BreakdownBar(principalShare: _principalShare),
                  const SizedBox(height: 22),
                  Text(
                    'Estimate only — final rates depend on your bank and '
                    'eligibility. Home8 is not a lender.',
                    style: AppTextStyles.caption(),
                  ),
                  const SizedBox(height: 30),
                  PrimaryButton(
                    label: 'Get pre-approved',
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Pre-approval is coming soon.'),
                          behavior: SnackBarBehavior.floating,
                          backgroundColor: AppColors.navDark,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onBack;
  const _Header({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onBack,
            child: const Padding(
              padding: EdgeInsets.all(10),
              child: Icon(Icons.arrow_back_rounded,
                  color: AppColors.ink, size: 24),
            ),
          ),
          Expanded(
            child: Text(
              'Mortgage estimate',
              textAlign: TextAlign.center,
              style: AppTextStyles.h1().copyWith(fontSize: 22),
            ),
          ),
          const SizedBox(width: 44),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String currency;
  final int monthly;
  final int loan;
  final int interest;
  final int total;

  const _SummaryCard({
    required this.currency,
    required this.monthly,
    required this.loan,
    required this.interest,
    required this.total,
  });

  /// Compact money for the three small stats — 1.12M, 695k.
  String _compact(int v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(2)}M';
    if (v >= 1000) return '${(v / 1000).round()}k';
    return '$v';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.navDark,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Estimated monthly payment',
              style: AppTextStyles.body(color: Colors.white70)),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              style: AppTextStyles.display(color: Colors.white)
                  .copyWith(fontSize: 32, fontWeight: FontWeight.w800),
              children: [
                TextSpan(text: '$currency ${formatThousands(monthly)}'),
                TextSpan(
                  text: ' / month',
                  style: AppTextStyles.body(color: Colors.white70),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _Stat(label: 'Loan', value: _compact(loan)),
              const SizedBox(width: 20),
              _Stat(label: 'Interest', value: _compact(interest)),
              const SizedBox(width: 20),
              _Stat(label: 'Total', value: _compact(total)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: AppTextStyles.caption(color: Colors.white54)),
        const SizedBox(width: 6),
        Text(value, style: AppTextStyles.bodyStrong(color: Colors.white)),
      ],
    );
  }
}

class _PriceField extends StatelessWidget {
  final TextEditingController controller;
  final String currency;
  final ValueChanged<String> onChanged;

  const _PriceField({
    required this.controller,
    required this.currency,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: onChanged,
              style: AppTextStyles.bodyStrong().copyWith(fontSize: 17),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          Text(currency, style: AppTextStyles.bodyStrong()),
        ],
      ),
    );
  }
}

/// Pill-shaped dropdown matching the Figma's Rate / Tenure controls.
class _PickerField<T> extends StatelessWidget {
  final String label;
  final String? hint;
  final T value;
  final List<T> values;
  final String Function(T) display;
  final ValueChanged<T> onChanged;

  const _PickerField({
    required this.label,
    required this.value,
    required this.values,
    required this.display,
    required this.onChanged,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            style: AppTextStyles.bodyStrong().copyWith(fontSize: 16),
            children: [
              TextSpan(text: label),
              if (hint != null)
                TextSpan(text: ' $hint', style: AppTextStyles.caption()),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Container(
          height: 60,
          padding: const EdgeInsetsDirectional.only(start: 18, end: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.line),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down_rounded,
                  color: AppColors.ink),
              borderRadius: BorderRadius.circular(AppRadius.md),
              style: AppTextStyles.bodyStrong().copyWith(fontSize: 17),
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
              items: [
                for (final v in values)
                  DropdownMenuItem<T>(
                    value: v,
                    child: Text(display(v)),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BreakdownBar extends StatelessWidget {
  final double principalShare;
  const _BreakdownBar({required this.principalShare});

  @override
  Widget build(BuildContext context) {
    final share = principalShare.clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: 12,
            child: Row(
              children: [
                Expanded(
                  flex: math.max(1, (share * 1000).round()),
                  child: const ColoredBox(color: AppColors.primary),
                ),
                Expanded(
                  flex: math.max(1, ((1 - share) * 1000).round()),
                  child: const ColoredBox(color: AppColors.amber),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _Legend(
              color: AppColors.primary,
              label: 'Principal ${(share * 100).round()}%',
            ),
            const SizedBox(width: 18),
            _Legend(
              color: AppColors.amber,
              label: 'Interest ${((1 - share) * 100).round()}%',
            ),
          ],
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 7),
        Text(label, style: AppTextStyles.caption(color: AppColors.ink)),
      ],
    );
  }
}

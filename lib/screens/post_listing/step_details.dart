import 'package:flutter/material.dart';

import '../../core/async_value.dart';
import '../../models/listing_draft.dart';
import '../../models/property.dart';
import '../../state/post_listing_controller.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/form_fields.dart';

/// Screen 34 — "Details & price", the fields of step 2.
///
/// ## The fair band is a live repository call
///
/// The green callout under the price isn't a static string. It comes from
/// `ListingRepository.priceGuidance`, debounced at 280ms, and it re-asks
/// whenever the price, area, bedrooms, furnishing or purpose change — see
/// `PostListingController.edit`. That means it renders all three async
/// branches like every other data surface in the app: a quiet loading line, the
/// band, or a retry.
///
/// Showing a seller their price against the market at the moment they set it is
/// the whole point of the fair-price feature; doing it after they publish is
/// too late to change anything.
class StepDetails extends StatefulWidget {
  final PostListingController controller;

  const StepDetails({super.key, required this.controller});

  @override
  State<StepDetails> createState() => _StepDetailsState();
}

class _StepDetailsState extends State<StepDetails> {
  static const int _titleMax = 70;

  late final TextEditingController _bua;
  late final TextEditingController _price;
  late final TextEditingController _title;

  @override
  void initState() {
    super.initState();
    final draft = widget.controller.draft;
    _bua = TextEditingController(
      text: draft.bua == null ? '' : ThousandsFormatter.group('${draft.bua}'),
    );
    _price = TextEditingController(
      text:
          draft.price == null ? '' : ThousandsFormatter.group('${draft.price}'),
    );
    _title = TextEditingController(text: draft.title);
  }

  @override
  void dispose() {
    _bua.dispose();
    _price.dispose();
    _title.dispose();
    super.dispose();
  }

  /// Label above the price box, which has to name the period or it's ambiguous
  /// — "96,000" means very different things yearly and monthly.
  String get _priceLabel {
    final draft = widget.controller.draft;
    if (draft.purpose == Purpose.sale) return 'Sale price';
    return switch (draft.period) {
      PricePeriod.monthly => 'Monthly rent',
      PricePeriod.weekly => 'Weekly rent',
      PricePeriod.nightly => 'Nightly rate',
      _ => 'Yearly rent',
    };
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final draft = controller.draft;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const FieldLabel('Bedrooms'),
                  const SizedBox(height: 8),
                  CounterField(
                    value: draft.beds,
                    // Zero bedrooms is a studio, which is a real listing —
                    // the floor is 0, not 1.
                    min: 0,
                    max: 12,
                    onChanged: (v) =>
                        controller.edit((d) => d.copyWith(beds: v)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const FieldLabel('Bathrooms'),
                  const SizedBox(height: 8),
                  CounterField(
                    value: draft.baths,
                    min: 1,
                    max: 12,
                    onChanged: (v) =>
                        controller.edit((d) => d.copyWith(baths: v)),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const FieldLabel('Built-up area'),
        const SizedBox(height: 8),
        AppTextField(
          controller: _bua,
          hint: '0',
          keyboardType: TextInputType.number,
          formatters: const [ThousandsFormatter()],
          onChanged: (text) => controller.edit(
            (d) => d.copyWith(bua: ThousandsFormatter.parse(text)),
          ),
          trailing: InlineUnitPicker<AreaUnit>(
            value: draft.areaUnit,
            options: AreaUnit.values,
            labelOf: (u) => u.label,
            onChanged: (u) => controller.edit((d) => d.copyWith(areaUnit: u)),
          ),
        ),
        const SizedBox(height: 20),
        FieldLabel(_priceLabel),
        const SizedBox(height: 8),
        AppTextField(
          controller: _price,
          hint: '0',
          keyboardType: TextInputType.number,
          formatters: const [ThousandsFormatter()],
          onChanged: (text) => controller.edit(
            (d) => d.copyWith(price: ThousandsFormatter.parse(text)),
          ),
          trailing: draft.purpose == Purpose.sale
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(draft.currency,
                      style:
                          AppTextStyles.bodyStrong(color: AppColors.inkMuted)),
                )
              : InlineUnitPicker<PricePeriod>(
                  value: draft.period ?? PricePeriod.yearly,
                  options: PricePeriod.values,
                  labelOf: (p) => '${draft.currency} / ${p.label}',
                  onChanged: (p) =>
                      controller.edit((d) => d.copyWith(period: p)),
                ),
        ),
        _PriceBandCallout(controller: controller),
        const SizedBox(height: 20),
        const FieldLabel('Furnishing'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final option in const ['Furnished', 'Unfurnished', 'Partly'])
              ChoicePill(
                label: option,
                active: draft.furnishing == option,
                onTap: () =>
                    controller.edit((d) => d.copyWith(furnishing: option)),
              ),
          ],
        ),
        const SizedBox(height: 20),
        const FieldLabel('Title'),
        const SizedBox(height: 8),
        AppTextField(
          controller: _title,
          hint: 'e.g. Bright 2BR with full sea view',
          maxLines: 2,
          maxLength: _titleMax,
          onChanged: (text) => controller.edit((d) => d.copyWith(title: text)),
        ),
        const SizedBox(height: 6),
        CharCount(length: _title.text.characters.length, max: _titleMax),
      ],
    );
  }
}

/// The fair-price feedback under the price field.
///
/// Renders nothing at all until there's a price and an area to judge — an empty
/// callout reserving space is noisier than no callout.
class _PriceBandCallout extends StatelessWidget {
  final PostListingController controller;

  const _PriceBandCallout({required this.controller});

  @override
  Widget build(BuildContext context) {
    final guidance = controller.guidance;
    if (guidance == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: guidance.when(
        // A skeleton block here would flash on every keystroke pause. A quiet
        // line of text is calmer and says the same thing.
        loading: () => Row(
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.inkMuted),
              ),
            ),
            const SizedBox(width: 10),
            Text('Checking this against the area…',
                style: AppTextStyles.caption()),
          ],
        ),
        error: (_) => InfoNote(
          tone: NoteTone.warning,
          icon: Icons.cloud_off_rounded,
          message: "Couldn't check the price band right now.",
          actionLabel: 'Retry',
          onAction: controller.retryGuidance,
        ),
        data: (band) => InfoNote(
          tone: switch (band.verdict) {
            PriceVerdict.fair => NoteTone.success,
            PriceVerdict.low => NoteTone.info,
            PriceVerdict.high => NoteTone.warning,
          },
          icon: switch (band.verdict) {
            PriceVerdict.fair => null,
            PriceVerdict.low => Icons.trending_down_rounded,
            PriceVerdict.high => Icons.trending_up_rounded,
          },
          message: _message(band, controller.draft),
        ),
      ),
    );
  }

  /// Says what the number means for the seller, not just where it sits.
  /// "Above the band" is a fact; "will get fewer enquiries" is the reason they
  /// care.
  static String _message(FairPrice band, ListingDraft draft) {
    final renting = draft.purpose == Purpose.rent;
    final range = band.hasBands
        ? ' (${_k(band.fairLow!)}–${_k(band.fairHigh!)})'
        : '';

    return switch (band.verdict) {
      PriceVerdict.fair => 'Within the fair band$range for this area — likely '
          'to ${renting ? 'rent' : 'sell'} faster.',
      PriceVerdict.low => 'Below the fair band$range for this area. You could '
          'ask more without losing interest.',
      PriceVerdict.high => 'Above the fair band$range for this area — expect '
          'fewer enquiries at this price.',
    };
  }

  /// "88k", "1.4m" — the band edges are context, not the headline, so they get
  /// the short form.
  static String _k(int value) {
    if (value >= 1000000) {
      final m = value / 1000000;
      return '${m.toStringAsFixed(m >= 10 ? 0 : 1)}m';
    }
    if (value >= 1000) return '${(value / 1000).round()}k';
    return '$value';
  }
}

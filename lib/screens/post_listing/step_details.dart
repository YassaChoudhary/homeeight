import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/amenities.dart';
import '../../models/listing_draft.dart';
import '../../models/property.dart';
import '../../models/search_query.dart';
import '../../state/app_scope.dart';
import '../../state/post_listing_controller.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/phone_number_field.dart';
import '../../widgets/pill_button.dart';

/// Step 2 — "Details & price" (prototype screen 40).
///
/// Bedrooms · Bathrooms · Built-up area · Price · Furnishing · Title ·
/// Description · What this place offers · Email · Phone · WhatsApp.
///
/// Plus two optional fields the listing page shows ("4 people", "6 years
/// old"): occupancy and building age, under Furnishing.
///
/// The green band under the price is a live database call (`price_guidance`)
/// built from real live listings like this one.
class StepDetails extends StatefulWidget {
  final PostListingController controller;

  const StepDetails({super.key, required this.controller});

  @override
  State<StepDetails> createState() => _StepDetailsState();
}

class _StepDetailsState extends State<StepDetails> {
  static const int _titleMax = 70;
  static const int _descriptionMax = 500;

  late final TextEditingController _bua;
  late final TextEditingController _price;
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _age;
  late final TextEditingController _email;
  late final String _initialPhone;
  late final String _initialWhatsapp;

  @override
  void initState() {
    super.initState();
    final draft = widget.controller.draft;

    // Contact defaults from the account, so most people never type them.
    final user = AppScope.authOf(context).user;
    if (draft.contactEmail.isEmpty && draft.contactPhone.isEmpty) {
      final email = user?.email ?? '';
      final phone = user?.phone ?? '';
      if (email.isNotEmpty || phone.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          widget.controller.edit((d) => d.copyWith(
                contactEmail: d.contactEmail.isEmpty ? email : null,
                contactPhone: d.contactPhone.isEmpty ? phone : null,
                contactWhatsapp: d.contactWhatsapp.isEmpty ? phone : null,
              ));
        });
      }
    }

    _bua = TextEditingController(
      text: draft.bua == null ? '' : ThousandsFormatter.group('${draft.bua}'),
    );
    _price = TextEditingController(
      text:
          draft.price == null ? '' : ThousandsFormatter.group('${draft.price}'),
    );
    _title = TextEditingController(text: draft.title);
    _description = TextEditingController(text: draft.description);
    _age = TextEditingController(
        text: draft.ageYears == null ? '' : '${draft.ageYears}');
    _email = TextEditingController(
        text: draft.contactEmail.isNotEmpty
            ? draft.contactEmail
            : (user?.email ?? ''));
    _initialPhone = draft.contactPhone.isNotEmpty
            ? draft.contactPhone
            : (user?.phone ?? '');
    _initialWhatsapp = draft.contactWhatsapp.isNotEmpty
            ? draft.contactWhatsapp
            : (user?.phone ?? '');
  }

  @override
  void dispose() {
    for (final c in [
      _bua,
      _price,
      _title,
      _description,
      _age,
      _email,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

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

  Future<void> _pickAmenities() async {
    final controller = widget.controller;
    final options = Amenities.forSegment(controller.draft.segment);
    final current = controller.draft.amenities;
    final result = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AmenitySheet(
        options: [
          ...options,
          // Keep anything saved earlier that isn't in today's list.
          for (final a in current)
            if (!options.contains(a)) a,
        ],
        selected: current,
      ),
    );
    if (result != null) {
      controller.edit((d) => d.copyWith(amenities: result));
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final draft = controller.draft;
    final market = Market.fromCountryCode(draft.countryCode) ??
        AppScope.of(context).appState.market;

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
                    // Zero bedrooms is a studio — a real listing.
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
          pill: true,
          hint: '0',
          keyboardType: TextInputType.number,
          formatters: const [ThousandsFormatter()],
          onChanged: (text) => controller.edit((d) {
            final v = ThousandsFormatter.parse(text);
            return v == null ? d.copyWith(clearBua: true) : d.copyWith(bua: v);
          }),
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
          pill: true,
          hint: '0',
          keyboardType: TextInputType.number,
          formatters: const [ThousandsFormatter()],
          onChanged: (text) => controller.edit((d) {
            final v = ThousandsFormatter.parse(text);
            return v == null
                ? d.copyWith(clearPrice: true)
                : d.copyWith(price: v);
          }),
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
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (draft.segment == PropertySegment.residential) ...[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const FieldLabel('Max occupancy'),
                    const SizedBox(height: 8),
                    CounterField(
                      // 0 = not stated.
                      value: draft.occupancy ?? 0,
                      min: 0,
                      max: 30,
                      onChanged: (v) => controller.edit((d) => v == 0
                          ? d.copyWith(clearOccupancy: true)
                          : d.copyWith(occupancy: v)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const FieldLabel('Building age'),
                  const SizedBox(height: 8),
                  AppTextField(
                    controller: _age,
                    pill: true,
                    hint: '0',
                    keyboardType: TextInputType.number,
                    formatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(3),
                    ],
                    onChanged: (text) => controller.edit((d) {
                      final v = int.tryParse(text);
                      return v == null
                          ? d.copyWith(clearAgeYears: true)
                          : d.copyWith(ageYears: v);
                    }),
                    trailing: Text('years',
                        style: AppTextStyles.bodyStrong(
                            color: AppColors.inkMuted)),
                  ),
                ],
              ),
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
          textCapitalization: TextCapitalization.sentences,
          onChanged: (text) => controller.edit((d) => d.copyWith(title: text)),
        ),
        const SizedBox(height: 6),
        CharCount(length: _title.text.characters.length, max: _titleMax),
        const SizedBox(height: 6),
        const FieldLabel('Description'),
        const SizedBox(height: 8),
        AppTextField(
          controller: _description,
          hint: 'What makes it special — views, layout, building, '
              'nearby places (at least 20 characters)',
          minLines: 4,
          maxLines: 8,
          maxLength: _descriptionMax,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (text) =>
              controller.edit((d) => d.copyWith(description: text)),
        ),
        const SizedBox(height: 6),
        CharCount(
            length: _description.text.characters.length, max: _descriptionMax),
        if (_description.text.trim().length < 20)
          Text('At least 20 characters',
              style: AppTextStyles.caption(color: AppColors.inkMuted)),
        const SizedBox(height: 6),
        const FieldLabel('What Place Offer'),
        const SizedBox(height: 8),
        _SelectBox(
          label: draft.amenities.isEmpty
              ? 'Select'
              : '${draft.amenities.length} selected',
          onTap: _pickAmenities,
        ),
        if (draft.amenities.isNotEmpty) ...[
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final a in draft.amenities)
                _AmenityChip(
                  label: a,
                  onRemove: () => controller.edit((d) => d.copyWith(
                        amenities:
                            d.amenities.where((x) => x != a).toList(),
                      )),
                ),
            ],
          ),
        ],
        const SizedBox(height: 20),
        const FieldLabel('Email'),
        const SizedBox(height: 8),
        AppTextField(
          controller: _email,
          pill: true,
          hint: 'name@example.com',
          keyboardType: TextInputType.emailAddress,
          onChanged: (text) =>
              controller.edit((d) => d.copyWith(contactEmail: text)),
        ),
        const SizedBox(height: 20),
        const FieldLabel('Phone Number'),
        const SizedBox(height: 8),
        PhoneNumberField(
          initialValue: _initialPhone,
          defaultMarket: market,
          onChanged: (v) =>
              controller.edit((d) => d.copyWith(contactPhone: v)),
        ),
        const SizedBox(height: 20),
        const FieldLabel('Whatsapp'),
        const SizedBox(height: 8),
        PhoneNumberField(
          initialValue: _initialWhatsapp,
          defaultMarket: market,
          onChanged: (v) =>
              controller.edit((d) => d.copyWith(contactWhatsapp: v)),
        ),
      ],
    );
  }
}

/// "Select ▾" box, same shape as the other fields.
class _SelectBox extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SelectBox({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        height: 64,
        padding: const EdgeInsetsDirectional.only(start: 18, end: 18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: AppTextStyles.bodyStrong().copyWith(fontSize: 16.5)),
            ),
            const Icon(Icons.arrow_drop_down_rounded,
                color: AppColors.inkMuted),
          ],
        ),
      ),
    );
  }
}

/// Cream chip, same as "What this place offers" on the listing page. Tap to
/// remove.
class _AmenityChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;

  const _AmenityChip({required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onRemove,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.accentTint,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label,
            style: AppTextStyles.bodyStrong(color: AppColors.ink)),
      ),
    );
  }
}

/// Multi-select list of amenities. Returns the new selection on "Done".
class _AmenitySheet extends StatefulWidget {
  final List<String> options;
  final List<String> selected;

  const _AmenitySheet({required this.options, required this.selected});

  @override
  State<_AmenitySheet> createState() => _AmenitySheetState();
}

class _AmenitySheetState extends State<_AmenitySheet> {
  late final Set<String> _picked = {...widget.selected};

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetDragHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenPadding, 8, AppSpacing.screenPadding, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text('What this place offers',
                        style: AppTextStyles.h2()),
                  ),
                  TertiaryButton(
                    label: 'Done',
                    onTap: () => Navigator.of(context).pop(
                      // Keep the catalogue's order.
                      widget.options.where(_picked.contains).toList(),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final a in widget.options)
                    CheckboxListTile(
                      value: _picked.contains(a),
                      activeColor: AppColors.primary,
                      title: Text(a, style: AppTextStyles.bodyStrong()),
                      onChanged: (v) => setState(() {
                        v == true ? _picked.add(a) : _picked.remove(a);
                      }),
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

/// The fair-price feedback under the price field.
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
        data: (band) {
          // Fewer than 3 similar live listings: say so instead of guessing.
          if (!band.hasBands) {
            return const InfoNote(
              icon: Icons.info_outline_rounded,
              message: 'Not enough similar listings nearby to judge this '
                  'price yet.',
            );
          }
          return InfoNote(
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
          );
        },
      ),
    );
  }

  static String _message(FairPrice band, ListingDraft draft) {
    final renting = draft.purpose == Purpose.rent;
    final range = ' (${_k(band.fairLow!)}–${_k(band.fairHigh!)})';
    return switch (band.verdict) {
      PriceVerdict.fair => 'Within the fair band$range for similar homes — '
          'likely to ${renting ? 'rent' : 'sell'} faster.',
      PriceVerdict.low => 'Below the fair band$range for similar homes. You '
          'could ask more without losing interest.',
      PriceVerdict.high => 'Above the fair band$range for similar homes — '
          'expect fewer enquiries at this price.',
    };
  }

  static String _k(int value) {
    if (value >= 1000000) {
      final m = value / 1000000;
      return '${m.toStringAsFixed(m >= 10 ? 0 : 1)}m';
    }
    if (value >= 1000) return '${(value / 1000).round()}k';
    return '$value';
  }
}

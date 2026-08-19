import 'package:flutter/material.dart';

import '../../models/listing_draft.dart';
import '../../models/property.dart';
import '../../models/property_category.dart';
import '../../models/search_query.dart';
import '../../state/post_listing_controller.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/pill_button.dart';
import 'step_location_screen.dart';

/// Screen 33 — "What are you listing?", the fields of step 1.
///
/// The chrome (header, progress, CTA) belongs to `PostListingFlow`; this is
/// only the body, which is why it's a Column rather than a Scaffold.
///
/// ## The type grid is the same catalogue as search
///
/// Tiles come from `PropertyCategory`, exactly as the Home grid and the Filters
/// sheet do. A type someone can post must be a type someone can search for —
/// keeping a second hardcoded list here is how you end up able to list a "Bed
/// Space" that no filter can find.
class StepBasics extends StatelessWidget {
  final PostListingController controller;

  const StepBasics({super.key, required this.controller});

  Future<void> _openMap(BuildContext context) async {
    final result = await Navigator.of(context).push<ListingDraft>(
      MaterialPageRoute(
        builder: (_) => StepLocationScreen(draft: controller.draft),
      ),
    );
    if (result != null) controller.edit((_) => result);
  }

  @override
  Widget build(BuildContext context) {
    final draft = controller.draft;
    final categories = PropertyCategory.forSegment(draft.segment);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FieldLabel('Purpose'),
        const SizedBox(height: 10),
        SegmentedControl<Purpose>(
          options: const [Purpose.rent, Purpose.sale],
          value: draft.purpose,
          labelOf: (p) => p.label,
          onChanged: (p) => controller.edit((d) => d.copyWith(
                purpose: p,
                // A sale has no rent period. Clearing it here rather than at
                // render time keeps the draft honest — otherwise a listing
                // switched from rent to sale still carries "yearly" into the
                // POST body.
                clearPeriod: p == Purpose.sale,
                period: p == Purpose.rent ? PricePeriod.yearly : null,
              )),
        ),
        const SizedBox(height: 22),
        const FieldLabel('Property nature'),
        const SizedBox(height: 10),
        SegmentedControl<PropertySegment>(
          options: PropertySegment.values,
          value: draft.segment,
          labelOf: (s) =>
              s == PropertySegment.residential ? 'Residential' : 'Commercial',
          onChanged: (segment) {
            if (segment == draft.segment) return;
            // Switching nature invalidates a type that doesn't belong to it —
            // same rule as the Filters sheet. Leaving "Offices" selected under
            // Residential would post a listing nothing can categorise.
            final stillValid =
                PropertyCategory.lookup(segment, draft.propertyType) != null;
            controller.edit((d) => d.copyWith(
                  segment: segment,
                  clearPropertyType: !stillValid,
                ));
          },
        ),
        const SizedBox(height: 22),
        const FieldLabel('Property type'),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: categories.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.86,
          ),
          itemBuilder: (context, i) {
            final category = categories[i];
            return _TypeTile(
              category: category,
              selected: draft.propertyType == category.wire,
              onTap: () => controller
                  .edit((d) => d.copyWith(propertyType: category.wire)),
            );
          },
        ),
        const SizedBox(height: 22),
        const FieldLabel('Location'),
        const SizedBox(height: 10),
        _LocationRow(
          address: draft.address,
          community: draft.community,
          city: draft.city,
          onTap: () => _openMap(context),
        ),
        const SizedBox(height: 18),
        // Market-specific, because the document differs: UAE wants a trade
        // licence or title deed, other markets don't yet. Reads off the draft's
        // country rather than a constant so it stays right as markets launch.
        if (draft.countryCode == 'AE')
          const InfoNote(
            message: 'A trade licence or title deed will be required at the '
                'verification step (UAE market rules).',
          ),
      ],
    );
  }
}

/// One property-type tile. Same artwork and geometry as the Home grid, with a
/// teal selected state added.
class _TypeTile extends StatelessWidget {
  final PropertyCategory category;
  final bool selected;
  final VoidCallback onTap;

  const _TypeTile({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: selected ? AppColors.primary : Colors.transparent,
            width: 1.8,
          ),
          boxShadow: [
            BoxShadow(
              color: selected
                  ? AppColors.primary.withValues(alpha: 0.16)
                  : AppColors.ink.withValues(alpha: 0.06),
              blurRadius: selected ? 16 : 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              category.asset,
              width: 52,
              height: 52,
              // Same reasoning as the Home grid: these are tiny on screen and
              // there are nine of them, so decode at 3x and no more.
              cacheWidth: 156,
              filterQuality: FilterQuality.medium,
            ),
            const SizedBox(height: 10),
            Text(
              category.gridLabel,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption(
                color: selected ? AppColors.primary : AppColors.ink,
              ).copyWith(
                fontSize: 13,
                height: 16 / 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The address field with the "Map" affordance on its trailing edge.
///
/// Not a text field: the address has to come back with coordinates attached,
/// and free text that doesn't geocode produces listings nobody can find on a
/// map. Tapping anywhere on the row opens the picker.
class _LocationRow extends StatelessWidget {
  final String address;
  final String community;
  final String city;
  final VoidCallback onTap;

  const _LocationRow({
    required this.address,
    required this.community,
    required this.city,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final empty = address.trim().isEmpty;
    final label = empty
        ? 'Add the address'
        : (community.isNotEmpty ? '$community, $city' : address);

    return Pressable(
      onTap: onTap,
      child: Container(
        height: 64,
        padding: const EdgeInsetsDirectional.only(start: 18, end: 18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            const Icon(Icons.location_on_outlined,
                size: 20, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: empty
                    ? AppTextStyles.body(color: AppColors.inkMuted)
                        .copyWith(fontSize: 16.5)
                    : AppTextStyles.bodyStrong().copyWith(fontSize: 16.5),
              ),
            ),
            const SizedBox(width: 10),
            Text('Map',
                style: AppTextStyles.bodyStrong(color: AppColors.primary)),
          ],
        ),
      ),
    );
  }
}

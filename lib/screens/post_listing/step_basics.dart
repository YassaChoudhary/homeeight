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

  @override
  Widget build(BuildContext context) {
    final draft = controller.draft;
    final categories = PropertyCategory.forSegment(draft.segment);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (controller.accountPending) ...[
          const InfoNote(
            tone: NoteTone.warning,
            icon: Icons.schedule_rounded,
            message: 'Your account is being verified. You can prepare this '
                'listing and save it as a draft — publishing unlocks once '
                "you're approved.",
          ),
          const SizedBox(height: 20),
        ],
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

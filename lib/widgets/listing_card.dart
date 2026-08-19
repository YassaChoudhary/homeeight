import 'package:flutter/material.dart';

import '../models/property.dart';
import '../state/app_scope.dart';
import 'sign_in_prompt.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import 'pill_button.dart';
import 'property_image.dart';

/// Compact card used in horizontal carousels (Home "The most relevant",
/// Search "Best deals for you", detail "Similar homes nearby").
///
/// Height is a published constant so the carousel's SizedBox and the card
/// always agree. The old version put an AspectRatio(1.28) image plus three text
/// rows inside a 232pt box, which is what produced the
/// "BOTTOM OVERFLOWED BY 47 PIXELS" stripe.
class DealCard extends StatelessWidget {
  /// Figma: 240 wide card, 150 image, white surface, 14 padding.
  static const double defaultWidth = 240;
  static const double imageHeight = 150;
  static const double height = 252;

  final Property property;
  final double width;
  final VoidCallback? onTap;

  const DealCard({
    super.key,
    required this.property,
    this.width = defaultWidth,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.985,
      child: SizedBox(
        width: width,
        height: height,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            boxShadow: [
              BoxShadow(
                color: AppColors.ink.withValues(alpha: 0.06),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: imageHeight,
                child: PropertyImage(
                  seed: property.gradientSeed,
                  url: property.photos.isEmpty ? null : property.photos.first,
                  decodeWidth: width,
                  child: Stack(
                    children: [
                      if (property.badgeLabel.isNotEmpty)
                        Positioned(
                          left: 10,
                          top: 10,
                          child: ListingBadge(label: property.badgeLabel),
                        ),
                      Positioned(
                        right: 10,
                        top: 10,
                        child: SaveHeartButton(listingId: property.id),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              property.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.bodyStrong()
                                  .copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.star_rounded,
                              size: 14, color: AppColors.accent),
                          const SizedBox(width: 2),
                          Text(
                            property.rating.toStringAsFixed(2),
                            style: AppTextStyles.caption(color: AppColors.ink),
                          ),
                        ],
                      ),
                      Text(
                        property.specLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.caption(),
                      ),
                      Text.rich(
                        TextSpan(
                          style: AppTextStyles.bodyStrong()
                              .copyWith(fontWeight: FontWeight.w700),
                          children: [
                            TextSpan(
                              text: '${property.currency} '
                                  '${property.priceFormatted}',
                            ),
                            if (property.period != null)
                              TextSpan(
                                text: ' / ${property.period!.label}',
                                style: AppTextStyles.caption(),
                              ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-width card used on the Results (list view) screen.
class ResultListingCard extends StatelessWidget {
  static const double imageHeight = 210;

  final Property property;
  final int index;
  final int total;
  final VoidCallback? onTap;
  final VoidCallback? onMapTap;

  const ResultListingCard({
    super.key,
    required this.property,
    required this.onTap,
    this.onMapTap,
    this.index = 1,
    this.total = 12,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.99,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.s4),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          boxShadow: [
            BoxShadow(
              color: AppColors.ink.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: imageHeight,
              child: PropertyImage(
                seed: property.gradientSeed,
                url: property.photos.isEmpty ? null : property.photos.first,
                decodeWidth: MediaQuery.sizeOf(context).width,
                child: Stack(
                  children: [
                    if (property.badgeLabel.isNotEmpty)
                      Positioned(
                        left: 12,
                        top: 12,
                        child: ListingBadge(label: property.badgeLabel),
                      ),
                    Positioned(
                      right: 12,
                      top: 12,
                      child: SaveHeartButton(listingId: property.id),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 12,
                      child: Center(
                        child: Pressable(
                          onTap: onMapTap,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 18, vertical: 9),
                            decoration: BoxDecoration(
                              color: AppColors.navDark.withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.map_rounded,
                                    size: 16, color: Colors.white),
                                const SizedBox(width: 6),
                                Text('Map',
                                    style: AppTextStyles.bodyStrong(
                                        color: Colors.white)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 12,
                      bottom: 14,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text('$index / $total',
                            style: AppTextStyles.micro(color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.s4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          property.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.h2(),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.star_rounded,
                          size: 16, color: AppColors.accent),
                      const SizedBox(width: 2),
                      Text(property.rating.toStringAsFixed(2),
                          style: AppTextStyles.bodyStrong()),
                      const SizedBox(width: 2),
                      Text('(${property.reviews})',
                          style: AppTextStyles.caption()),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 14,
                    runSpacing: 4,
                    children: [
                      _Spec(
                          icon: Icons.bed_outlined,
                          label: '${property.beds} Bedrooms'),
                      _Spec(
                          icon: Icons.bathtub_outlined,
                          label: '${property.baths} Baths'),
                      _Spec(
                          icon: Icons.crop_free_rounded,
                          label: '${formatThousands(property.sqft)} sqft'),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            style: AppTextStyles.h2(),
                            children: [
                              TextSpan(
                                text: '${property.currency} '
                                    '${property.priceFormatted}',
                              ),
                              TextSpan(
                                text: property.period != null
                                    ? ' / ${property.period!.label} · '
                                        '${property.pricePerSqft}/sqft'
                                    : ' · ${property.pricePerSqft}/sqft',
                                style: AppTextStyles.caption(),
                              ),
                            ],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (property.verified) ...[
                        const SizedBox(width: 8),
                        const VerifiedPill(),
                      ],
                    ],
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

class _Spec extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Spec({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: AppColors.inkMuted),
        const SizedBox(width: 4),
        Text(label, style: AppTextStyles.caption()),
      ],
    );
  }
}

class VerifiedPill extends StatelessWidget {
  const VerifiedPill({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.primaryTint,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.verified_rounded, size: 14, color: AppColors.success),
          const SizedBox(width: 4),
          Text('Verified', style: AppTextStyles.micro(color: AppColors.success)),
        ],
      ),
    );
  }
}

class ListingBadge extends StatelessWidget {
  final String label;
  const ListingBadge({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final isFeatured = label == 'Featured';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isFeatured ? AppColors.navDark : AppColors.accent,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: AppTextStyles.micro(color: Colors.white)
            .copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// Save toggle wired to [SavedListingsStore].
///
/// Listens to the store directly, so tapping one heart repaints that heart only
/// — no list rebuild, no screen setState.
class SaveHeartButton extends StatelessWidget {
  final String listingId;
  final double size;

  const SaveHeartButton({super.key, required this.listingId, this.size = 32});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.savedOf(context);

    return ValueListenableBuilder<Set<String>>(
      valueListenable: store,
      builder: (context, saved, _) {
        final isSaved = saved.contains(listingId);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          // Anonymous taps prompt sign-in and the save is applied afterwards —
          // see SignInPrompt.gate. Unsaving an already-saved listing can only
          // happen when signed in, so it passes straight through.
          onTap: () => SignInPrompt.gate(
            context,
            action: () => store.toggle(listingId),
          ),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.32),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isSaved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: isSaved ? AppColors.amber : Colors.white,
              size: size * 0.55,
            ),
          ),
        );
      },
    );
  }
}

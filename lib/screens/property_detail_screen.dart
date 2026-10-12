import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../data/listing_repository.dart';

import '../models/property.dart';
import '../state/app_scope.dart';
import '../state/listings_controller.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../widgets/app_icons.dart';
import '../widgets/home8_map.dart';
import '../widgets/listing_card.dart';
import '../widgets/pill_button.dart';
import '../widgets/property_image.dart';
import '../widgets/state_views.dart';
import 'fair_price_sheet.dart';
import 'gallery_screen.dart';
import 'map/property_map_screen.dart';
import 'mortgage_screen.dart';
import 'share_sheet.dart';
import 'video_player_screen.dart';

/// Screen 18.
///
/// Takes a [propertyId] rather than a full object so it can be reached from a
/// deep link or a reel. If the caller already has the listing it passes
/// [preloaded] and the screen renders instantly while the full record refreshes
/// behind it — no spinner on a tap that came from a card.
///
/// Every value here now comes off the model. The old version hardcoded the
/// address, occupancy, amenities, description and the fair-price marker.
class PropertyDetailScreen extends StatefulWidget {
  final String propertyId;
  final Property? preloaded;

  /// The seller's "see it as buyers will" preview from Post a listing:
  /// renders [preloaded] only — nothing is fetched or recorded, and the
  /// heart, share and contact buttons are inactive.
  final bool previewOnly;

  const PropertyDetailScreen({
    super.key,
    required this.propertyId,
    this.preloaded,
    this.previewOnly = false,
  });

  @override
  State<PropertyDetailScreen> createState() => _PropertyDetailScreenState();
}

class _PropertyDetailScreenState extends State<PropertyDetailScreen> {
  late final AsyncController<Property> _property;
  late final AsyncController<List<Property>> _similar;

  final PageController _gallery = PageController();
  final ValueNotifier<int> _page = ValueNotifier<int>(0);
  bool _descExpanded = false;

  @override
  void initState() {
    super.initState();
    _property = AsyncController<Property>(
      () => AppScope.repositoryOf(context).propertyById(widget.propertyId),
    );
    _similar = AsyncController<List<Property>>(
      () => AppScope.repositoryOf(context).similarTo(widget.propertyId),
    );
    if (widget.previewOnly) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _property.load();
      _similar.load();
      // Counts towards the lister's "views" (once per phone per hour).
      AppScope.repositoryOf(context)
          .recordListingEvent(widget.propertyId, ListingEvent.view);
    });
  }

  @override
  void dispose() {
    _gallery.dispose();
    _page.dispose();
    _property.dispose();
    _similar.dispose();
    super.dispose();
  }

  void _openGallery(Property p, {int initialIndex = 0}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            GalleryScreen(property: p, initialIndex: initialIndex),
      ),
    );
  }

  void _openFairPrice(Property p) => FairPriceSheet.show(context, p);

  void _openShare(Property p) => ShareSheet.show(context, p);

  void _openMortgage(Property p) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MortgageScreen(
          property: p,
          currency: AppScope.of(context).appState.currency,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: ListenableBuilder(
        listenable: _property,
        builder: (context, _) {
          final property = widget.previewOnly
              ? widget.preloaded
              : _property.state.valueOrNull ?? widget.preloaded;

          if (property == null) {
            if (_property.state.hasError) {
              return SafeArea(
                child: Column(
                  children: [
                    Align(
                      alignment: AlignmentDirectional.topStart,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: BackButton(
                          color: AppColors.ink,
                          onPressed: () => Navigator.of(context).maybePop(),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: ErrorStateView(onRetry: _property.load),
                      ),
                    ),
                  ],
                ),
              );
            }
            return const Center(child: CircularProgressIndicator());
          }

          return _buildContent(context, property);
        },
      ),
      bottomNavigationBar: ListenableBuilder(
        listenable: _property,
        builder: (context, _) {
          final p = widget.previewOnly
              ? widget.preloaded
              : _property.state.valueOrNull ?? widget.preloaded;
          return _ContactBar(
            property: p,
            enabled: !widget.previewOnly,
          );
        },
      ),
    );
  }

  Widget _buildContent(BuildContext context, Property p) {
    // Slider order: walkthrough video (if any), then the cover, then the
    // other photos (the cover is already first in `photos`).
    final hasVideo = p.videoUrl != null;
    final photoSlides = p.photos.isEmpty ? 5 : p.photos.length;
    final photoCount = photoSlides + (hasVideo ? 1 : 0);
    int photoIndexOf(int slide) => hasVideo ? (slide - 1).clamp(0, 1 << 20) : slide;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: SizedBox(
            height: 340,
            child: Stack(
              fit: StackFit.expand,
              children: [
                PageView.builder(
                  controller: _gallery,
                  itemCount: photoCount,
                  onPageChanged: (i) => _page.value = i,
                  itemBuilder: (context, slide) {
                    if (hasVideo && slide == 0) {
                      return _VideoSlide(
                        url: p.videoUrl!,
                        posterUrl: p.photos.isEmpty ? null : p.photos.first,
                        posterSeed: p.gradientSeed,
                        page: _page,
                        onFullscreen: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => VideoPlayerScreen(
                                url: p.videoUrl!, title: p.title),
                          ),
                        ),
                      );
                    }
                    final i = photoIndexOf(slide);
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      // Tapping the hero opens the full gallery at this photo.
                      onTap: () => _openGallery(p, initialIndex: i),
                      child: PropertyImage(
                        seed: p.gradientSeed + i,
                        url: i < p.photos.length ? p.photos[i] : null,
                        decodeWidth: MediaQuery.sizeOf(context).width,
                      ),
                    );
                  },
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      child: Row(
                        children: [
                          _GalleryIconBtn(
                            icon: Icons.close_rounded,
                            onTap: () => Navigator.of(context).maybePop(),
                          ),
                          const Spacer(),
                          if (!widget.previewOnly) ...[
                            SaveHeartButton(listingId: p.id, size: 36),
                            const SizedBox(width: 10),
                            _GalleryIconBtn(
                              icon: Icons.ios_share_rounded,
                              onTap: () => _openShare(p),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 14,
                  bottom: 16,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _openGallery(p,
                        initialIndex: photoIndexOf(_page.value)),
                    child: ValueListenableBuilder<int>(
                      valueListenable: _page,
                      builder: (context, page, _) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text('${page + 1} / $photoCount',
                            style: AppTextStyles.micro(color: Colors.white)),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 4,
                  child: ValueListenableBuilder<int>(
                    valueListenable: _page,
                    builder: (context, page, _) => Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < photoCount; i++)
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: i == page ? Colors.white : Colors.white38,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(p.title, style: AppTextStyles.h1())),
                    if (p.verified)
                      const Icon(Icons.verified_rounded,
                          color: AppColors.accent, size: 20),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  [
                    if (p.occupancy != null) '${p.occupancy} people',
                    '${p.beds} Bedrooms',
                    '${p.baths} Bathrooms',
                    '${formatThousands(p.sqft)} sqft',
                  ].join(' · '),
                  style: AppTextStyles.caption(),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.star_rounded,
                        size: 16, color: AppColors.accent),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        [
                          if (p.reviews > 0)
                            '${p.rating} · ${p.reviews} reviews'
                          else
                            'New listing',
                          [p.area, p.city].where((x) => x.isNotEmpty).join(', '),
                        ].where((x) => x.isNotEmpty).join(' · '),
                        style: AppTextStyles.caption(color: AppColors.ink),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _PriceBlock(
                  property: p,
                  onFairPriceTap: () => _openFairPrice(p),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    if (p.verified)
                      const _TintChip(
                        icon: Icons.shield_rounded,
                        label: 'Verified',
                        bg: AppColors.primaryTint,
                        fg: AppColors.success,
                      ),
                    if (p.permitNo != null)
                      _TintChip(
                        icon: Icons.badge_rounded,
                        label: 'Permit #${p.permitNo}',
                        bg: AppColors.primaryTint,
                        fg: AppColors.primary,
                      ),
                    if (p.listedByOwner)
                      const _TintChip(
                        icon: Icons.person_rounded,
                        label: 'Listed by Owner',
                        bg: AppColors.accentTint,
                        fg: AppColors.accent,
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                GridView.count(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 2.6,
                  children: [
                    _SpecTile(
                        icon: Icons.bed_outlined,
                        title: '${p.beds} Beds',
                        subtitle: 'Bedrooms'),
                    _SpecTile(
                        icon: Icons.bathtub_outlined,
                        title: '${p.baths} Baths',
                        subtitle: 'Bathrooms'),
                    _SpecTile(
                        icon: Icons.crop_free_rounded,
                        title: '${formatThousands(p.sqft)} sqft',
                        subtitle: 'Built-up area'),
                    _SpecTile(
                      icon: Icons.chair_outlined,
                      title: p.furnishing ?? 'Unfurnished',
                      subtitle:
                          p.ageYears == null ? '—' : '${p.ageYears} years old',
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _AgentCard(agent: p.agent),
                if (p.amenities.isNotEmpty) ...[
                  const SizedBox(height: 26),
                  Text('What this place offers', style: AppTextStyles.h1()),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final amenity in p.amenities)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.accentTint,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(amenity,
                              style: AppTextStyles.bodyStrong(
                                  color: AppColors.ink)),
                        ),
                    ],
                  ),
                ],
                if (p.fairPrice.isKnown) ...[
                const SizedBox(height: 26),
                Text('Home8 Fair Price', style: AppTextStyles.h1()),
                const SizedBox(height: 14),
                // Tapping anywhere in the card opens the full explainer sheet —
                // the gauge, the sentence and the link all answer the same
                // question, so they share one target.
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _openFairPrice(p),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FairPriceGauge(fairPrice: p.fairPrice),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Low',
                              style: p.fairPrice.verdict == PriceVerdict.low
                                  ? AppTextStyles.bodyStrong(
                                      color: AppColors.success)
                                  : AppTextStyles.caption(),
                            ),
                            Text(
                              'Fair',
                              style: p.fairPrice.verdict == PriceVerdict.fair
                                  ? AppTextStyles.bodyStrong(
                                      color: AppColors.success)
                                  : AppTextStyles.caption(),
                            ),
                            Text(
                              'High',
                              style: p.fairPrice.verdict == PriceVerdict.high
                                  ? AppTextStyles.bodyStrong(
                                      color: AppColors.danger)
                                  : AppTextStyles.caption(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text.rich(
                          TextSpan(
                            style:
                                AppTextStyles.body(color: AppColors.inkMuted),
                            children: [
                              TextSpan(
                                text: p.fairPrice.verdictSentence(
                                    p.currency, p.price),
                              ),
                              if (p.fairPrice.comparableCount > 0)
                                TextSpan(
                                  text: ', against '
                                      '${p.fairPrice.comparableCount} '
                                      'comparable homes in ${p.area}',
                                ),
                              const TextSpan(text: '. '),
                              TextSpan(
                                text: 'How is this calculated?',
                                style: AppTextStyles.bodyStrong(
                                    color: AppColors.primary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                ],
                // Sale listings get the mortgage calculator; rentals don't.
                if (p.purpose == Purpose.sale) ...[
                  const SizedBox(height: 12),
                  _MortgageRow(
                    currency: p.currency,
                    onTap: () => _openMortgage(p),
                  ),
                ],
                if (p.description.isNotEmpty) ...[
                  const SizedBox(height: 26),
                  Text('More about this property', style: AppTextStyles.h1()),
                  const SizedBox(height: 10),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 180),
                    alignment: Alignment.topCenter,
                    child: Text(
                      p.description,
                      style: AppTextStyles.body(color: AppColors.inkMuted),
                      maxLines: _descExpanded ? null : 3,
                      overflow: _descExpanded
                          ? TextOverflow.visible
                          : TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 12),
                  GhostButton(
                    label: _descExpanded ? 'Show less' : 'Show more',
                    onTap: () => setState(() => _descExpanded = !_descExpanded),
                  ),
                ],
                if (p.addressLine.isNotEmpty || p.hasLocation) ...[
                  const SizedBox(height: 26),
                  Text("Where you'll be", style: AppTextStyles.h1()),
                  if (p.addressLine.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(p.addressLine, style: AppTextStyles.caption()),
                  ],
                  const SizedBox(height: 12),
                  _LocationPreview(property: p),
                ],
                if (!widget.previewOnly) ...[
                const SizedBox(height: 26),
                Text('Similar homes nearby', style: AppTextStyles.h1()),
                const SizedBox(height: 12),
                SizedBox(
                  height: DealCard.height,
                  child: ListenableBuilder(
                    listenable: _similar,
                    builder: (context, _) => _similar.state.when(
                      loading: () => ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: 2,
                        separatorBuilder: (_, _) => const SizedBox(width: 14),
                        itemBuilder: (_, _) =>
                            const DealCardSkeleton(width: 220),
                      ),
                      error: (_) => ErrorStateView(
                        compact: true,
                        message: "Couldn't load similar homes.",
                        onRetry: _similar.load,
                      ),
                      data: (items) => ListView.separated(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 14),
                        itemBuilder: (context, i) => DealCard(
                          property: items[i],
                          width: 220,
                          onTap: () => Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (_) => PropertyDetailScreen(
                                propertyId: items[i].id,
                                preloaded: items[i],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PriceBlock extends StatelessWidget {
  final Property property;
  final VoidCallback onFairPriceTap;

  const _PriceBlock({required this.property, required this.onFairPriceTap});

  @override
  Widget build(BuildContext context) {
    final p = property;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.navDark,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.period == null
                      ? 'Sale price'
                      : '${p.period!.label == "year" ? "Yearly" : "Monthly"} '
                          'rent',
                  style: AppTextStyles.caption(color: Colors.white60),
                ),
                const SizedBox(height: 4),
                Text.rich(
                  TextSpan(
                    style: AppTextStyles.display(color: Colors.white)
                        .copyWith(fontSize: 24),
                    children: [
                      TextSpan(text: '${p.currency} ${p.priceFormatted}'),
                      TextSpan(
                        text: '  ${p.pricePerSqft}/sqft',
                        style: AppTextStyles.caption(color: Colors.white60),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppStateBuilder(
                      builder: (context, state) => Text(
                        state.currency,
                        style: AppTextStyles.bodyStrong(color: Colors.white),
                      ),
                    ),
                    const Icon(Icons.keyboard_arrow_down_rounded,
                        color: Colors.white, size: 16),
                  ],
                ),
              ),
              if (p.fairPrice.isKnown) ...[
              const SizedBox(height: 8),
              Pressable(
                onTap: onFairPriceTap,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: switch (p.fairPrice.verdict) {
                      PriceVerdict.low => AppColors.success,
                      PriceVerdict.fair => AppColors.amber,
                      PriceVerdict.high => AppColors.danger,
                    },
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    p.fairPrice.verdictLabel,
                    style: AppTextStyles.micro(color: Colors.white)
                        .copyWith(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _AgentCard extends StatelessWidget {
  final Agent agent;
  const _AgentCard({required this.agent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
              color: AppColors.primaryTint,
              shape: BoxShape.circle,
            ),
            clipBehavior: Clip.antiAlias,
            child: agent.avatarUrl == null
                ? const Icon(Icons.person_rounded, color: AppColors.primary)
                : Image.network(
                    agent.avatarUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const Icon(Icons.person_rounded,
                        color: AppColors.primary),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        agent.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodyStrong(),
                      ),
                    ),
                    if (agent.verified) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.verified_rounded,
                          size: 14, color: AppColors.accent),
                    ],
                  ],
                ),
                Text(
                  '${agent.agency} · replies in ${agent.responseTime}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption(),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.inkMuted),
        ],
      ),
    );
  }
}

class _GalleryIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _GalleryIconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
}

class _GalleryTag extends StatelessWidget {
  final IconData? icon;
  final String? iconAsset;
  final String label;
  final VoidCallback? onTap;

  const _GalleryTag({
    required this.label,
    this.icon,
    this.iconAsset,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (iconAsset != null)
              SvgPicture.asset(
                iconAsset!,
                width: 13,
                height: 13,
                colorFilter:
                    const ColorFilter.mode(Colors.white, BlendMode.srcIn),
              )
            else
              Icon(icon, size: 13, color: Colors.white),
            const SizedBox(width: 4),
            Text(label, style: AppTextStyles.micro(color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

class _TintChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color bg;
  final Color fg;

  const _TintChip({
    required this.icon,
    required this.label,
    required this.bg,
    required this.fg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: fg),
          const SizedBox(width: 6),
          Text(label, style: AppTextStyles.bodyStrong(color: fg)),
        ],
      ),
    );
  }
}

class _SpecTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SpecTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title,
                    style: AppTextStyles.bodyStrong(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(subtitle,
                    style: AppTextStyles.micro(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Entry point to the mortgage calculator, shown on sale listings only.
class _MortgageRow extends StatelessWidget {
  final String currency;
  final VoidCallback onTap;

  const _MortgageRow({required this.currency, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.primaryTint,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            const Icon(Icons.account_balance_rounded,
                color: AppColors.primary, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Estimate my mortgage',
                      style: AppTextStyles.bodyStrong()),
                  const SizedBox(height: 2),
                  Text('Monthly payment in $currency',
                      style: AppTextStyles.caption()),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.primary, size: 24),
          ],
        ),
      ),
    );
  }
}

/// Small, still map of the listing's approximate area. Tap opens the full map.
///
/// Shows a shaded circle, not a pin: buyers only see roughly where the home
/// is until the owner accepts their enquiry (see `approximateLocation`).
class _LocationPreview extends StatelessWidget {
  final Property property;
  const _LocationPreview({required this.property});

  @override
  Widget build(BuildContext context) {
    final area = property.mapLocation;
    if (area == null) return const _MapPlaceholder();

    void open() => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PropertyMapScreen(property: property),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: SizedBox(
            height: 180,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Home8Map(
                    initialCenter: area,
                    initialZoom: 14,
                    area: area,
                    interactive: false,
                    onTap: open,
                  ),
                ),
                Positioned(
                  right: 10,
                  top: 10,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.open_in_full_rounded,
                              size: 14, color: AppColors.ink),
                          const SizedBox(width: 6),
                          Text('View map',
                              style: AppTextStyles.caption(
                                  color: AppColors.ink)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(Icons.shield_outlined,
                size: 15, color: AppColors.inkMuted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Approximate area. The exact address is shared after '
                'the owner accepts your enquiry.',
                style: AppTextStyles.caption(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Shown when a listing has no coordinates yet.
class _MapPlaceholder extends StatelessWidget {
  const _MapPlaceholder();

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        height: 160,
        decoration: BoxDecoration(
          color: const Color(0xFFE8EEE9),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            CustomPaint(size: Size.infinite, painter: _MapGridPainter()),
            const Center(
              child: Icon(Icons.location_on_rounded,
                  color: AppColors.primary, size: 34),
            ),
            const Positioned(
              right: 10,
              bottom: 10,
              child: Column(
                children: [
                  _MapBtn(icon: Icons.add_rounded),
                  SizedBox(height: 6),
                  _MapBtn(icon: Icons.remove_rounded),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.12)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 22) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += 22) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MapBtn extends StatelessWidget {
  final IconData icon;
  const _MapBtn({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
          ),
        ],
      ),
      child: Icon(icon, size: 16, color: AppColors.ink),
    );
  }
}

/// Email · Call · WhatsApp — the lister's details for this listing.
/// Taps open the phone's mail app, dialler or WhatsApp, and count as an
/// enquiry on the lister's dashboard.
class _ContactBar extends StatelessWidget {
  final Property? property;
  final bool enabled;

  const _ContactBar({required this.property, required this.enabled});

  Future<void> _open(BuildContext context, ListingEvent kind) async {
    final p = property;
    if (p == null || !enabled) return;
    final c = p.contact;
    final Uri? uri = switch (kind) {
      ListingEvent.email => c.email == null
          ? null
          : Uri(
              scheme: 'mailto',
              path: c.email,
              query: 'subject=${Uri.encodeComponent('Home8: ${p.title}')}',
            ),
      ListingEvent.call =>
        c.phone == null ? null : Uri(scheme: 'tel', path: c.phone),
      ListingEvent.whatsapp => (c.whatsapp ?? c.phone) == null
          ? null
          : Uri.parse('https://wa.me/'
              '${(c.whatsapp ?? c.phone)!.replaceAll(RegExp(r'[^0-9]'), '')}'
              '?text=${Uri.encodeComponent('Hi, I saw "${p.title}" on Home8. Is it still available?')}'),
      ListingEvent.view => null,
    };
    if (uri == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text("The lister hasn't shared this contact option."),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.navDark,
        ));
      return;
    }
    AppScope.repositoryOf(context).recordListingEvent(p.id, kind);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text("Couldn't open an app for that on this phone."),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.navDark,
        ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: _ContactButton(
                iconAsset: AppIcons.contactEmail,
                label: 'Email',
                bg: AppColors.primaryTint,
                fg: AppColors.primary,
                onTap: () => _open(context, ListingEvent.email),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ContactButton(
                iconAsset: AppIcons.contactCall,
                label: 'Call',
                bg: AppColors.navDark,
                fg: Colors.white,
                onTap: () => _open(context, ListingEvent.call),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ContactButton(
                iconAsset: AppIcons.contactWhatsapp,
                label: 'Whatsapp',
                bg: const Color(0xFF25D366),
                fg: Colors.white,
                onTap: () => _open(context, ListingEvent.whatsapp),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactButton extends StatelessWidget {
  final String iconAsset;
  final String label;
  final Color bg;
  final Color fg;
  final VoidCallback onTap;

  const _ContactButton({
    required this.iconAsset,
    required this.label,
    required this.bg,
    required this.fg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset(
              iconAsset,
              width: 18,
              height: 18,
              colorFilter: ColorFilter.mode(fg, BlendMode.srcIn),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyStrong(color: fg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// First slide of the gallery when the listing has a video: shows the cover
/// until tapped, then plays inline (tap to pause). ⛶ opens full screen.
/// Pauses itself when swiped away.
class _VideoSlide extends StatefulWidget {
  final String url;
  final String? posterUrl;
  final int posterSeed;
  final ValueNotifier<int> page;
  final VoidCallback onFullscreen;

  const _VideoSlide({
    required this.url,
    required this.posterUrl,
    required this.posterSeed,
    required this.page,
    required this.onFullscreen,
  });

  @override
  State<_VideoSlide> createState() => _VideoSlideState();
}

class _VideoSlideState extends State<_VideoSlide> {
  VideoPlayerController? _video;
  bool _started = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    widget.page.addListener(_onPage);
  }

  void _onPage() {
    if (widget.page.value != 0) _video?.pause();
  }

  @override
  void dispose() {
    widget.page.removeListener(_onPage);
    _video?.removeListener(_tick);
    _video?.dispose();
    super.dispose();
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  Future<void> _toggle() async {
    if (_failed) return;
    final existing = _video;
    if (existing == null) {
      // Platform view: renders reliably on devices/emulators where the
      // texture path shows a black picture with sound (Impeller).
      final c = VideoPlayerController.networkUrl(
        Uri.parse(widget.url),
        viewType: VideoViewType.platformView,
      );
      setState(() {
        _video = c;
        _started = true;
      });
      c.addListener(_tick);
      try {
        await c.initialize();
        await c.setLooping(true);
        if (mounted && widget.page.value == 0) await c.play();
      } catch (_) {
        if (mounted) setState(() => _failed = true);
      }
      return;
    }
    existing.value.isPlaying ? existing.pause() : existing.play();
  }

  @override
  Widget build(BuildContext context) {
    final v = _video?.value;
    final ready = v?.isInitialized ?? false;
    final playing = v?.isPlaying ?? false;

    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: Colors.black),
        if (ready)
          Center(
            child: AspectRatio(
              aspectRatio: v!.aspectRatio,
              child: VideoPlayer(_video!),
            ),
          )
        else
          PropertyImage(
            seed: widget.posterSeed,
            url: widget.posterUrl,
            decodeWidth: MediaQuery.sizeOf(context).width,
          ),
        // Tap layer above the native view.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggle,
          ),
        ),
        if (!playing)
          IgnorePointer(
            child: Center(
              child: _failed
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text("Couldn't play this video",
                          style: AppTextStyles.caption(color: Colors.white)),
                    )
                  : _started && !ready
                      ? const CircularProgressIndicator(
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white))
                      : Container(
                          width: 68,
                          height: 68,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.play_arrow_rounded,
                              color: Colors.white, size: 42),
                        ),
            ),
          ),
        Positioned(
          left: 14,
          bottom: 16,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.videocam_rounded,
                      color: Colors.white, size: 14),
                  const SizedBox(width: 5),
                  Text('Video',
                      style: AppTextStyles.micro(color: Colors.white)),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          right: 14,
          bottom: 48,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              _video?.pause();
              widget.onFullscreen();
            },
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.fullscreen_rounded,
                  color: Colors.white, size: 22),
            ),
          ),
        ),
      ],
    );
  }
}

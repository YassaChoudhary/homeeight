import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/property.dart';
import '../models/search_query.dart';
import '../state/app_scope.dart';
import '../state/listings_controller.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../widgets/app_icons.dart';
import '../widgets/pill_button.dart';
import '../widgets/property_image.dart';
import '../widgets/state_views.dart';
import 'property_detail_screen.dart';

/// Screens F02 / F03 — "Saved", with Properties and Reels tabs.
///
/// ## Why this reads from two places
///
/// `SavedListingsStore` holds only listing **ids** — it's a `Set<String>` so
/// that tapping a heart repaints hearts and nothing else. The cards here need
/// full `Property` records, so the screen resolves the ids through the
/// repository and keeps its own async state. That means the heart stays cheap
/// everywhere else in the app and this screen pays the lookup cost only when
/// it's open.
///
/// Unsaving from here removes the id from the store but **keeps the card on
/// screen** until you leave, so an accidental tap is recoverable. Dropping the
/// row instantly is the behaviour people complain about.
class SavedScreen extends StatefulWidget {
  const SavedScreen({super.key});

  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> {
  late final AsyncController<List<Property>> _saved;
  bool _propertiesTab = true;

  @override
  void initState() {
    super.initState();
    _saved = AsyncController<List<Property>>(_resolveSaved);
    WidgetsBinding.instance.addPostFrameCallback((_) => _saved.load());
  }

  @override
  void dispose() {
    _saved.dispose();
    super.dispose();
  }

  /// Resolves saved ids into full records.
  ///
  /// Uses a broad search and filters client-side because there is no
  /// `GET /saved-listings` returning hydrated records yet. When that endpoint
  /// exists this method becomes a single call and nothing else changes.
  Future<List<Property>> _resolveSaved() async {
    final ids = AppScope.savedOf(context).value;
    if (ids.isEmpty) return const [];

    final repository = AppScope.repositoryOf(context);
    final page = await repository.search(
      const SearchQuery(pageSize: 100),
    );
    final byId = {for (final p in page.results) p.id: p};

    // Also sweep sale listings — the default query is rent-only.
    final salePage = await repository.search(
      const SearchQuery(purpose: Purpose.sale, pageSize: 100),
    );
    for (final p in salePage.results) {
      byId.putIfAbsent(p.id, () => p);
    }

    return [
      for (final id in ids)
        if (byId[id] != null) byId[id]!,
    ];
  }

  void _openDetail(Property p) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            PropertyDetailScreen(propertyId: p.id, preloaded: p),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
              child: Row(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).maybePop(),
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Icon(Icons.arrow_back_rounded,
                          color: AppColors.ink, size: 24),
                    ),
                  ),
                  Expanded(
                    child: Text('Saved',
                        style: AppTextStyles.display().copyWith(fontSize: 27)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenPadding),
              child: _SavedTabs(
                propertiesActive: _propertiesTab,
                onChanged: (v) => setState(() => _propertiesTab = v),
              ),
            ),
            Expanded(
              child: _propertiesTab
                  ? _PropertiesTab(
                      controller: _saved,
                      onOpen: _openDetail,
                    )
                  : const _ReelsTab(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Properties / Reels segmented control — same geometry as Home's
/// Residential/Commercial toggle, amber active half.
class _SavedTabs extends StatelessWidget {
  final bool propertiesActive;
  final ValueChanged<bool> onChanged;

  const _SavedTabs({required this.propertiesActive, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _TabHalf(
              label: 'Properties',
              active: propertiesActive,
              onTap: () => onChanged(true),
            ),
          ),
          Expanded(
            child: _TabHalf(
              label: 'Reels',
              active: !propertiesActive,
              onTap: () => onChanged(false),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabHalf extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _TabHalf({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? AppColors.amber : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Text(
            label,
            style: AppTextStyles.bodyStrong(
              color: active ? Colors.white : AppColors.ink,
            ).copyWith(fontSize: 15.5),
          ),
        ),
      ),
    );
  }
}

class _PropertiesTab extends StatelessWidget {
  final AsyncController<List<Property>> controller;
  final ValueChanged<Property> onOpen;

  const _PropertiesTab({required this.controller, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => controller.state.when(
        loading: () => GridView.count(
          crossAxisCount: 2,
          padding: const EdgeInsets.all(AppSpacing.screenPadding),
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          childAspectRatio: 0.74,
          children: const [
            SkeletonBox(height: 240, radius: AppRadius.md),
            SkeletonBox(height: 240, radius: AppRadius.md),
            SkeletonBox(height: 240, radius: AppRadius.md),
            SkeletonBox(height: 240, radius: AppRadius.md),
          ],
        ),
        error: (_) => Center(
          child: ErrorStateView(
            message: "Couldn't load your saved homes.",
            onRetry: controller.load,
          ),
        ),
        data: (items) {
          if (items.isEmpty) return const SavedEmptyState();
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(AppSpacing.screenPadding, 16,
                AppSpacing.screenPadding, 28),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 0.72,
            ),
            itemCount: items.length,
            cacheExtent: 700,
            itemBuilder: (context, i) => SavedPropertyCard(
              property: items[i],
              onTap: () => onOpen(items[i]),
            ),
          );
        },
      ),
    );
  }
}

/// Grid card for a saved home.
///
/// Three states the normal `DealCard` doesn't cover, all driven off the model
/// rather than flags passed in:
/// - a price drop shows a green badge and strikes through the old price;
/// - an unavailable listing dims, shows a reason chip, and replaces the price
///   with "No longer available";
/// - the heart is always filled amber, because everything here is saved.
class SavedPropertyCard extends StatelessWidget {
  final Property property;
  final VoidCallback onTap;

  const SavedPropertyCard({
    super.key,
    required this.property,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = property;
    final gone = !p.available;

    return Pressable(
      onTap: onTap,
      child: Opacity(
        // Dim rather than hide — silently dropping a home someone saved is
        // worse than showing it as gone.
        opacity: gone ? 0.55 : 1,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            boxShadow: [
              BoxShadow(
                color: AppColors.ink.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1.16,
                child: PropertyImage(
                  seed: p.gradientSeed,
                  url: p.photos.isEmpty ? null : p.photos.first,
                  decodeWidth: MediaQuery.sizeOf(context).width / 2,
                  child: Stack(
                    children: [
                      Positioned(
                        top: 10,
                        right: 10,
                        child: _SavedHeart(listingId: p.id),
                      ),
                      if (p.hasPriceDrop && !gone)
                        Positioned(
                          left: 10,
                          bottom: 10,
                          child: _PriceDropBadge(amount: p.priceDrop,
                              currency: p.currency),
                        ),
                      if (gone)
                        Positioned(
                          left: 10,
                          bottom: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              (p.unavailableReason ?? 'GONE').toUpperCase(),
                              style: AppTextStyles.micro(color: Colors.white)
                                  .copyWith(fontSize: 11, letterSpacing: 0.4),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style:
                            AppTextStyles.bodyStrong().copyWith(fontSize: 15),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${p.beds} Bed · ${formatThousands(p.sqft)} sqft',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.caption(),
                      ),
                      const Spacer(),
                      if (gone)
                        Text('No longer available',
                            style: AppTextStyles.bodyStrong(
                                color: AppColors.inkMuted))
                      else
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Flexible(
                              child: Text(
                                '${p.currency} ${p.priceFormatted}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.bodyStrong()
                                    .copyWith(fontSize: 15.5),
                              ),
                            ),
                            if (p.hasPriceDrop) ...[
                              const SizedBox(width: 5),
                              Text(
                                _short(p.previousPrice!),
                                style: AppTextStyles.caption().copyWith(
                                  decoration: TextDecoration.lineThrough,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
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

  static String _short(int v) =>
      v >= 1000 ? '${(v / 1000).round()}k' : '$v';
}

class _PriceDropBadge extends StatelessWidget {
  final int amount;
  final String currency;

  const _PriceDropBadge({required this.amount, required this.currency});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.success,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.arrow_drop_down_rounded,
              color: Colors.white, size: 18),
          Text(
            '$currency ${formatThousands(amount)}',
            style: AppTextStyles.micro(color: Colors.white)
                .copyWith(fontSize: 11.5, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// Always-filled amber heart. Unsaving updates the store but leaves the card in
/// place for this visit.
class _SavedHeart extends StatelessWidget {
  final String listingId;
  const _SavedHeart({required this.listingId});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.savedOf(context);

    return ValueListenableBuilder<Set<String>>(
      valueListenable: store,
      builder: (context, saved, _) {
        final isSaved = saved.contains(listingId);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => store.toggle(listingId),
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              shape: BoxShape.circle,
            ),
            padding: const EdgeInsets.all(8),
            child: SvgPicture.asset(
              AppIcons.heartSolid,
              colorFilter: ColorFilter.mode(
                isSaved ? AppColors.amber : Colors.white,
                BlendMode.srcIn,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// F02 — "Nothing saved yet".
class SavedEmptyState extends StatelessWidget {
  const SavedEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset(AppIcons.savedEmpty, width: 148, height: 148),
            const SizedBox(height: 22),
            Text('Nothing saved yet',
                style: AppTextStyles.display().copyWith(fontSize: 24)),
            const SizedBox(height: 10),
            Text(
              'Tap the heart on any home to keep it here — '
              "we'll watch prices for you and tell you when they drop.",
              textAlign: TextAlign.center,
              style: AppTextStyles.body(color: AppColors.inkMuted),
            ),
            const SizedBox(height: 24),
            PrimaryButton(
              label: 'Start exploring',
              leadingIcon: Icons.search_rounded,
              expand: false,
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reels tab.
///
/// Saved reels aren't modelled — `SavedListingsStore` keys on listing ids and
/// `Reel` has its own id space, so there's nothing to resolve yet. Rather than
/// fake it, this states the position. Add a `savedReels` notifier and a
/// `GET /saved-reels` method and this becomes a grid of thumbnails.
class _ReelsTab extends StatelessWidget {
  const _ReelsTab();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: EmptyStateView(
        icon: Icons.video_library_outlined,
        title: 'No saved reels',
        subtitle:
            'Save a reel from the feed and it will show up here. Reel saving '
            'is still being wired up.',
      ),
    );
  }
}

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/property.dart';
import '../models/property_category.dart';
import '../models/search_query.dart';
import '../state/app_scope.dart';
import '../state/listings_controller.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../widgets/app_icons.dart';
import '../widgets/home_nav_bar.dart';
import '../widgets/listing_card.dart';
import '../widgets/pill_button.dart';
import '../widgets/property_image.dart';
import '../widgets/state_views.dart';
import 'filters_sheet.dart';
import 'property_detail_screen.dart';
import 'results_screen.dart';

/// Screens 7 and 8 (Discover — Residential / Commercial).
///
/// ## Why this screen used to render blank
///
/// The hero was `SliverToBoxAdapter > ClipRRect > PropertyImage`, and
/// `PropertyImage` is a `Stack(fit: StackFit.expand)`. A sliver hands its child
/// *unbounded* vertical constraints, and `StackFit.expand` tightens whatever it
/// receives onto its children — so the stack was asked to be infinitely tall.
/// That throws during layout, and because the hero is the first sliver the
/// whole `CustomScrollView` fails to lay out and you get a white screen with
/// nothing on it.
///
/// Every other `PropertyImage` call site in the app happens to sit inside a
/// bounded box (a grid cell with an aspect ratio, a `SizedBox`, a `PageView`),
/// which is why this was the only screen affected.
///
/// The fix is that the hero now declares its own height ([_Hero.contentHeight]
/// plus the status-bar inset) instead of trying to inherit one. Nothing else
/// about the layering changed.
class HomeScreen extends StatefulWidget {
  final ValueChanged<NavTab> onNavTap;
  const HomeScreen({super.key, required this.onNavTap});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with AutomaticKeepAliveClientMixin {
  late final AsyncController<List<Property>> _highlights;
  late final AsyncController<List<Community>> _communities;

  Purpose _purpose = Purpose.rent;
  PropertySegment _segment = PropertySegment.residential;

  /// What the category grid is currently *showing*. These trail [_purpose]
  /// and [_segment] by the length of the switch animation, so the boxes fade
  /// out as the old version, the loader plays, and they come back as the new.
  Purpose _gridPurpose = Purpose.rent;
  PropertySegment _gridSegment = PropertySegment.residential;

  /// True while the switch loader is on screen (either toggle).
  bool _switching = false;
  Timer? _switchTimer;

  /// How long the loader stays up. Long enough to read as "the page changed",
  /// short enough not to feel like waiting.
  static const Duration _switchDuration = Duration(milliseconds: 750);

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Both read _purpose when they run, so a reload after the toggle fetches
    // the rent or sale version.
    _highlights = AsyncController<List<Property>>(
      () => AppScope.repositoryOf(context)
          .highlights(purpose: _purpose, segment: _segment),
    );
    _communities = AsyncController<List<Community>>(
      () => AppScope.repositoryOf(context)
          .popularCommunities(purpose: _purpose, segment: _segment),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _highlights.load();
      _communities.load();
    });
  }

  void _setPurpose(Purpose next) {
    if (next != _purpose) _switchTo(purpose: next);
  }

  void _setSegment(PropertySegment next) {
    if (next != _segment) _switchTo(segment: next);
  }

  /// Either toggle: start the loader, refetch both carousels for the new
  /// combination, and bring the boxes back once the loader has played.
  ///
  /// Tapping again mid-switch restarts the timer, so the boxes always end up
  /// showing whatever is selected last.
  void _switchTo({Purpose? purpose, PropertySegment? segment}) {
    setState(() {
      _purpose = purpose ?? _purpose;
      _segment = segment ?? _segment;
      _switching = true;
    });
    _highlights.load();
    _communities.load();
    _switchTimer?.cancel();
    _switchTimer = Timer(_switchDuration, () {
      if (!mounted) return;
      setState(() {
        _switching = false;
        _gridPurpose = _purpose;
        _gridSegment = _segment;
      });
    });
  }

  @override
  void dispose() {
    _switchTimer?.cancel();
    _highlights.dispose();
    _communities.dispose();
    super.dispose();
  }

  SearchQuery get _baseQuery =>
      SearchQuery(purpose: _purpose, segment: _segment);

  void _openResults({SearchQuery? query}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ResultsScreen(initialQuery: query ?? _baseQuery),
      ),
    );
  }

  void _openSearch() => widget.onNavTap(NavTab.search);

  /// Account lives in the hero now rather than the bottom bar, but it is still
  /// a tab switch — not a push — so the nav bar stays put.
  void _openProfile() => widget.onNavTap(NavTab.profile);

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<SearchQuery>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FiltersSheet(query: _baseQuery),
    );
    if (result != null && mounted) _openResults(query: result);
  }

  void _openDetail(Property property) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PropertyDetailScreen(
          propertyId: property.id,
          preloaded: property,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // The grid shows the version it's animating to only once the loader is
    // done, so it uses the trailing _grid* values.
    final categories = _gridSegment == PropertySegment.residential
        ? PropertyCategory.residential
        : PropertyCategory.commercial;
    final what = _segment == PropertySegment.commercial
        ? 'commercial spaces'
        : 'homes';
    final emptyLabel =
        'No $what ${_purpose == Purpose.sale ? 'for sale' : 'for rent'} yet';

    return ColoredBox(
      color: AppColors.bg,
      child: RefreshIndicator(
        color: AppColors.primary,
        edgeOffset: MediaQuery.paddingOf(context).top,
        onRefresh: () async {
          await Future.wait([_highlights.load(), _communities.load()]);
        },
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _Hero(
                onSearchTap: _openSearch,
                onFilterTap: _openFilters,
                onProfileTap: _openProfile,
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.screenPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 20),
                    Center(
                      child: _PurposeToggle(
                        purpose: _purpose,
                        onChanged: _setPurpose,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _SegmentToggle(
                      segment: _segment,
                      onChanged: _setSegment,
                    ),
                    const SizedBox(height: 18),
                    _PurposeSwitchArea(
                      switching: _switching,
                      purpose: _purpose,
                      segment: _segment,
                      tileCount: categories.length,
                      grid: _CategoryGrid(
                        // A new key replays the staggered entrance whenever
                        // the boxes come back for a different purpose or
                        // segment.
                        key: ValueKey(
                            'grid-${_gridPurpose.name}-${_gridSegment.name}'),
                        categories: categories,
                        onTap: (c) => _openResults(
                          query: _baseQuery.copyWith(propertyType: c.wire),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    _SectionHeader(
                      title: 'The most relevant',
                      onSeeAll: () => _openResults(),
                    ),
                    const SizedBox(height: 14),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: DealCard.height,
                child: ListenableBuilder(
                  listenable: _highlights,
                  builder: (context, _) => _FadeSwap(
                    swapKey: '${_purpose.name}-${_segment.name}-'
                        '${_highlights.state.runtimeType}',
                    child: _highlights.state.when(
                    loading: () => ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.screenPadding),
                      itemCount: 3,
                      separatorBuilder: (_, _) => const SizedBox(width: 14),
                      itemBuilder: (_, _) => const DealCardSkeleton(),
                    ),
                    error: (_) => Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.screenPadding),
                      child: ErrorStateView(
                        compact: true,
                        message: "Couldn't load listings.",
                        onRetry: _highlights.load,
                      ),
                    ),
                    data: (items) => items.isEmpty
                        ? _EmptyNote(message: emptyLabel)
                        : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.screenPadding),
                      itemCount: items.length,
                      cacheExtent: 600,
                      separatorBuilder: (_, _) => const SizedBox(width: 14),
                      itemBuilder: (context, i) => DealCard(
                        property: items[i],
                        onTap: () => _openDetail(items[i]),
                      ),
                    ),
                  ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.screenPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 28),
                    _SectionHeader(
                      title: 'Popular communities',
                      onSeeAll: () => _openResults(),
                    ),
                    const SizedBox(height: 14),
                    ListenableBuilder(
                      listenable: _communities,
                      builder: (context, _) => _FadeSwap(
                        swapKey: '${_purpose.name}-${_segment.name}-'
                            '${_communities.state.runtimeType}',
                        child: _communities.state.when(
                        loading: () => const _CommunityGridSkeleton(),
                        error: (_) => ErrorStateView(
                          compact: true,
                          message: "Couldn't load communities.",
                          onRetry: _communities.load,
                        ),
                        data: (items) => items.isEmpty
                            ? _EmptyNote(message: emptyLabel, inset: false)
                            : GridView.builder(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: items.length,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 1.45,
                          ),
                          itemBuilder: (context, i) => _CommunityTile(
                            community: items[i],
                            onTap: () => _openResults(
                              query:
                                  _baseQuery.copyWith(community: items[i].name),
                            ),
                          ),
                        ),
                      ),
                      ),
                    ),
                    SizedBox(height: HomeNavBar.reservedSpace(context) + 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hero
// ---------------------------------------------------------------------------

/// Full-bleed photo header with the market picker, greeting and search bar.
///
/// Declares its own height — see the note at the top of this file for why that
/// matters. [contentHeight] is the space below the status bar, taken from the
/// Figma frame (272pt total on a 390pt-wide device).
class _Hero extends StatelessWidget {
  static const double contentHeight = 226;
  static const double radius = 28;

  final VoidCallback onSearchTap;
  final VoidCallback onFilterTap;
  final VoidCallback onProfileTap;

  const _Hero({
    required this.onSearchTap,
    required this.onFilterTap,
    required this.onProfileTap,
  });

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;

    return SizedBox(
      height: topInset + contentHeight,
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(radius),
          bottomRight: Radius.circular(radius),
        ),
        child: PropertyImage(
          seed: 7,
          decodeWidth: MediaQuery.sizeOf(context).width,
          child: DecoratedBox(
            // Const literal colours rather than withValues() so the scrim
            // isn't recomputed on every build.
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0, 0.5, 1],
                colors: [
                  Color(0x99000000),
                  Color(0x4D000000),
                  Color(0x73000000),
                ],
              ),
            ),
            child: Padding(
              padding: EdgeInsets.only(top: topInset),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SvgPicture.asset(
                          AppIcons.pinSmall,
                          width: 13,
                          height: 15,
                          colorFilter: const ColorFilter.mode(
                              Colors.white, BlendMode.srcIn),
                        ),
                        const SizedBox(width: 7),
                        // Where the user physically is, from GPS. Independent
                        // of the market, which decides whose listings show
                        // below and is set in onboarding / settings.
                        //
                        // Expanded (not Flexible + Spacer) so the icons are
                        // pinned to the right edge whatever the city name's
                        // length.
                        Expanded(
                          child: AppStateBuilder(
                            builder: (context, state) => Text(
                              state.headerCity,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.h2(color: Colors.white)
                                  .copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const _HeroIcon(asset: AppIcons.bell, label: 'Notifications'),
                        const SizedBox(width: 6),
                        // Account moved out of the bottom bar and into the
                        // hero, freeing the fifth nav slot for Chats.
                        _HeroIcon(
                          asset: NavIcons.profileAvatar,
                          label: 'Account',
                          onTap: onProfileTap,
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      'Hey! Tell us where you\nwant to live next?',
                      style: AppTextStyles.display(color: Colors.white)
                          .copyWith(
                              fontSize: 26, height: 34 / 26, letterSpacing: -0.2),
                    ),
                    const SizedBox(height: 16),
                    _HeroSearchBar(
                      onTap: onSearchTap,
                      onFilterTap: onFilterTap,
                    ),
                    const _OutsideMarketNote(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroSearchBar extends StatelessWidget {
  final VoidCallback onTap;
  final VoidCallback onFilterTap;
  const _HeroSearchBar({required this.onTap, required this.onFilterTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 56,
        padding: const EdgeInsetsDirectional.only(start: 18, end: 5),
        decoration: BoxDecoration(
          color: const Color(0x4D000000),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0x33FFFFFF)),
        ),
        child: Row(
          children: [
            SvgPicture.asset(
              NavIcons.search,
              width: 19,
              height: 19,
              colorFilter:
                  const ColorFilter.mode(Colors.white, BlendMode.srcIn),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'What are you looking for?',
                style: AppTextStyles.body(color: Colors.white)
                    .copyWith(fontSize: 16),
              ),
            ),
            Pressable(
              onTap: onFilterTap,
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.45),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(13),
                child: SvgPicture.asset(
                  AppIcons.filterSliders,
                  colorFilter:
                      const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Toggles
// ---------------------------------------------------------------------------

/// For Rent / For Sale. Hug-width, floating white pill with a teal active
/// segment — per the Figma it sits centred and raised off the background.
class _PurposeToggle extends StatelessWidget {
  final Purpose purpose;
  final ValueChanged<Purpose> onChanged;

  const _PurposeToggle({required this.purpose, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PurposeSegment(
            label: 'For Rent',
            icon: NavIcons.purposeRent,
            active: purpose == Purpose.rent,
            onTap: () => onChanged(Purpose.rent),
          ),
          _PurposeSegment(
            label: 'For Sale',
            icon: NavIcons.purposeSale,
            active: purpose == Purpose.sale,
            onTap: () => onChanged(Purpose.sale),
          ),
        ],
      ),
    );
  }
}

class _PurposeSegment extends StatelessWidget {
  final String label;
  final String icon;
  final bool active;
  final VoidCallback onTap;

  const _PurposeSegment({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = active ? Colors.white : AppColors.ink;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
        decoration: BoxDecoration(
          color: active ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.30),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgPicture.asset(
              icon,
              width: 17,
              height: 17,
              colorFilter: ColorFilter.mode(fg, BlendMode.srcIn),
            ),
            const SizedBox(width: 8),
            Text(label, style: AppTextStyles.bodyStrong(color: fg)),
          ],
        ),
      ),
    );
  }
}

/// Residential / Commercial. Full-width white card, amber active half.
class _SegmentToggle extends StatelessWidget {
  final PropertySegment segment;
  final ValueChanged<PropertySegment> onChanged;

  const _SegmentToggle({required this.segment, required this.onChanged});

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
            child: _SegmentHalf(
              label: 'Residential',
              active: segment == PropertySegment.residential,
              onTap: () => onChanged(PropertySegment.residential),
            ),
          ),
          Expanded(
            child: _SegmentHalf(
              label: 'Commercial',
              active: segment == PropertySegment.commercial,
              onTap: () => onChanged(PropertySegment.commercial),
            ),
          ),
        ],
      ),
    );
  }
}

class _SegmentHalf extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _SegmentHalf({
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
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
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

// ---------------------------------------------------------------------------
// Category grid
// ---------------------------------------------------------------------------

class _CategoryGrid extends StatelessWidget {
  final List<PropertyCategory> categories;
  final ValueChanged<PropertyCategory> onTap;

  const _CategoryGrid({super.key, required this.categories, required this.onTap});

  static const double spacing = 12;
  static const double aspectRatio = 0.80;
  static const int columns = 3;

  /// Height the grid will take at [width] — the loader uses it so swapping
  /// between the two never moves anything below.
  static double heightFor(double width, int count) {
    final tileWidth = (width - spacing * (columns - 1)) / columns;
    final tileHeight = tileWidth / aspectRatio;
    final rows = (count + columns - 1) ~/ columns;
    return rows * tileHeight + math.max(0, rows - 1) * spacing;
  }

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: categories.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: spacing,
        crossAxisSpacing: spacing,
        childAspectRatio: aspectRatio,
      ),
      itemBuilder: (context, i) => _StaggeredEntrance(
        index: i,
        child: _CategoryTile(
          category: categories[i],
          onTap: () => onTap(categories[i]),
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final PropertyCategory category;
  final VoidCallback onTap;
  const _CategoryTile({required this.category, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              category.asset,
              width: 52,
              height: 52,
              // Category art is tiny on screen; decoding it at 3x display size
              // is plenty and keeps nine of them off the decode budget.
              cacheWidth: 156,
              filterQuality: FilterQuality.medium,
            ),
            const SizedBox(height: 10),
            Text(
              category.gridLabel,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption(color: AppColors.ink).copyWith(
                fontSize: 13.5,
                height: 17 / 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              category.subtitle,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.micro(color: AppColors.inkMuted)
                  .copyWith(fontSize: 11, fontWeight: FontWeight.w400),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// For Rent ⇄ For Sale switch animation
// ---------------------------------------------------------------------------

/// Holds the category grid and, while [switching], cross-fades it to a loader
/// of exactly the same height — so nothing below the grid jumps.
///
/// Sequence on a tap: boxes fade out (220 ms) → loader fades in with bouncing
/// dots and "Showing homes for sale" → after the switch timer, loader fades out
/// and the boxes come back one after another (see [_StaggeredEntrance]).
class _PurposeSwitchArea extends StatelessWidget {
  final bool switching;
  final Purpose purpose;
  final PropertySegment segment;
  final int tileCount;
  final Widget grid;

  const _PurposeSwitchArea({
    required this.switching,
    required this.purpose,
    required this.segment,
    required this.tileCount,
    required this.grid,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = _CategoryGrid.heightFor(constraints.maxWidth, tileCount);
        return SizedBox(
          height: height,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            reverseDuration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.topCenter,
              children: [...previous, if (current != null) current],
            ),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.98, end: 1).animate(animation),
                child: child,
              ),
            ),
            child: switching
                ? _PurposeLoader(
                    key: ValueKey('loader-${purpose.name}-${segment.name}'),
                    purpose: purpose,
                    segment: segment,
                    height: height,
                  )
                : grid,
          ),
        );
      },
    );
  }
}

/// Faint placeholder boxes in the grid's shape, with three bouncing dots and
/// a line saying which version is loading.
class _PurposeLoader extends StatefulWidget {
  final Purpose purpose;
  final PropertySegment segment;
  final double height;

  const _PurposeLoader({
    super.key,
    required this.purpose,
    required this.segment,
    required this.height,
  });

  @override
  State<_PurposeLoader> createState() => _PurposeLoaderState();
}

class _PurposeLoaderState extends State<_PurposeLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _dots = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _dots.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final what = widget.segment == PropertySegment.commercial
        ? 'commercial'
        : 'homes';
    final label =
        'Showing $what ${widget.purpose == Purpose.sale ? 'for sale' : 'for rent'}';

    return SizedBox(
      height: widget.height,
      child: Stack(
        children: [
          // Ghost tiles in the same 3-column layout as the real grid.
          Positioned.fill(
            child: GridView.builder(
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 9,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _CategoryGrid.columns,
                mainAxisSpacing: _CategoryGrid.spacing,
                crossAxisSpacing: _CategoryGrid.spacing,
                childAspectRatio: _CategoryGrid.aspectRatio,
              ),
              itemBuilder: (_, _) =>
                  const SkeletonBox(height: double.infinity, radius: AppRadius.md),
            ),
          ),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.ink.withValues(alpha: 0.10),
                    blurRadius: 18,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RepaintBoundary(
                    child: AnimatedBuilder(
                      animation: _dots,
                      builder: (context, _) => Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < 3; i++) _dot(i),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    label,
                    style: AppTextStyles.bodyStrong(color: AppColors.ink)
                        .copyWith(fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// One dot: rises and brightens in turn, a third of a cycle after the last.
  Widget _dot(int i) {
    final phase = (_dots.value - i / 3) % 1.0;
    final lift = math.sin(phase * math.pi * 2).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2.5),
      child: Transform.translate(
        offset: Offset(0, -5 * lift),
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.45 + 0.55 * lift),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

/// Fades and lifts a tile into place, each one a beat after the previous, so
/// the grid "deals in" left-to-right, top-to-bottom. Plays once per mount —
/// the grid's key changes on every switch, which remounts the tiles.
///
/// Skipped when the device has "Remove animations" turned on.
class _StaggeredEntrance extends StatelessWidget {
  final int index;
  final Widget child;

  const _StaggeredEntrance({required this.index, required this.child});

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final delay = 45 * index;
    const run = 320;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: delay + run),
      curve: Interval(delay / (delay + run), 1, curve: Curves.easeOutCubic),
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 14 * (1 - t)),
          child: Transform.scale(scale: 0.94 + 0.06 * t, child: child),
        ),
      ),
    );
  }
}

/// Small inline "nothing here yet" for the carousels — the full
/// [EmptyStateView] is too tall for a 1-row carousel slot.
class _EmptyNote extends StatelessWidget {
  final String message;

  /// The carousel row is full-bleed, so it needs the screen padding; the
  /// communities block is already inside it.
  final bool inset;

  const _EmptyNote({required this.message, this.inset = true});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: inset ? AppSpacing.screenPadding : 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            const Icon(Icons.home_work_outlined,
                color: AppColors.inkMuted, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: AppTextStyles.body(color: AppColors.inkMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cross-fade for the carousels: skeleton → cards (or error) fade instead of
/// popping, and a rent → sale reload fades through its skeleton.
class _FadeSwap extends StatelessWidget {
  final String swapKey;
  final Widget child;

  const _FadeSwap({required this.swapKey, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topLeft,
        children: [...previous, if (current != null) current],
      ),
      child: KeyedSubtree(key: ValueKey(swapKey), child: child),
    );
  }
}

// ---------------------------------------------------------------------------
// Communities
// ---------------------------------------------------------------------------

class _CommunityTile extends StatelessWidget {
  final Community community;
  final VoidCallback onTap;
  const _CommunityTile({required this.community, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: PropertyImage(
        seed: community.gradientSeed,
        url: community.photoUrl,
        decodeWidth: MediaQuery.sizeOf(context).width / 2,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0.35, 1],
              colors: [Color(0x00000000), Color(0xA6000000)],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  community.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyStrong(color: Colors.white)
                      .copyWith(fontSize: 16),
                ),
                const SizedBox(height: 1),
                Text(
                  '${formatThousands(community.homes)} homes',
                  style: AppTextStyles.caption(color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CommunityGridSkeleton extends StatelessWidget {
  const _CommunityGridSkeleton();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 4,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.45,
      ),
      itemBuilder: (_, _) =>
          const SkeletonBox(height: 100, radius: AppRadius.md),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback onSeeAll;
  const _SectionHeader({required this.title, required this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            title,
            style: AppTextStyles.h1().copyWith(fontSize: 21),
          ),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onSeeAll,
          child: Text('See all',
              style: AppTextStyles.bodyStrong(color: AppColors.primary)),
        ),
      ],
    );
  }
}


/// Shown when the user's location and their selected market disagree — sitting
/// in Lahore with UAE selected, for example.
///
/// The hero names the real city, so without this line the city and the results
/// contradict each other and read as a bug. It also distinguishes the two
/// cases: a market we haven't launched yet, versus one the user simply chose.
class _OutsideMarketNote extends StatelessWidget {
  const _OutsideMarketNote();

  @override
  Widget build(BuildContext context) {
    return AppStateBuilder(
      builder: (context, state) {
        if (!state.outsideLaunchedMarket) return const SizedBox.shrink();
        final detected = state.detectedMarket?.label ?? state.detectedCity;
        final launching = state.detectedMarket?.isLaunched != true;
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(
            children: [
              const Icon(Icons.info_outline_rounded,
                  size: 15, color: Colors.white70),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  detected == null
                      ? 'Showing ${state.market.label} homes.'
                      : launching
                          ? '$detected is launching soon — showing '
                              '${state.market.label} homes.'
                          : 'Showing ${state.market.label} homes. '
                              'Switch market in Settings.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption(color: Colors.white70),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}


/// Bell / avatar in the Home hero.
///
/// Both glyphs come from different exports with different internal padding, so
/// each is drawn into an identical 22x22 box with `BoxFit.contain`. Sizing them
/// individually is what made them look mismatched and off-centre from each
/// other. The 44x44 outer box is the tap target — icons that small need one
/// regardless of how big they look.
class _HeroIcon extends StatelessWidget {
  final String asset;
  final String label;
  final VoidCallback? onTap;

  const _HeroIcon({required this.asset, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: SvgPicture.asset(
                asset,
                fit: BoxFit.contain,
                colorFilter:
                    const ColorFilter.mode(Colors.white, BlendMode.srcIn),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

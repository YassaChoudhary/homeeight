import 'package:flutter/material.dart';

import '../../core/async_value.dart';
import '../../models/my_listing.dart';
import '../../models/property.dart';
import '../../state/app_scope.dart';
import '../../state/listings_controller.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/property_image.dart';
import '../../widgets/state_views.dart';
import '../../models/lister_profile.dart';
import 'lister_gate.dart';
import '../property_detail_screen.dart';
import 'listing_performance_screen.dart';

/// Screen 31 — "My Listings".
///
/// The seller's home. Three things at once: how the portfolio is doing (the
/// dark header), what state each listing is in (the tabs), and what to do next
/// about any one of them (the row and its ⋮ menu).
///
/// ## Tabs filter in memory
///
/// One `myListings()` call fetches everything and the tabs filter the result,
/// rather than a request per tab. The counts on the tab labels have to be right
/// the moment the screen opens — "Live · 2" can't wait for a second round trip
/// — and a seller's list is tens of rows, not thousands.
class MyListingsScreen extends StatefulWidget {
  const MyListingsScreen({super.key});

  @override
  State<MyListingsScreen> createState() => _MyListingsScreenState();
}

class _MyListingsScreenState extends State<MyListingsScreen> {
  late final AsyncController<List<MyListing>> _listings;
  ListingFilter _filter = ListingFilter.all;

  @override
  void initState() {
    super.initState();
    _listings = AsyncController<List<MyListing>>(
      () => AppScope.repositoryOf(context).myListings(),
    )..load();
  }

  @override
  void dispose() {
    _listings.dispose();
    super.dispose();
  }

  Future<void> _openPostFlow({MyListing? existing}) async {
    // Same verification check as the + button.
    await startListing(context, draft: existing?.draft);
    // Always reload on return: the flow may have submitted, saved a draft or
    // changed nothing, and guessing which is how a stale row ends up on screen.
    if (mounted) _listings.load();
  }

  /// The listing page as buyers see it. A live listing opens the real page;
  /// anything not public yet (draft, in review, rejected) opens a preview
  /// built from the saved listing.
  Future<void> _openDetails(MyListing listing) async {
    final user = AppScope.authOf(context).user;
    final profile = user?.listerProfile;
    final agency = (profile?.organisation.isNotEmpty ?? false)
        ? profile!.organisation
        : ((profile?.type ?? ListerType.individual) == ListerType.individual
            ? 'Property owner'
            : '');
    final preview = listing.draft.toPreviewProperty(
      agentName: user?.name ?? '',
      agency: agency,
      avatarUrl: user?.avatarUrl,
    );
    final isLive = listing.status == ListingStatus.live;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PropertyDetailScreen(
          propertyId: listing.id,
          preloaded: preview,
          previewOnly: !isLive,
        ),
      ),
    );
    if (mounted) _listings.load();
  }

  Future<void> _openPerformance(MyListing listing) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ListingPerformanceScreen(listing: listing),
      ),
    );
    if (mounted) _listings.load();
  }

  void _showError(Object e) {
    final message = e is RepositoryException
        ? e.message
        : 'Something went wrong. Try again.';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.navDark,
        ),
      );
  }

  void _notYet(String what) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('$what is work in progress — coming soon.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.navDark,
        ),
      );
  }

  /// The ⋮ menu. Performance is the first item because it's the one the design
  /// calls out, and the destructive action is last and red.
  Future<void> _openRowMenu(MyListing listing) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
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
              const SizedBox(height: 8),
              if (listing.hasMetrics)
                _MenuItem(
                  icon: Icons.insights_rounded,
                  label: 'View performance',
                  onTap: () => Navigator.of(sheetContext).pop('performance'),
                ),
              _MenuItem(
                icon: Icons.edit_outlined,
                label: 'Edit listing',
                onTap: () => Navigator.of(sheetContext).pop('edit'),
              ),
              if (listing.status == ListingStatus.live) ...[
                _MenuItem(
                  icon: Icons.bolt_rounded,
                  label: 'Boost this listing',
                  onTap: () => Navigator.of(sheetContext).pop('boost'),
                ),
                _MenuItem(
                  icon: Icons.ios_share_rounded,
                  label: 'Share',
                  onTap: () => Navigator.of(sheetContext).pop('share'),
                ),
                _MenuItem(
                  icon: Icons.check_circle_outline_rounded,
                  label: 'Mark as rented / sold',
                  onTap: () => Navigator.of(sheetContext).pop('close'),
                ),
              ],
              _MenuItem(
                icon: Icons.delete_outline_rounded,
                label: 'Delete listing',
                tint: AppColors.danger,
                onTap: () => Navigator.of(sheetContext).pop('delete'),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );

    if (action == null || !mounted) return;

    switch (action) {
      case 'performance':
        await _openPerformance(listing);
      case 'edit':
        await _openPostFlow(existing: listing);
      case 'boost':
        await _boost(listing);
      case 'share':
        _notYet('Sharing a listing');
      case 'close':
        await _setStatus(listing, ListingStatus.closed);
      case 'delete':
        await _confirmDelete(listing);
    }
  }

  Future<void> _boost(MyListing listing) async {
    try {
      await AppScope.repositoryOf(context).boostListing(listing.id);
      if (!mounted) return;
      _listings.load();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text("Boost requested — we'll contact you to set it up."),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.navDark,
          ),
        );
    } catch (e) {
      if (mounted) _showError(e);
    }
  }

  Future<void> _setStatus(MyListing listing, ListingStatus status) async {
    try {
      await AppScope.repositoryOf(context)
          .updateListingStatus(listing.id, status);
      if (mounted) _listings.load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text("Couldn't update the listing. Try again."),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.navDark,
          ),
        );
    }
  }

  Future<void> _confirmDelete(MyListing listing) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        title: Text('Delete this listing?', style: AppTextStyles.h2()),
        content: Text(
          'Its views, enquiries and saves go with it. This cannot be undone.',
          style: AppTextStyles.body(color: AppColors.inkMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Keep',
                style: AppTextStyles.bodyStrong(color: AppColors.inkMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Delete',
                style: AppTextStyles.bodyStrong(color: AppColors.danger)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    try {
      await AppScope.repositoryOf(context).deleteListing(listing.id);
      if (mounted) _listings.load();
    } catch (e) {
      if (mounted) _showError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      floatingActionButton: _PostFab(onTap: _openPostFlow),
      body: ListenableBuilder(
        listenable: _listings,
        builder: (context, _) {
          final all = _listings.state.valueOrNull ?? const <MyListing>[];
          final visible = all.where(_filter.matches).toList();

          return Column(
            children: [
              _StatsHeader(
                listings: all,
                loading: _listings.state.isLoading,
                onFilter: (f) => setState(() => _filter = f),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.screenPadding),
                  children: [
                    for (final filter in ListingFilter.values) ...[
                      _FilterTab(
                        // The count sits in the label, as the design shows —
                        // "Draft · 1" answers "is there anything in there"
                        // without a tap.
                        label: '${filter.label} · '
                            '${all.where(filter.matches).length}',
                        active: _filter == filter,
                        onTap: () => setState(() => _filter = filter),
                      ),
                      const SizedBox(width: 10),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: _listings.state.when(
                  loading: () => ListView(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.screenPadding, 12, AppSpacing.screenPadding, 24),
                    children: const [
                      _ListingRowSkeleton(),
                      _ListingRowSkeleton(),
                      _ListingRowSkeleton(),
                    ],
                  ),
                  error: (_) => Center(
                    child: ErrorStateView(
                      message: "We couldn't load your listings.",
                      onRetry: _listings.load,
                    ),
                  ),
                  data: (_) => visible.isEmpty
                      ? Center(
                          child: EmptyStateView(
                            icon: Icons.home_work_outlined,
                            title: _filter == ListingFilter.all
                                ? 'No listings yet'
                                : 'Nothing in ${_filter.label.toLowerCase()}',
                            subtitle: _filter == ListingFilter.all
                                ? 'Post your first property and it appears '
                                    'here with its views and enquiries.'
                                : 'Switch tabs to see your other listings.',
                            action: _filter == ListingFilter.all
                                ? PrimaryButton(
                                    label: 'Post a listing',
                                    expand: false,
                                    onTap: _openPostFlow,
                                  )
                                : null,
                          ),
                        )
                      : ListView.separated(
                          padding: EdgeInsets.fromLTRB(
                            AppSpacing.screenPadding,
                            12,
                            AppSpacing.screenPadding,
                            // Clears the FAB.
                            96,
                          ),
                          itemCount: visible.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 14),
                          itemBuilder: (context, i) => _ListingRow(
                            listing: visible[i],
                            onMenu: () => _openRowMenu(visible[i]),
                            onBoost: () => _boost(visible[i]),
                            onContinue: () =>
                                _openPostFlow(existing: visible[i]),
                            onTap: () => _openDetails(visible[i]),
                          ),
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Dark rounded header: how many listings are in review, approved (live)
/// and rejected. Tapping a figure shows those listings.
class _StatsHeader extends StatelessWidget {
  final List<MyListing> listings;
  final bool loading;
  final ValueChanged<ListingFilter> onFilter;

  const _StatsHeader({
    required this.listings,
    required this.loading,
    required this.onFilter,
  });

  int _count(ListingStatus status) =>
      listings.where((l) => l.status == status).length;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;

    return Container(
      padding: EdgeInsets.only(top: topInset + 4, bottom: 22),
      decoration: const BoxDecoration(
        color: AppColors.navDark,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).maybePop(),
                  child: const Padding(
                    padding: EdgeInsets.all(10),
                    child: Icon(Icons.arrow_back_rounded,
                        color: Colors.white, size: 24),
                  ),
                ),
                Expanded(
                  child: Text('My Listings',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.h1(color: Colors.white)),
                ),
                const SizedBox(width: 44),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenPadding),
            child: Row(
              children: [
                Expanded(
                  child: _StatTile(
                    value: '${_count(ListingStatus.inReview)}',
                    label: 'In review',
                    valueColor: AppColors.amber,
                    loading: loading,
                    onTap: () => onFilter(ListingFilter.inReview),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatTile(
                    value: '${_count(ListingStatus.live)}',
                    label: 'Approved',
                    valueColor: AppColors.primaryOnDark,
                    loading: loading,
                    onTap: () => onFilter(ListingFilter.live),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatTile(
                    value: '${_count(ListingStatus.rejected)}',
                    label: 'Rejected',
                    valueColor: const Color(0xFFFF8A80),
                    loading: loading,
                    onTap: () => onFilter(ListingFilter.rejected),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One figure in the header: big number, label under it.
class _StatTile extends StatelessWidget {
  final String value;
  final String label;
  final Color valueColor;
  final bool loading;
  final VoidCallback onTap;

  const _StatTile({
    required this.value,
    required this.label,
    required this.onTap,
    this.valueColor = Colors.white,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        height: 84,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (loading)
              const SkeletonBox(height: 24, width: 40)
            else
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.display(color: valueColor)
                    .copyWith(fontSize: 24),
              ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption(color: Colors.white70)
                  .copyWith(fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterTab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _FilterTab({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? AppColors.navDark : AppColors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: active ? AppColors.navDark : AppColors.line),
        ),
        child: Text(
          label,
          style: AppTextStyles.bodyStrong(
            color: active ? Colors.white : AppColors.ink,
          ).copyWith(fontSize: 14.5),
        ),
      ),
    );
  }
}

/// One listing row. Three shapes behind one widget, keyed off status: a live
/// row shows metrics and Boost, a review row shows progress, a draft row shows
/// what's missing and a way back in.
class _ListingRow extends StatelessWidget {
  final MyListing listing;
  final VoidCallback onMenu;
  final VoidCallback onBoost;
  final VoidCallback onContinue;
  final VoidCallback onTap;

  const _ListingRow({
    required this.listing,
    required this.onMenu,
    required this.onBoost,
    required this.onContinue,
    required this.onTap,
  });

  Color get _badgeColor => switch (listing.status) {
        ListingStatus.live => AppColors.primary,
        ListingStatus.inReview => AppColors.amber,
        ListingStatus.draft => AppColors.inkMuted,
        ListingStatus.closed => AppColors.navDark,
        ListingStatus.rejected => AppColors.danger,
      };

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.99,
      child: Container(
        padding: const EdgeInsets.all(12),
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
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 96,
                  height: 84,
                  child: PropertyImage(
                    seed: listing.draft.gradientSeed,
                    url: listing.draft.coverUrl,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    decodeWidth: 96,
                    child: PositionedDirectional(
                      start: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _badgeColor,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          listing.status.badge,
                          style: AppTextStyles.micro(color: Colors.white)
                              .copyWith(fontSize: 9.5, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              listing.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.bodyStrong()
                                  .copyWith(fontSize: 15.5, height: 20 / 15.5),
                            ),
                          ),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: onMenu,
                            child: const Padding(
                              padding: EdgeInsets.only(left: 6, bottom: 6),
                              child: Icon(Icons.more_vert_rounded,
                                  size: 20, color: AppColors.inkMuted),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        listing.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.caption(),
                      ),
                      if (listing.statusLine.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            if (listing.verified) ...[
                              const Icon(Icons.verified_outlined,
                                  size: 14, color: AppColors.success),
                              const SizedBox(width: 4),
                            ],
                            Flexible(
                              child: Text(
                                listing.statusLine,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.caption(
                                        color: AppColors.success)
                                    .copyWith(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (listing.status == ListingStatus.draft) ...[
                        const SizedBox(height: 10),
                        Pressable(
                          onTap: onContinue,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 9),
                            decoration: BoxDecoration(
                              border: Border.all(color: AppColors.primary),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text('Continue editing',
                                style: AppTextStyles.bodyStrong(
                                        color: AppColors.primary)
                                    .copyWith(fontSize: 14)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (listing.hasMetrics) ...[
              const SizedBox(height: 12),
              const Divider(height: 1, color: AppColors.line),
              const SizedBox(height: 10),
              Row(
                children: [
                  _Metric(
                    icon: Icons.visibility_outlined,
                    value: formatCountish(listing.views),
                    label: 'views',
                  ),
                  const SizedBox(width: 16),
                  _Metric(
                    icon: Icons.chat_bubble_outline_rounded,
                    value: '${listing.enquiries}',
                    label: 'chats',
                  ),
                  const SizedBox(width: 16),
                  _Metric(
                    icon: Icons.favorite_border_rounded,
                    value: '${listing.saves}',
                    label: 'saves',
                  ),
                  const Spacer(),
                  if (listing.status == ListingStatus.live)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onBoost,
                      child: Row(
                        children: [
                          Text('Boost',
                              style: AppTextStyles.bodyStrong(
                                      color: AppColors.primary)
                                  .copyWith(fontSize: 14.5)),
                          const SizedBox(width: 2),
                          const Icon(Icons.north_east_rounded,
                              size: 14, color: AppColors.primary),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _Metric({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: AppColors.inkMuted),
        const SizedBox(width: 5),
        Text(value,
            style: AppTextStyles.bodyStrong().copyWith(fontSize: 13.5)),
        const SizedBox(width: 3),
        Text(label,
            style: AppTextStyles.caption().copyWith(fontSize: 12.5)),
      ],
    );
  }
}

class _PostFab extends StatelessWidget {
  final VoidCallback onTap;
  const _PostFab({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Post a listing',
      child: Pressable(
        onTap: onTap,
        child: Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.45),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(Icons.add_rounded, color: Colors.white, size: 30),
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color tint;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.tint = AppColors.ink,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
        child: Row(
          children: [
            Icon(icon, size: 21, color: tint),
            const SizedBox(width: 16),
            Text(label,
                style: AppTextStyles.bodyStrong(color: tint)
                    .copyWith(fontSize: 16)),
          ],
        ),
      ),
    );
  }
}

class _ListingRowSkeleton extends StatelessWidget {
  const _ListingRowSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(width: 96, height: 84, radius: AppRadius.sm),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(height: 14, width: 180),
                SizedBox(height: 10),
                SkeletonBox(height: 12, width: 140),
                SizedBox(height: 10),
                SkeletonBox(height: 12, width: 110),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "1,284" / "12.4k" — thousands grouped up to five digits, then compacted.
///
/// The header tile is narrow; a six-digit grouped number wraps and the design
/// shows it compacted. Uses the existing formatters rather than a third one.
String formatCountish(int value) =>
    value >= 100000 ? formatCount(value) : formatThousands(value);

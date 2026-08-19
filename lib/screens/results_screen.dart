import 'package:flutter/material.dart';

import '../models/property.dart';
import '../models/search_query.dart';
import '../state/app_scope.dart';
import '../state/listings_controller.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/home_nav_bar.dart';
import '../widgets/listing_card.dart';
import '../widgets/state_views.dart';
import 'coming_soon_screen.dart';
import 'filters_sheet.dart';
import 'no_results_screen.dart';
import 'property_detail_screen.dart';
import 'sort_sheet.dart';

/// Screen 10. Everything on it is now derived from the controller's query —
/// the result count, the chips, the sort label and the filter badge were all
/// hardcoded before.
class ResultsScreen extends StatefulWidget {
  final SearchQuery initialQuery;

  const ResultsScreen({super.key, this.initialQuery = const SearchQuery()});

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  late final ListingsController _controller;
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller = ListingsController(
      AppScope.repositoryOf(context),
      initialQuery: widget.initialQuery,
    );
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _controller.load());
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final remaining = _scroll.position.maxScrollExtent - _scroll.position.pixels;
    if (remaining < 600) _controller.loadMore();
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<SearchQuery>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FiltersSheet(query: _controller.query),
    );
    if (result != null) _controller.applyQuery(result);
  }

  Future<void> _openSort() async {
    final result = await showModalBottomSheet<SortOption>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => SortSheet(selected: _controller.query.sort),
    );
    if (result != null) _controller.setSort(result);
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
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final query = _controller.query;
          return Column(
            children: [
              _Header(
                query: query,
                onBack: () => Navigator.of(context).maybePop(),
                onFilters: _openFilters,
                onSort: _openSort,
              ),
              Expanded(
                child: _controller.state.when(
                  loading: () => ListView(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                    children: const [
                      SkeletonBox(height: 18, width: 200),
                      SizedBox(height: 18),
                      ResultCardSkeleton(),
                      ResultCardSkeleton(),
                    ],
                  ),
                  error: (_) => ErrorStateView(onRetry: _controller.load),
                  data: (items) {
                    if (items.isEmpty) {
                      return NoResultsView(
                        query: query,
                        onEditFilters: _openFilters,
                        onSaveSearch: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Search saved — we'll alert you."),
                            ),
                          );
                        },
                      );
                    }
                    return _buildList(items);
                  },
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: HomeNavBar(
        current: NavTab.search,
        onTap: (tab) => Navigator.of(context).pop(tab),
        onPost: () => openPostListingFlow(context),
      ),
    );
  }

  Widget _buildList(List<Property> items) {
    final query = _controller.query;
    return ListView.builder(
      controller: _scroll,
      padding: EdgeInsets.fromLTRB(
        16,
        18,
        16,
        HomeNavBar.reservedSpace(context) + 16,
      ),
      // One extra row for the header, one for the footer.
      itemCount: items.length + 2,
      cacheExtent: 800,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      style: AppTextStyles.body(color: AppColors.ink),
                      children: [
                        TextSpan(
                          text: '${formatThousands(_controller.total)} '
                              '${_controller.total == 1 ? "home" : "homes"} ',
                          style: AppTextStyles.h2(),
                        ),
                        if (query.community != null)
                          TextSpan(text: 'in ${query.community}'),
                      ],
                    ),
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _openSort,
                  child: Row(
                    children: [
                      Text(
                        query.sort.label,
                        style:
                            AppTextStyles.bodyStrong(color: AppColors.primary),
                      ),
                      const Icon(Icons.expand_more_rounded,
                          color: AppColors.primary),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        if (index == items.length + 1) {
          if (_controller.loadingMore) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                ),
              ),
            );
          }
          if (!_controller.hasMore) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text("That's everything",
                    style: AppTextStyles.caption()),
              ),
            );
          }
          return const SizedBox(height: 40);
        }

        final property = items[index - 1];
        return ResultListingCard(
          key: ValueKey(property.id),
          property: property,
          index: index,
          total: _controller.total,
          onTap: () => _openDetail(property),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  final SearchQuery query;
  final VoidCallback onBack;
  final VoidCallback onFilters;
  final VoidCallback onSort;

  const _Header({
    required this.query,
    required this.onBack,
    required this.onFilters,
    required this.onSort,
  });

  @override
  Widget build(BuildContext context) {
    final chips = query.activeChips;
    return Container(
      color: AppColors.navDark,
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top + 8,
        bottom: chips.isEmpty ? 12 : 16,
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _CircleBtn(icon: Icons.arrow_back_rounded, onTap: onBack),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Properties ${query.purpose.label}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              AppTextStyles.bodyStrong(color: Colors.white),
                        ),
                        Text(
                          _subtitle(query),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.caption(color: Colors.white60),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _CircleBtn(
                  icon: Icons.tune_rounded,
                  badge: query.activeFilterCount,
                  onTap: onFilters,
                ),
                const SizedBox(width: 10),
                _CircleBtn(icon: Icons.swap_vert_rounded, onTap: onSort),
              ],
            ),
          ),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 14),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: chips.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, i) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(chips[i],
                      style: AppTextStyles.bodyStrong(color: Colors.white)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _subtitle(SearchQuery query) {
    final parts = <String>[
      if (query.community != null) query.community!,
      if (query.term.isNotEmpty && query.community == null) query.term,
      if (query.beds != null) '${query.beds} Beds',
      if (query.buaMin != null || query.buaMax != null)
        '${query.buaMin ?? 0}–${query.buaMax ?? "any"} sqft',
    ];
    return parts.isEmpty ? 'All areas' : parts.join(' · ');
  }
}

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final int badge;

  const _CircleBtn({
    required this.icon,
    required this.onTap,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          if (badge > 0)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                ),
                constraints:
                    const BoxConstraints(minWidth: 18, minHeight: 18),
                child: Text(
                  '$badge',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.micro(color: Colors.white)
                      .copyWith(fontSize: 10, fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

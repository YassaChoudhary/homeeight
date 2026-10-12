import 'package:flutter/material.dart';

import '../core/async_value.dart';
import '../models/geo.dart';
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
import 'results_map_view.dart';
import 'sort_sheet.dart';

/// Screen 10. Everything on it is now derived from the controller's query —
/// the result count, the chips, the sort label and the filter badge were all
/// hardcoded before.
class ResultsScreen extends StatefulWidget {
  final SearchQuery initialQuery;

  /// Open on the map instead of the list (e.g. after "Search on the map").
  final bool initialMapMode;

  const ResultsScreen({
    super.key,
    this.initialQuery = const SearchQuery(),
    this.initialMapMode = false,
  });

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  late final ListingsController _controller;
  final ScrollController _scroll = ScrollController();

  /// List or map. The query (and its results) is shared by both.
  late bool _mapMode = widget.initialMapMode;

  /// Listing to centre the map on (a card's Map button).
  String? _focusId;

  /// Last results, kept while a new search loads so the map doesn't empty
  /// out under the user's finger.
  List<Property> _lastItems = const [];

  /// Every match for the map (up to [_mapLimit]), not just the pages the
  /// list has scrolled through — so all results get a marker.
  static const int _mapLimit = 300;
  List<Property> _mapItems = const [];
  SearchQuery? _mapQuery;
  bool _mapLoading = false;

  /// Fetches the map's pins when the query has changed since last time.
  void _ensureMapPins(SearchQuery query) {
    final key = query.copyWith(page: 1, pageSize: _mapLimit);
    if (key == _mapQuery) return;
    _mapQuery = key;
    _mapLoading = true;
    AppScope.repositoryOf(context).search(key).then((page) {
      if (!mounted || _mapQuery != key) return;
      setState(() {
        _mapItems = page.results;
        _mapLoading = false;
      });
    }).catchError((Object _) {
      if (!mounted || _mapQuery != key) return;
      // Fall back to the list's results.
      setState(() {
        _mapItems = _lastItems;
        _mapLoading = false;
      });
    });
  }

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

  void _showMap({String? focusId}) {
    setState(() {
      _mapMode = true;
      _focusId = focusId;
    });
  }

  void _showList() => setState(() {
        _mapMode = false;
        _focusId = null;
      });

  Widget _buildMap(SearchQuery query) {
    final state = _controller.state;
    if (state is AsyncError<List<Property>> && _lastItems.isEmpty) {
      return ErrorStateView(onRetry: _controller.load);
    }
    final market = AppScope.of(context).appState.market;
    final listLoading = state is AsyncLoading<List<Property>>;
    // Wait for the list's query to settle (it may switch Rent ↔ Sale).
    if (!listLoading) _ensureMapPins(query);
    final fresh = _mapQuery == query.copyWith(page: 1, pageSize: _mapLimit);
    return ResultsMapView(
      items: fresh && !_mapLoading ? _mapItems : _lastItems,
      loading: listLoading || _mapLoading,
      activeArea: query.bounds,
      fallbackCenter: marketCenter(market.code),
      focusId: _focusId,
      onSearchArea: (bounds) =>
          _controller.applyQuery(query.copyWith(bounds: bounds)),
      onClearArea: () =>
          _controller.applyQuery(query.copyWith(clearBounds: true)),
      onOpenDetail: _openDetail,
      // Room for the List/Map toggle under the card.
      bottomInset: 64,
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
          final value = _controller.state.valueOrNull;
          if (value != null) _lastItems = value;
          return Column(
            children: [
              _Header(
                query: query,
                onBack: () => Navigator.of(context).maybePop(),
                onFilters: _openFilters,
                onSort: _openSort,
              ),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: _mapMode
                          ? _buildMap(query)
                          : _buildListBody(query),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 12,
                      child: Center(
                        child: _ViewToggle(
                          mapMode: _mapMode,
                          onList: _showList,
                          onMap: () => _showMap(),
                        ),
                      ),
                    ),
                  ],
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

  Widget _buildListBody(SearchQuery query) {
    return _controller.state.when(
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
        // Clear of the floating List/Map toggle.
        HomeNavBar.reservedSpace(context) + 72,
      ),
      // One extra row for the header, one for the footer.
      itemCount: items.length + 2,
      cacheExtent: 800,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PurposeNotice(
                query: query,
                switchedFrom: _controller.switchedFrom,
                otherTotal: _controller.otherTotal,
                onSwitch: (p) => _controller.setPurpose(p),
              ),
              Padding(
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
                          TextSpan(text: 'in ${query.community}')
                        else if (query.term.trim().isNotEmpty)
                          TextSpan(text: 'for "${query.term.trim()}"'),
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
              ),
            ],
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
          onMapTap: property.hasLocation
              ? () => _showMap(focusId: property.id)
              : null,
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

/// Floating List | Map switch over the results.
class _ViewToggle extends StatelessWidget {
  final bool mapMode;
  final VoidCallback onList;
  final VoidCallback onMap;

  const _ViewToggle({
    required this.mapMode,
    required this.onList,
    required this.onMap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.navDark,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToggleSegment(
            icon: Icons.view_agenda_outlined,
            label: 'List',
            selected: !mapMode,
            onTap: onList,
          ),
          _ToggleSegment(
            icon: Icons.map_outlined,
            label: 'Map',
            selected: mapMode,
            onTap: onMap,
          ),
        ],
      ),
    );
  }
}

class _ToggleSegment extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ToggleSegment({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : Colors.white70;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: selected ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: fg),
            const SizedBox(width: 6),
            Text(label, style: AppTextStyles.bodyStrong(color: fg)),
          ],
        ),
      ),
    );
  }
}

/// Rent ↔ Sale hint above the results:
/// * after an automatic switch: "No homes for rent match "penthouse" —
///   showing homes for sale."
/// * otherwise, when the other purpose also has matches: "Also 3 for sale →".
class _PurposeNotice extends StatelessWidget {
  final SearchQuery query;
  final Purpose? switchedFrom;
  final int otherTotal;
  final ValueChanged<Purpose> onSwitch;

  const _PurposeNotice({
    required this.query,
    required this.switchedFrom,
    required this.otherTotal,
    required this.onSwitch,
  });

  static String _short(Purpose p) => p == Purpose.rent ? 'for rent' : 'for sale';

  @override
  Widget build(BuildContext context) {
    final term = query.term.trim();
    final other = query.purpose == Purpose.rent ? Purpose.sale : Purpose.rent;
    final from = switchedFrom;

    if (from != null) {
      return Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.primaryTint,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded,
                size: 18, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                term.isEmpty
                    ? 'No homes ${_short(from)} — showing homes ${_short(query.purpose)}.'
                    : 'No homes ${_short(from)} match "$term" — showing homes '
                        '${_short(query.purpose)}.',
                style: AppTextStyles.caption(color: AppColors.ink),
              ),
            ),
          ],
        ),
      );
    }

    if (term.isEmpty || otherTotal <= 0) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onSwitch(other),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: AppColors.primaryTint,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            'Also ${formatThousands(otherTotal)} ${_short(other)} →',
            style: AppTextStyles.caption(color: AppColors.primary)
                .copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}

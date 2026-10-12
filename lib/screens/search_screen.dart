import 'dart:async';

import 'package:flutter/material.dart';

import '../models/geo.dart';
import '../models/property.dart';
import '../models/search_query.dart';
import '../state/app_scope.dart';
import '../state/recent_searches.dart';
import '../state/listings_controller.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../widgets/home_nav_bar.dart';
import '../widgets/listing_card.dart';
import '../widgets/state_views.dart';
import 'bua_search_sheet.dart';
import 'filters_sheet.dart';
import 'map/map_area_screen.dart';
import 'property_detail_screen.dart';
import 'results_screen.dart';

class SearchScreen extends StatefulWidget {
  final ValueChanged<NavTab> onNavTap;
  const SearchScreen({super.key, required this.onNavTap});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  late final AsyncController<List<Property>> _deals;
  /// What this user actually searched for on this phone (newest first).
  List<String> _recents = RecentSearches.all;

  final ValueNotifier<List<SearchSuggestion>> _suggestions =
      ValueNotifier<List<SearchSuggestion>>(const []);
  final ValueNotifier<bool> _typing = ValueNotifier<bool>(false);

  Timer? _debounce;
  SearchQuery _query = const SearchQuery();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _deals = AsyncController<List<Property>>(
      () => AppScope.repositoryOf(context).highlights(),
    );
    _controller.addListener(_onTextChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _deals.load();
    });
  }

  /// Debounced so we issue one suggest request per typing pause instead of one
  /// per keystroke — the same shape the real endpoint will want.
  void _onTextChanged() {
    final text = _controller.text;
    _typing.value = text.isNotEmpty;
    _debounce?.cancel();
    if (text.trim().isEmpty) {
      _suggestions.value = const [];
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 280), () async {
      try {
        final results = await AppScope.repositoryOf(context).suggest(text);
        if (mounted) _suggestions.value = results;
      } catch (_) {
        if (mounted) _suggestions.value = const [];
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focus.dispose();
    _suggestions.dispose();
    _typing.dispose();
    _deals.dispose();
    super.dispose();
  }

  void _reloadRecents() {
    if (mounted) setState(() => _recents = RecentSearches.all);
  }

  Future<void> _remember(String term) async {
    await RecentSearches.remember(term);
    _reloadRecents();
  }

  Future<void> _goResults({
    String? term,
    GeoBounds? bounds,
    SearchQuery? query,
    bool mapMode = false,
  }) async {
    _focus.unfocus();
    final text = (term ?? _controller.text).trim();
    if (text.isNotEmpty) await _remember(text);
    if (!mounted) return;
    final base = query ?? _query;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ResultsScreen(
          initialMapMode: mapMode,
          initialQuery: base.copyWith(
            term: text,
            // A typed search replaces any earlier map area / community.
            clearCommunity: text.isNotEmpty,
            clearBounds: text.isNotEmpty && bounds == null,
            bounds: bounds,
            page: 1,
          ),
        ),
      ),
    );
    _reloadRecents();
  }

  /// A listing suggestion opens that home; anything else (place, type)
  /// searches for it.
  void _openSuggestion(SearchSuggestion s) {
    if (s.id.startsWith('l:')) {
      _focus.unfocus();
      _remember(_controller.text);
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PropertyDetailScreen(propertyId: s.id.substring(2)),
        ),
      );
      return;
    }
    _controller.text = s.title;
    _goResults(term: s.title);
  }

  /// Search by built-up area: size range + live count, then results.
  Future<void> _openBua() async {
    _focus.unfocus();
    final result = await BuaSearchSheet.show(context, _query);
    if (result == null || !mounted) return;
    setState(() => _query = result);
    _goResults(term: '', query: result);
  }

  Future<void> _clearRecents() async {
    await RecentSearches.clear();
    _reloadRecents();
  }

  /// Frame an area on the map, then show results inside it.
  Future<void> _pickArea() async {
    _focus.unfocus();
    final market = AppScope.of(context).appState.market;
    final bounds = await Navigator.of(context).push<GeoBounds>(
      MaterialPageRoute(
        builder: (_) => MapAreaScreen(
          fallbackCenter: marketCenter(market.code),
          initialBounds: _query.bounds,
        ),
      ),
    );
    if (bounds == null || !mounted) return;
    _goResults(term: '', bounds: bounds, mapMode: true);
  }

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<SearchQuery>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FiltersSheet(query: _query),
    );
    if (result != null && mounted) {
      setState(() => _query = result);
      _goResults();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ColoredBox(
      color: AppColors.bg,
      child: SafeArea(
        bottom: false,
        child: CustomScrollView(
          keyboardDismissBehavior:
              ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverToBoxAdapter(child: _buildSearchBar()),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_recents.isNotEmpty) ...[
                      Row(
                        children: [
                          Expanded(
                            child: Text('RECENT',
                                style: AppTextStyles.micro()
                                    .copyWith(letterSpacing: 0.6)),
                          ),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _clearRecents,
                            child: Text('Clear',
                                style: AppTextStyles.caption(
                                        color: AppColors.primary)
                                    .copyWith(fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final term in _recents)
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                _controller.text = term;
                                _goResults(term: term);
                              },
                              child: Container(
                                padding: const EdgeInsets.fromLTRB(
                                    14, 10, 10, 10),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryTint
                                      .withValues(alpha: 0.6),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.history_rounded,
                                        size: 16, color: AppColors.inkMuted),
                                    const SizedBox(width: 6),
                                    Text(term,
                                        style: AppTextStyles.bodyStrong(
                                            color: AppColors.ink)),
                                    const SizedBox(width: 4),
                                    GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () async {
                                        await RecentSearches.remove(term);
                                        _reloadRecents();
                                      },
                                      child: const Padding(
                                        padding: EdgeInsets.all(2),
                                        child: Icon(Icons.close_rounded,
                                            size: 15,
                                            color: AppColors.inkMuted),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                    _buildSuggestions(),
                    const SizedBox(height: 20),
                    _ActionCard(
                      icon: Icons.map_outlined,
                      title: 'Search on the map',
                      subtitle: 'Frame the area you want to live in',
                      onTap: _pickArea,
                    ),
                    const SizedBox(height: 12),
                    _ActionCard(
                      icon: Icons.grid_4x4_rounded,
                      title: 'Search by built-up area',
                      subtitle: 'Find homes by size (sqft or sqm)',
                      onTap: _openBua,
                    ),
                    const SizedBox(height: 26),
                    Row(
                      children: [
                        Expanded(
                          child: Text('Best deals for you',
                              style: AppTextStyles.h1()),
                        ),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _goResults(term: ''),
                          child: Text('See all',
                              style: AppTextStyles.bodyStrong(
                                  color: AppColors.primary)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: DealCard.height,
                child: ListenableBuilder(
                  listenable: _deals,
                  builder: (context, _) => _deals.state.when(
                    loading: () => ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.screenPadding),
                      itemCount: 3,
                      separatorBuilder: (_, _) => const SizedBox(width: 14),
                      itemBuilder: (_, _) => const DealCardSkeleton(),
                    ),
                    error: (_) => ErrorStateView(
                      compact: true,
                      message: "Couldn't load deals.",
                      onRetry: _deals.load,
                    ),
                    data: (items) => ListView.separated(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.screenPadding),
                      itemCount: items.length,
                      cacheExtent: 600,
                      separatorBuilder: (_, _) => const SizedBox(width: 14),
                      itemBuilder: (context, i) => DealCard(
                        property: items[i],
                        onTap: () => Navigator.of(context).push(
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
            ),
            SliverToBoxAdapter(
              child: SizedBox(height: HomeNavBar.reservedSpace(context) + 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: ValueListenableBuilder<bool>(
        valueListenable: _typing,
        builder: (context, typing, _) {
          return Row(
            children: [
              Expanded(
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: typing ? AppColors.primary : AppColors.line,
                      width: typing ? 1.6 : 1,
                    ),
                  ),
                  child: TextField(
                    controller: _controller,
                    focusNode: _focus,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _goResults(),
                    style: AppTextStyles.bodyStrong(),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Search here',
                      hintStyle: AppTextStyles.body(color: AppColors.inkMuted),
                      prefixIcon: const Icon(Icons.search_rounded,
                          color: AppColors.inkMuted),
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              if (typing)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    _controller.clear();
                    _focus.unfocus();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text('Cancel',
                        style: AppTextStyles.bodyStrong(color: AppColors.ink)),
                  ),
                )
              else
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _openFilters,
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: AppColors.primary, width: 1.6),
                    ),
                    child: const Icon(Icons.tune_rounded,
                        color: AppColors.primary, size: 20),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSuggestions() {
    return ValueListenableBuilder<List<SearchSuggestion>>(
      valueListenable: _suggestions,
      builder: (context, suggestions, _) {
        if (suggestions.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 22),
            Text('SUGGESTIONS',
                style: AppTextStyles.micro().copyWith(letterSpacing: 0.6)),
            const SizedBox(height: 8),
            for (final s in suggestions)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _openSuggestion(s),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: AppColors.line)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.primaryTint,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                            s.id.startsWith('l:')
                                ? Icons.home_rounded
                                : s.id.startsWith('t:')
                                    ? Icons.apartment_rounded
                                    : Icons.location_on_rounded,
                            color: AppColors.primary,
                            size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.title,
                                style: AppTextStyles.bodyStrong(
                                    color: AppColors.primary)),
                            Text(s.subtitle, style: AppTextStyles.caption()),
                          ],
                        ),
                      ),
                      if (!s.id.startsWith('l:'))
                        Text(
                            '${formatThousands(s.count)} '
                            '${s.count == 1 ? 'home' : 'homes'}',
                            style: AppTextStyles.caption())
                      else
                        const Icon(Icons.chevron_right_rounded,
                            color: AppColors.inkMuted),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.accentTint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.accent, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTextStyles.bodyStrong()),
                  Text(subtitle, style: AppTextStyles.caption()),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.inkMuted),
          ],
        ),
      ),
    );
  }
}

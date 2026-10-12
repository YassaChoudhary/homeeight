import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/async_value.dart';
import '../data/listing_repository.dart';
import '../models/property.dart';
import '../models/search_query.dart';

/// Owns the state of one results surface: the query, the page of results, the
/// loading/error flags and pagination.
///
/// Screens create one of these, render off `state`, and mutate the query
/// through the named methods. No screen calls the repository directly, so when
/// the API arrives the only thing that changes is which repository was injected.
class ListingsController extends ChangeNotifier {
  final ListingRepository _repository;

  ListingsController(this._repository, {SearchQuery initialQuery = const SearchQuery()})
      : _query = initialQuery;

  SearchQuery _query;
  AsyncValue<List<Property>> _state = const AsyncValue.loading();
  int _total = 0;
  int _otherTotal = 0;
  Purpose? _switchedFrom;
  String? _autoSwitchedTerm;
  bool _hasMore = false;
  bool _loadingMore = false;
  int _requestId = 0;
  Timer? _debounce;
  bool _disposed = false;

  SearchQuery get query => _query;
  AsyncValue<List<Property>> get state => _state;
  int get total => _total;

  /// Matches under the other purpose (rent ↔ sale) for the same search.
  int get otherTotal => _otherTotal;

  /// Set when a text search found nothing for the chosen purpose and we
  /// switched to the other one automatically ("No homes for rent — showing
  /// homes for sale"). Cleared by the user's next change.
  Purpose? get switchedFrom => _switchedFrom;
  bool get hasMore => _hasMore;
  bool get loadingMore => _loadingMore;

  /// True when the query returned nothing — the "No homes match" screen.
  bool get isEmpty {
    final v = _state.valueOrNull;
    return v != null && v.isEmpty;
  }

  Future<void> load() async {
    final id = ++_requestId;
    _state = const AsyncValue.loading();
    _safeNotify();
    try {
      final page = await _repository.search(_query.copyWith(page: 1));
      if (_disposed || id != _requestId) return;
      // Nothing for this purpose, but the same words match the other one:
      // switch rather than show "No results".
      if (page.total == 0 &&
          page.otherTotal > 0 &&
          _query.term.trim().isNotEmpty &&
          _query.term != _autoSwitchedTerm) {
        // Once per search term, so picking Rent again by hand sticks.
        _autoSwitchedTerm = _query.term;
        _switchedFrom = _query.purpose;
        _query = _query.copyWith(
          purpose: _query.purpose == Purpose.rent ? Purpose.sale : Purpose.rent,
          page: 1,
        );
        return load();
      }
      _total = page.total;
      _otherTotal = page.otherTotal;
      _hasMore = page.hasMore;
      _state = AsyncValue.data(page.results);
    } catch (e, s) {
      if (_disposed || id != _requestId) return;
      _state = AsyncValue.error(e, s);
    }
    _safeNotify();
  }

  /// Appends the next page. Safe to call repeatedly from a scroll listener.
  Future<void> loadMore() async {
    if (_loadingMore || !_hasMore) return;
    final current = _state.valueOrNull;
    if (current == null) return;

    _loadingMore = true;
    _safeNotify();

    final id = _requestId;
    try {
      final next = await _repository.search(_query.copyWith(page: _query.page + 1));
      if (_disposed || id != _requestId) return;
      _query = _query.copyWith(page: _query.page + 1);
      _total = next.total;
      _hasMore = next.hasMore;
      _state = AsyncValue.data([...current, ...next.results]);
    } catch (_) {
      // Keep what's already on screen; the footer shows a retry.
    } finally {
      _loadingMore = false;
      _safeNotify();
    }
  }

  /// Replaces the query and reloads. Page always resets to 1.
  void applyQuery(SearchQuery next) {
    if (next == _query) return;
    _switchedFrom = null;
    _query = next.copyWith(page: 1);
    load();
  }

  void update(SearchQuery Function(SearchQuery current) transform) {
    applyQuery(transform(_query));
  }

  void setSort(SortOption sort) => update((q) => q.copyWith(sort: sort));

  void setPurpose(Purpose purpose) => update((q) => q.copyWith(purpose: purpose));

  /// Typing in the search field — debounced so we issue one request per pause
  /// rather than one per keystroke.
  void setTerm(String term, {Duration debounce = const Duration(milliseconds: 300)}) {
    _debounce?.cancel();
    _debounce = Timer(debounce, () {
      applyQuery(_query.copyWith(term: term));
    });
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    super.dispose();
  }
}

/// Small helper for one-shot reads (highlights, communities, suggestions,
/// reels) so those widgets get the same loading/error/data branches without
/// each one hand-rolling a FutureBuilder.
class AsyncController<T> extends ChangeNotifier {
  final Future<T> Function() _fetch;
  AsyncValue<T> _state = const AsyncValue.loading();
  int _requestId = 0;
  bool _disposed = false;

  AsyncController(this._fetch);

  AsyncValue<T> get state => _state;

  Future<void> load() async {
    final id = ++_requestId;
    _state = const AsyncValue.loading();
    if (!_disposed) notifyListeners();
    try {
      final value = await _fetch();
      if (_disposed || id != _requestId) return;
      _state = AsyncValue.data(value);
    } catch (e, s) {
      if (_disposed || id != _requestId) return;
      _state = AsyncValue.error(e, s);
    }
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

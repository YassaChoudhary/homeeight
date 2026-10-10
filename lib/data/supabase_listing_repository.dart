import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/async_value.dart';
import '../models/lister_profile.dart';
import '../models/listing_draft.dart';
import '../models/my_listing.dart';
import '../models/property.dart';
import '../models/search_query.dart';
import 'listing_repository.dart';

/// Listings from Supabase (Postgres).
///
/// Every read is one SQL function call (an "RPC") defined in
/// `supabase/migrations/20261011000000_listings.sql`, and each returns JSON in
/// exactly the shape the existing `fromJson` constructors read — so no model
/// or screen changed when this replaced the mock.
///
/// Two connections:
/// * [_public] — always the anon key. Every browse read (search, detail,
///   carousels, communities, autocomplete) uses it, so **browsing works the
///   same whether or not anyone is logged in**, and a login problem can never
///   take the listings down with it.
/// * [_client] — sends the user's **Firebase** ID token (set up in `main.dart`
///   via `accessToken`). Used only for personal data: saved hearts, and the
///   "saved" flag on reels.
/// Row Level Security in the database decides what each caller can see — this
/// class never filters for permission itself.
///
/// ## Still on the mock (next step)
/// The seller side — my listings, drafts, submit, status, delete, boost,
/// stats, performance, price guidance, verification — still goes to
/// [fallback]. It needs photo upload (Storage) first, so it moves over in the
/// next round. `recentSearches` stays local (it's per-device).
class SupabaseListingRepository implements ListingRepository {
  SupabaseListingRepository(
    this._client, {
    required SupabaseClient publicClient,
    required ListingRepository fallback,
    this.market = 'AE',
  })  : _public = publicClient,
        _fallback = fallback;

  /// Carries the signed-in user's Firebase token (or the anon key when signed
  /// out). Personal data only.
  final SupabaseClient _client;

  /// Always anonymous. All public browsing goes through this.
  final SupabaseClient _public;
  final ListingRepository _fallback;

  /// Which market's listings to read. Only UAE is launched.
  final String market;

  static const Duration _timeout = Duration(seconds: 15);

  // ---------------------------------------------------------------------------
  // Buyer side — Supabase
  // ---------------------------------------------------------------------------

  @override
  Future<ListingPage> search(SearchQuery query) async {
    final params = {...query.toQueryParameters(), 'market': market};
    final json = await _rpcMap('search_listings', {'p': params});
    return ListingPage.fromJson(json);
  }

  @override
  Future<Property> propertyById(String id) async {
    final data = await _rpc('listing_by_id', {'p_id': id});
    if (data is! Map) {
      throw const RepositoryException('Listing not found', statusCode: 404);
    }
    return Property.fromJson(_asMap(data));
  }

  @override
  Future<List<Property>> similarTo(String id, {int limit = 6}) async {
    final list =
        await _rpcList('similar_listings', {'p_id': id, 'p_limit': limit});
    return list.map(Property.fromJson).toList(growable: false);
  }

  @override
  Future<List<ComparableListing>> comparables(String id, {int limit = 6}) async {
    final list =
        await _rpcList('comparable_listings', {'p_id': id, 'p_limit': limit});
    return list.map(ComparableListing.fromJson).toList(growable: false);
  }

  @override
  Future<List<Property>> highlights({int limit = 8}) async {
    final list = await _rpcList(
        'highlight_listings', {'p_limit': limit, 'p_market': market});
    return list.map(Property.fromJson).toList(growable: false);
  }

  @override
  Future<List<Community>> popularCommunities({int limit = 4}) async {
    final list = await _rpcList(
        'popular_communities', {'p_limit': limit, 'p_market': market});
    return list.map(Community.fromJson).toList(growable: false);
  }

  @override
  Future<List<SearchSuggestion>> suggest(String term) async {
    if (term.trim().isEmpty) return const [];
    final list =
        await _rpcList('suggest_places', {'p_term': term, 'p_market': market});
    return list.map(SearchSuggestion.fromJson).toList(growable: false);
  }

  @override
  Future<List<Reel>> reels() async {
    // As the user, so each reel's heart shows their own saves; if that fails
    // (signed out, or a login problem) the feed still loads anonymously.
    List<Map<String, dynamic>> list;
    try {
      list = await _rpcList('reels_feed', {'p_limit': 30}, client: _client);
    } on RepositoryException catch (e) {
      debugPrint('Reels as user failed (${e.message}); loading anonymously');
      list = await _rpcList('reels_feed', {'p_limit': 30});
    }
    return list.map(Reel.fromJson).toList(growable: false);
  }

  /// Hearts. Needs a signed-in user — the database fills `user_uid` from the
  /// Firebase token and refuses the write otherwise, which makes
  /// `SavedListingsStore` roll the heart back.
  @override
  Future<bool> toggleSaved(String listingId, {required bool saved}) async {
    await _guard(() async {
      final table = _client.from('saved_listings');
      if (saved) {
        try {
          await table.insert({'listing_id': listingId});
        } on PostgrestException catch (e) {
          if (e.code != '23505') rethrow; // already saved — fine
        }
      } else {
        await table.delete().eq('listing_id', listingId);
      }
    });
    return saved;
  }

  @override
  Future<Set<String>> savedListingIds() async {
    final rows = await _guard(
        () async => await _client.from('saved_listings').select('listing_id'));
    return {
      for (final row in rows)
        if (row['listing_id'] is String) row['listing_id'] as String,
    };
  }

  @override
  Future<List<String>> recentSearches() => _fallback.recentSearches();

  // ---------------------------------------------------------------------------
  // Seller side — still the mock (see class doc)
  // ---------------------------------------------------------------------------

  @override
  Future<ListerStats> listerStats() => _fallback.listerStats();

  @override
  Future<List<MyListing>> myListings() => _fallback.myListings();

  @override
  Future<ListingPerformance> listingPerformance(
    String listingId, {
    PerformanceRange range = PerformanceRange.days30,
  }) =>
      _fallback.listingPerformance(listingId, range: range);

  @override
  Future<FairPrice> priceGuidance(ListingDraft draft) =>
      _fallback.priceGuidance(draft);

  @override
  Future<ListingDraft> saveListingDraft(ListingDraft draft) =>
      _fallback.saveListingDraft(draft);

  @override
  Future<MyListing> submitListing(ListingDraft draft) =>
      _fallback.submitListing(draft);

  @override
  Future<MyListing> updateListingStatus(String id, ListingStatus status) =>
      _fallback.updateListingStatus(id, status);

  @override
  Future<void> deleteListing(String id) => _fallback.deleteListing(id);

  @override
  Future<MyListing> boostListing(String id) => _fallback.boostListing(id);

  @override
  Future<ListerProfile> submitVerification(ListerProfile profile) =>
      _fallback.submitVerification(profile);

  // ---------------------------------------------------------------------------
  // Plumbing
  // ---------------------------------------------------------------------------

  /// Public read by default; pass [client] to read as the signed-in user.
  Future<dynamic> _rpc(String fn, Map<String, dynamic> params,
          {SupabaseClient? client}) =>
      _guard(() async => await (client ?? _public).rpc(fn, params: params));

  Future<Map<String, dynamic>> _rpcMap(
      String fn, Map<String, dynamic> params) async {
    final data = await _rpc(fn, params);
    if (data is! Map) {
      throw RepositoryException('Unexpected response from $fn');
    }
    return _asMap(data);
  }

  Future<List<Map<String, dynamic>>> _rpcList(
      String fn, Map<String, dynamic> params,
      {SupabaseClient? client}) async {
    final data = await _rpc(fn, params, client: client);
    if (data == null) return const [];
    if (data is! List) {
      throw RepositoryException('Unexpected response from $fn');
    }
    return [
      for (final item in data)
        if (item is Map) _asMap(item),
    ];
  }

  static Map<String, dynamic> _asMap(Map<dynamic, dynamic> m) =>
      m is Map<String, dynamic> ? m : Map<String, dynamic>.from(m);

  /// Turns Supabase/network failures into [RepositoryException], which every
  /// screen already renders as its error state with a retry.
  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call().timeout(_timeout);
    } on PostgrestException catch (e) {
      debugPrint('Supabase error ${e.code}: ${e.message} ${e.details ?? ''}');
      throw RepositoryException(
        e.message,
        statusCode: int.tryParse(e.code ?? ''),
      );
    } on TimeoutException {
      throw const RepositoryException('The server took too long to respond');
    } on RepositoryException {
      rethrow;
    } catch (e) {
      // Socket / HTTP client errors. Caught generically rather than via
      // dart:io's SocketException so this file still compiles for web.
      debugPrint('Supabase request failed: $e');
      throw const RepositoryException(
          'Could not reach the server. Check your connection.');
    }
  }
}

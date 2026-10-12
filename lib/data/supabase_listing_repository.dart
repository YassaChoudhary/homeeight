import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/async_value.dart';
import '../models/agent_profile.dart';
import '../models/lister_profile.dart';
import '../models/listing_draft.dart';
import '../models/my_listing.dart';
import '../models/property.dart';
import '../models/search_query.dart';
import '../models/uploaded_doc.dart';
import '../state/recent_searches.dart';
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
/// The seller side (post a listing, my listings, stats, performance,
/// uploads) is real too — see the "Seller side" section. Only
/// `recentSearches` stays on [fallback] (it's per-device).
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
  Future<List<Property>> highlights({
    int limit = 8,
    Purpose? purpose,
    PropertySegment? segment,
  }) async {
    final list = await _rpcList('highlight_listings', {
      'p_limit': limit,
      'p_market': market,
      'p_purpose': purpose?.wire,
      'p_segment': segment?.name,
    });
    return list.map(Property.fromJson).toList(growable: false);
  }

  @override
  Future<List<Community>> popularCommunities({
    int limit = 4,
    Purpose? purpose,
    PropertySegment? segment,
  }) async {
    final list = await _rpcList('popular_communities', {
      'p_limit': limit,
      'p_market': market,
      'p_purpose': purpose?.wire,
      'p_segment': segment?.name,
    });
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
  Future<List<String>> recentSearches() async => RecentSearches.all;

  // ---------------------------------------------------------------------------
  // Seller side — Supabase (functions in 20261013000000_seller_listings.sql)
  //
  // All of these run as the signed-in user ([_client], Firebase token). The
  // database checks ownership and the publish rules itself.
  // ---------------------------------------------------------------------------

  @override
  Future<ListerStats> listerStats() async {
    final data = await _rpc('lister_stats', const {}, client: _client);
    return data is Map ? ListerStats.fromJson(_asMap(data)) : ListerStats.empty;
  }

  @override
  Future<List<MyListing>> myListings() async {
    final list = await _rpcList('my_listings', const {}, client: _client);
    return list.map(MyListing.fromJson).toList(growable: false);
  }

  @override
  Future<ListingPerformance> listingPerformance(
    String listingId, {
    PerformanceRange range = PerformanceRange.days30,
  }) async {
    final data = await _rpc(
      'listing_performance',
      {'p_id': listingId, 'p_days': range.days},
      client: _client,
    );
    if (data is! Map) {
      throw const RepositoryException('No numbers for this listing yet');
    }
    return ListingPerformance.fromJson(listingId, range, _asMap(data));
  }

  /// Null-safe: with fewer than 3 similar live listings the database returns
  /// nothing, and so do we (the details step then says so).
  @override
  Future<FairPrice> priceGuidance(ListingDraft draft) async {
    final data =
        await _rpc('price_guidance', {'p': draft.toJson()}, client: _client);
    if (data is! Map) return FairPrice.unknown;
    return FairPrice.fromJson(_asMap(data));
  }

  @override
  Future<ListingDraft> saveListingDraft(ListingDraft draft) async {
    final saved = await _sellerCall('save_listing', {'p': draft.toJson()});
    return _keepLocalState(draft, saved.draft);
  }

  @override
  Future<MyListing> submitListing(ListingDraft draft,
      {ListerSummary? lister}) async {
    final body = draft.toJson();
    if (lister != null) body['lister'] = lister.toJson();
    final listing = await _sellerCall('submit_listing', {'p': body});
    return listing.copyWith(draft: _keepLocalState(draft, listing.draft));
  }

  @override
  Future<MyListing> updateListingStatus(String id, ListingStatus status) {
    final wire = switch (status) {
      ListingStatus.closed => 'closed',
      ListingStatus.live => 'live',
      ListingStatus.draft => 'draft',
      _ => throw const RepositoryException("That status can't be set here"),
    };
    return _sellerCall('set_my_listing_status', {'p_id': id, 'p_status': wire});
  }

  @override
  Future<void> deleteListing(String id) async {
    final data =
        await _rpc('delete_my_listing', {'p_id': id}, client: _client);
    // The database hands back the files that belonged to the listing.
    final byBucket = <String, List<String>>{};
    if (data is List) {
      for (final f in data) {
        if (f is Map && f['bucket'] is String && f['path'] is String) {
          byBucket.putIfAbsent(f['bucket'] as String, () => []).add(f['path'] as String);
        }
      }
    }
    for (final kind in ListingFileKind.values) {
      final paths = byBucket[kind.bucket];
      if (paths != null) await deleteListingFiles(kind, paths);
    }
  }

  /// Boost is paid and payments aren't live: this records the request.
  @override
  Future<MyListing> boostListing(String id) =>
      _sellerCall('request_boost', {'p_id': id});

  @override
  Future<ListerProfile> submitVerification(ListerProfile profile) async {
    final data = await _rpc(
      'submit_verification',
      {
        'p': {
          'type': profile.type.name,
          'legal_name': profile.legalName,
          'organisation': profile.organisation,
          'licence_number': profile.licenceNumber,
          'trade_licence': profile.tradeLicence?.toJson(),
          'broker_card': profile.brokerCard?.toJson(),
          'id_front': profile.idFront?.toJson(),
          'id_back': profile.idBack?.toJson(),
        },
      },
      client: _client,
    );
    final status = data is Map
        ? VerificationStatus.parse(data['status'] as String?)
        : VerificationStatus.pending;
    return profile.copyWith(status: status, reviewNote: '');
  }

  @override
  Future<void> updatePublicProfile({String? name, String? avatarUrl}) async {
    await _rpc(
      'update_my_public_profile',
      {'p_name': name, 'p_avatar_url': avatarUrl},
      client: _client,
    );
  }

  @override
  Future<AgentProfile?> agentProfile(String agentId) async {
    final data =
        await _rpc('agent_profile', {'p_agent_id': agentId}, client: _client);
    if (data is! Map) return null;
    return AgentProfile.fromJson(_asMap(data));
  }

  @override
  Future<ListerProfile?> myVerification() async {
    final data = await _rpc('my_verification', const {}, client: _client);
    if (data is! Map || data['status'] == null || data['status'] == 'none') {
      return null;
    }
    final j = _asMap(data);
    return ListerProfile(
      type: ListerType.parse(j['type'] as String?) ?? ListerType.individual,
      status: VerificationStatus.parse(j['status'] as String?),
      legalName: j['legal_name'] as String? ?? '',
      organisation: j['organisation'] as String? ?? '',
      licenceNumber: j['licence_number'] as String? ?? '',
      reviewNote: j['review_note'] as String? ?? '',
      submittedAt: DateTime.tryParse(j['submitted_at'] as String? ?? '')
          ?.toLocal(),
    );
  }

  // --- Files ------------------------------------------------------------------

  @override
  Future<UploadedDoc> uploadListingFile({
    required ListingFileKind kind,
    required Uint8List bytes,
    required String fileName,
    String? contentType,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw const RepositoryException('Please sign in again to upload.',
          statusCode: 401);
    }
    final ext = _extensionOf(fileName);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final folder = kind == ListingFileKind.privateDoc ? 'docs' : 'listings';
    final path = '$uid/$folder/$stamp-${_random.nextInt(1 << 32)}$ext';
    final bucket = _client.storage.from(kind.bucket);

    try {
      await bucket
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              contentType: contentType ?? _mimeFor(ext),
              upsert: false,
              cacheControl: '31536000',
            ),
          )
          .timeout(const Duration(minutes: 3));
    } on StorageException catch (e) {
      debugPrint('Upload failed ${e.statusCode}: ${e.message}');
      final tooBig = e.statusCode == '413' ||
          e.message.toLowerCase().contains('exceeded') ||
          e.message.toLowerCase().contains('too large');
      throw RepositoryException(
        tooBig
            ? 'That file is too big.'
            : "Couldn't upload. Check your connection and try again.",
      );
    } on TimeoutException {
      throw const RepositoryException('The upload took too long. Try again.');
    } catch (e) {
      debugPrint('Upload failed: $e');
      throw const RepositoryException(
          "Couldn't upload. Check your connection and try again.");
    }

    return UploadedDoc(
      name: fileName,
      bytes: bytes.length,
      storagePath: path,
      remoteUrl: kind == ListingFileKind.privateDoc
          ? null
          : bucket.getPublicUrl(path),
    );
  }

  @override
  Future<void> deleteListingFiles(
      ListingFileKind kind, List<String> paths) async {
    final clean = paths.where((p) => p.isNotEmpty).toList();
    if (clean.isEmpty) return;
    try {
      await _client.storage.from(kind.bucket).remove(clean);
    } catch (e) {
      debugPrint('Removing files failed (left in Storage): $e');
    }
  }

  // --- Buyer activity → seller numbers -----------------------------------------

  @override
  Future<void> recordListingEvent(String listingId, ListingEvent event) async {
    try {
      final device = await _deviceId();
      // As the user when signed in, so the owner's own visits don't count.
      await _client.rpc('record_listing_event', params: {
        'p_id': listingId,
        'p_kind': event.name,
        'p_device': device,
      }).timeout(_timeout);
    } catch (e) {
      debugPrint('recordListingEvent skipped: $e');
    }
  }

  static String? _cachedDeviceId;

  /// A random id per install, so one phone opening a listing ten times in an
  /// hour counts once. Not linked to the person.
  static Future<String> _deviceId() async {
    final cached = _cachedDeviceId;
    if (cached != null) return cached;
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('home8_device_id');
    if (id == null) {
      id = List.generate(16, (_) => _random.nextInt(256))
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      await prefs.setString('home8_device_id', id);
    }
    return _cachedDeviceId = id;
  }

  static final math.Random _random = math.Random.secure();

  static String _extensionOf(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return '';
    final ext = name.substring(dot).toLowerCase();
    return ext.length > 6 ? '' : ext;
  }

  static String _mimeFor(String ext) => switch (ext) {
        '.jpg' || '.jpeg' => 'image/jpeg',
        '.png' => 'image/png',
        '.webp' => 'image/webp',
        '.heic' => 'image/heic',
        '.heif' => 'image/heif',
        '.pdf' => 'application/pdf',
        '.mp4' => 'video/mp4',
        '.mov' => 'video/quicktime',
        '.3gp' => 'video/3gpp',
        '.webm' => 'video/webm',
        '.mkv' => 'video/x-matroska',
        _ => 'application/octet-stream',
      };

  Future<MyListing> _sellerCall(String fn, Map<String, dynamic> params) async {
    final data = await _rpc(fn, params, client: _client);
    if (data is! Map) {
      throw RepositoryException('Unexpected response from $fn');
    }
    return MyListing.fromJson(_asMap(data));
  }

  /// The server copy is the truth, but photos still uploading (or failed)
  /// exist only on this phone — keep them, and keep the chosen cover.
  static ListingDraft _keepLocalState(ListingDraft local, ListingDraft server) {
    final pending = local.photos.where((p) => !p.isUploaded).toList();
    final uploaded = server.photos;
    final coverUrl = local.coverUrl;
    final cover = coverUrl == null
        ? 0
        : uploaded.indexWhere((p) => p.remoteUrl == coverUrl).clamp(0, 1 << 20);
    return server.copyWith(
      photos: [...uploaded, ...pending],
      coverIndex: cover,
    );
  }

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

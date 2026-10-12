import 'dart:math' as math;
import 'dart:typed_data';

import '../core/async_value.dart';
import '../models/agent_profile.dart';
import '../models/lister_profile.dart';
import '../models/listing_draft.dart';
import '../models/my_listing.dart';
import '../models/geo.dart';
import '../models/property.dart';
import '../models/property_category.dart';
import '../models/search_query.dart';
import '../models/uploaded_doc.dart';
import '../state/recent_searches.dart';
import 'listing_repository.dart';

/// In-memory stand-in for the API. It filters, sorts and paginates for real —
/// so the screens exercise the same code paths they will with a live backend,
/// including empty results and latency.
///
/// Delete this class the day `ApiListingRepository` lands; nothing else needs
/// to change.
class MockListingRepository implements ListingRepository {
  /// Simulated round-trip. Set to Duration.zero in widget tests.
  final Duration latency;

  /// Flip to true to exercise the error states end to end.
  final bool failEverything;

  MockListingRepository({
    this.latency = const Duration(milliseconds: 350),
    this.failEverything = false,
  });

  Future<T> _respond<T>(T Function() build) async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    if (failEverything) {
      throw const RepositoryException('Mock repository failure', statusCode: 500);
    }
    return build();
  }

  @override
  Future<ListingPage> search(SearchQuery query) {
    return _respond(() {
      var items = _seed.where((p) => p.purpose == query.purpose).toList();

      if (query.term.trim().isNotEmpty) {
        final t = query.term.toLowerCase();
        items = items
            .where((p) =>
                p.title.toLowerCase().contains(t) ||
                p.area.toLowerCase().contains(t) ||
                p.city.toLowerCase().contains(t))
            .toList();
      }
      if (query.community != null && query.community!.isNotEmpty) {
        final c = query.community!.toLowerCase();
        items = items.where((p) => p.area.toLowerCase().contains(c)).toList();
      }
      if (query.priceMin != null) {
        items = items.where((p) => p.price >= query.priceMin!).toList();
      }
      if (query.priceMax != null) {
        items = items.where((p) => p.price <= query.priceMax!).toList();
      }
      if (query.beds != null) {
        items = items.where((p) => p.beds >= query.beds!).toList();
      }
      if (query.baths != null) {
        items = items.where((p) => p.baths >= query.baths!).toList();
      }
      if (query.buaMin != null) {
        items = items.where((p) => p.sqft >= query.buaMin!).toList();
      }
      if (query.buaMax != null) {
        items = items.where((p) => p.sqft <= query.buaMax!).toList();
      }
      if (query.furnishing != null && query.furnishing != 'Any') {
        items = items
            .where((p) =>
                (p.furnishing ?? '').toLowerCase() ==
                query.furnishing!.toLowerCase())
            .toList();
      }
      if (query.amenities.isNotEmpty) {
        items = items
            .where((p) => query.amenities.every((a) => p.amenities.contains(a)))
            .toList();
      }
      if (query.verifiedOnly) {
        items = items.where((p) => p.verified).toList();
      }
      final bounds = query.bounds;
      if (bounds != null) {
        items = items
            .where((p) =>
                p.hasLocation && bounds.contains(GeoPoint(p.lat!, p.lng!)))
            .toList();
      }

      switch (query.sort) {
        case SortOption.relevance:
          items.sort((a, b) {
            final byBadge = (b.featured ? 1 : 0) - (a.featured ? 1 : 0);
            return byBadge != 0 ? byBadge : b.rating.compareTo(a.rating);
          });
        case SortOption.newest:
          items = items.reversed.toList();
        case SortOption.priceAsc:
          items.sort((a, b) => a.price.compareTo(b.price));
        case SortOption.priceDesc:
          items.sort((a, b) => b.price.compareTo(a.price));
        case SortOption.pricePerSqft:
          items.sort((a, b) => a.pricePerSqft.compareTo(b.pricePerSqft));
        case SortOption.buaDesc:
          items.sort((a, b) => b.sqft.compareTo(a.sqft));
      }

      final total = items.length;
      final start = math.min((query.page - 1) * query.pageSize, total);
      final end = math.min(start + query.pageSize, total);
      return ListingPage(
        results: items.sublist(start, end),
        total: total,
        page: query.page,
        hasMore: end < total,
      );
    });
  }

  @override
  Future<Property> propertyById(String id) {
    return _respond(() {
      final match = _seed.where((p) => p.id == id);
      if (match.isEmpty) {
        throw const RepositoryException('Listing not found', statusCode: 404);
      }
      return match.first;
    });
  }

  @override
  Future<List<Property>> similarTo(String id, {int limit = 6}) {
    return _respond(
        () => _seed.where((p) => p.id != id).take(limit).toList(growable: false));
  }

  @override
  Future<List<ComparableListing>> comparables(String id, {int limit = 6}) {
    return _respond(
        () => _comparables.take(limit).toList(growable: false));
  }

  @override
  Future<List<Property>> highlights({
    int limit = 8,
    Purpose? purpose,
    PropertySegment? segment,
  }) {
    return _respond(() => _seed
        .where((p) => _matches(p, purpose, segment))
        .take(limit)
        .toList(growable: false));
  }

  /// The mock's Property has no segment field, so commercial-ness comes from
  /// the type: office, retail, warehouse… are the commercial category wires.
  static bool _isCommercial(Property p) =>
      PropertyCategory.commercial.any((c) => c.wire == p.type);

  static bool _matches(Property p, Purpose? purpose, PropertySegment? segment) {
    if (purpose != null && p.purpose != purpose) return false;
    if (segment != null &&
        _isCommercial(p) != (segment == PropertySegment.commercial)) {
      return false;
    }
    return true;
  }

  @override
  Future<List<Community>> popularCommunities({
    int limit = 4,
    Purpose? purpose,
    PropertySegment? segment,
  }) {
    return _respond(() {
      if (purpose == null && segment == null) {
        return _communities.take(limit).toList(growable: false);
      }
      // Same shape as the Supabase version: rank by homes of this purpose.
      final ranked = [
        for (final c in _communities)
          Community(
            id: c.id,
            name: c.name,
            homes: _seed
                .where((p) => _matches(p, purpose, segment) && p.area == c.name)
                .length,
            photoUrl: c.photoUrl,
            gradientSeed: c.gradientSeed,
          ),
      ]
        // Same rule as the database: with a filter on, hide "0 homes" tiles.
        ..removeWhere((c) => c.homes == 0)
        ..sort((a, b) => b.homes.compareTo(a.homes));
      return ranked.take(limit).toList(growable: false);
    });
  }

  @override
  Future<List<SearchSuggestion>> suggest(String term) {
    return _respond(() {
      if (term.trim().isEmpty) return const <SearchSuggestion>[];
      final t = term.toLowerCase();
      return _suggestions
          .where((s) => s.title.toLowerCase().contains(t))
          .toList(growable: false);
    });
  }

  @override
  Future<List<String>> recentSearches() {
    return _respond(() => RecentSearches.all);
  }

  @override
  Future<List<Reel>> reels() => _respond(() => _reels);

  @override
  Future<bool> toggleSaved(String listingId, {required bool saved}) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    return saved;
  }

  /// The mock keeps no server-side saves; the hearts live in memory only.
  @override
  Future<Set<String>> savedListingIds() async => const <String>{};

  // ---------------------------------------------------------------------
  // Seller side
  //
  // Unlike the buyer methods, these mutate. `_myListings` is instance state
  // rather than a const seed so submitting a listing actually makes it appear
  // on My Listings — the whole post flow is untestable if the last step is a
  // no-op that returns to an unchanged list.
  // ---------------------------------------------------------------------

  List<MyListing>? _myListingsCache;
  int _idCounter = 100;

  List<MyListing> get _listings => _myListingsCache ??= _seedListings();

  @override
  Future<ListerStats> listerStats() {
    return _respond(() {
      final live = _listings.where((l) => l.status == ListingStatus.live);
      return ListerStats(
        saved: 12,
        // Derived rather than hardcoded, so the "4" beside My listings can
        // never disagree with the number of rows on the next screen.
        listings: _listings.length,
        viewings: live.fold(0, (sum, l) => sum + (l.enquiries ~/ 7)),
        rating: 4.9,
        trustScore: 92,
        idVerified: true,
      );
    });
  }

  @override
  Future<List<MyListing>> myListings() =>
      _respond(() => List<MyListing>.unmodifiable(_listings));

  @override
  Future<ListingPerformance> listingPerformance(
    String listingId, {
    PerformanceRange range = PerformanceRange.days30,
  }) {
    return _respond(() {
      final listing = _listings.where((l) => l.id == listingId);
      if (listing.isEmpty) {
        throw const RepositoryException('Listing not found', statusCode: 404);
      }
      final total = listing.first.views;
      return ListingPerformance(
        listingId: listingId,
        range: range,
        series: _series(total, range),
        totalViews: total,
        enquiries: listing.first.enquiries,
        saves: listing.first.saves,
        viewsChangePct: switch (range) {
          PerformanceRange.days30 => 18,
          PerformanceRange.days7 => 6.5,
          PerformanceRange.hours24 => -2,
        },
        conversionPct:
            total == 0 ? 0 : (listing.first.enquiries / total) * 100,
        savesRank: 'top 10% in area',
        boostPrice: 'AED 99',
      );
    });
  }

  /// A rising curve that ends at [total] views.
  ///
  /// Deterministic on purpose — a chart that reshuffles every time you switch
  /// tabs and come back reads as broken data, not as a demo.
  List<PerformancePoint> _series(int total, PerformanceRange range) {
    final labels = switch (range) {
      PerformanceRange.days30 => const [
          '17 Jun', '24 Jun', '1 Jul', '8 Jul', '15 Jul',
        ],
      PerformanceRange.days7 => const [
          'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
        ],
      PerformanceRange.hours24 => const [
          '00:00', '06:00', '12:00', '18:00', '23:00',
        ],
    };
    final n = labels.length;
    // Weights sum to roughly 1 and lean later, which is the shape the design
    // shows: slow start, steady climb.
    final weights = [for (var i = 0; i < n; i++) 0.6 + (i / (n - 1)) * 0.8];
    final sum = weights.reduce((a, b) => a + b);
    return [
      for (var i = 0; i < n; i++)
        PerformancePoint(labels[i], (total * weights[i] / sum).round()),
    ];
  }

  @override
  Future<FairPrice> priceGuidance(ListingDraft draft) {
    return _respond(() {
      final price = draft.price ?? 0;
      final sqft = draft.bua ?? 0;
      if (price == 0 || sqft == 0) return FairPrice.unknown;

      // Stand-in for the real model: a per-sqft rate scaled by bedrooms and
      // furnishing. The point is that the band moves when the user changes a
      // field, so the live feedback under the price box is exercised for real.
      final base = draft.purpose == Purpose.rent ? 88.0 : 1450.0;
      final furnishBump = draft.furnishing == 'Furnished' ? 1.06 : 1.0;
      final bedBump = 1 + (draft.beds - 2) * 0.03;
      final centre = sqft * base * furnishBump * bedBump;

      final fairLow = (centre * 0.92).round();
      final fairHigh = (centre * 1.08).round();
      final bandLow = (centre * 0.80).round();
      final bandHigh = (centre * 1.24).round();

      final verdict = price < fairLow
          ? PriceVerdict.low
          : price > fairHigh
              ? PriceVerdict.high
              : PriceVerdict.fair;

      final span = (bandHigh - bandLow).clamp(1, 1 << 30);
      return FairPrice(
        verdict: verdict,
        position: ((price - bandLow) / span).clamp(0.0, 1.0),
        comparableCount: 6,
        bandLow: bandLow,
        fairLow: fairLow,
        fairHigh: fairHigh,
        bandHigh: bandHigh,
      );
    });
  }

  @override
  Future<ListingDraft> saveListingDraft(ListingDraft draft) {
    return _respond(() {
      final id = draft.id ?? 'l${_idCounter++}';
      final saved = draft.copyWith(id: id);
      final index = _listings.indexWhere((l) => l.id == id);
      if (index >= 0) {
        _listings[index] = _listings[index].copyWith(draft: saved);
      } else {
        _listings.insert(
          0,
          MyListing(id: id, draft: saved, status: ListingStatus.draft),
        );
      }
      return saved;
    });
  }

  @override
  Future<MyListing> submitListing(ListingDraft draft, {ListerSummary? lister}) {
    return _respond(() {
      final id = draft.id ?? 'l${_idCounter++}';
      // Never goes straight to live: permit and photo checks are server-side,
      // and a flow that publishes instantly would teach the wrong expectation.
      final listing = MyListing(
        id: id,
        draft: draft.copyWith(id: id),
        status: ListingStatus.inReview,
        reference: '71-${4400 + _listings.length}',
        submittedAgo: 'just now',
        reviewProgress: 0.15,
        reviewStage: 'Permit check',
      );
      final index = _listings.indexWhere((l) => l.id == id);
      if (index >= 0) {
        _listings[index] = listing;
      } else {
        _listings.insert(0, listing);
      }
      return listing;
    });
  }

  @override
  Future<MyListing> updateListingStatus(String id, ListingStatus status) {
    return _respond(() {
      final index = _listings.indexWhere((l) => l.id == id);
      if (index < 0) {
        throw const RepositoryException('Listing not found', statusCode: 404);
      }
      final updated = _listings[index].copyWith(status: status);
      _listings[index] = updated;
      return updated;
    });
  }

  @override
  Future<void> deleteListing(String id) {
    // Returns a bool rather than nothing so `_respond`'s type parameter has a
    // concrete type to bind to. Future<bool> satisfies Future<void>.
    return _respond<bool>(() {
      _listings.removeWhere((l) => l.id == id);
      return true;
    });
  }

  @override
  Future<MyListing> boostListing(String id) {
    return _respond(() {
      final index = _listings.indexWhere((l) => l.id == id);
      if (index < 0) {
        throw const RepositoryException('Listing not found', statusCode: 404);
      }
      // A boost buys placement, so views jump. Nothing else about the listing
      // changes — the payment sheet that would sit in front of this doesn't
      // exist yet.
      final boosted = _listings[index]
          .copyWith(views: (_listings[index].views * 1.4).round());
      _listings[index] = boosted;
      return boosted;
    });
  }

  /// Demo mode only (no Supabase key): nothing leaves the phone, so the file
  /// gets a placeholder address. Run with env.json for real uploads.
  @override
  Future<UploadedDoc> uploadListingFile({
    required ListingFileKind kind,
    required Uint8List bytes,
    required String fileName,
    String? contentType,
  }) {
    return _respond(() {
      final path = 'demo/${DateTime.now().microsecondsSinceEpoch}-$fileName';
      return UploadedDoc(
        name: fileName,
        bytes: bytes.length,
        storagePath: path,
        remoteUrl: kind == ListingFileKind.privateDoc ? null : 'mock://$path',
      );
    });
  }

  @override
  Future<void> deleteListingFiles(ListingFileKind kind, List<String> paths) async {}

  @override
  Future<void> recordListingEvent(String listingId, ListingEvent event) async {}

  /// Demo mode: nothing on a server, so the account counts as approved.
  @override
  Future<void> updatePublicProfile({String? name, String? avatarUrl}) async {}

  @override
  Future<AgentProfile?> agentProfile(String agentId) async {
    final page = await search(const SearchQuery(pageSize: 6));
    final a = Agent.placeholder;
    return AgentProfile(
      id: agentId,
      name: a.name,
      agency: a.agency,
      verified: a.verified,
      kind: 'agent',
      activeCount: page.results.length,
      listings: page.results,
    );
  }

  @override
  Future<ListerProfile?> myVerification() => _respond(() => const ListerProfile(
        type: ListerType.individual,
        status: VerificationStatus.verified,
      ));

  @override
  Future<ListerProfile> submitVerification(ListerProfile profile) {
    return _respond(
      () => profile.copyWith(status: VerificationStatus.pending),
    );
  }

  /// The four rows on screen 31 — one live, one in review, one draft, plus a
  /// closed one so the row menu's "mark rented" has somewhere to land.
  List<MyListing> _seedListings() => [
        MyListing(
          id: 'l1',
          status: ListingStatus.live,
          reference: '71-4402',
          verified: true,
          expiresInDays: 24,
          views: 812,
          enquiries: 31,
          saves: 96,
          draft: const ListingDraft(
            id: 'l1',
            title: 'Bright 2BR, sea view — Palm Jumeirah',
            propertyType: 'apartment',
            city: 'Dubai',
            community: 'Palm Jumeirah',
            address: 'East Crescent, Palm Jumeirah, Dubai',
            beds: 2,
            baths: 2,
            bua: 1050,
            price: 96000,
            furnishing: 'Furnished',
            photos: [
              DraftPhoto(id: 'ph1', seed: 0),
              DraftPhoto(id: 'ph2', seed: 3),
              DraftPhoto(id: 'ph3', seed: 5),
            ],
            idFront: UploadedDoc(name: 'id-front.jpg'),
            idBack: UploadedDoc(name: 'id-back.jpg'),
            selfie: UploadedDoc(name: 'selfie.jpg'),
          ),
        ),
        MyListing(
          id: 'l2',
          status: ListingStatus.inReview,
          submittedAgo: 'submitted 1 h ago',
          reviewProgress: 0.42,
          reviewStage: 'Permit check',
          draft: const ListingDraft(
            id: 'l2',
            title: '2BR in Al Nahda 1',
            propertyType: 'apartment',
            city: 'Dubai',
            community: 'Al Nahda 1',
            address: 'Al Nawras Building, Al Nahda 1, Dubai',
            beds: 2,
            baths: 2,
            bua: 980,
            price: 68000,
            furnishing: 'Unfurnished',
            photos: [
              DraftPhoto(id: 'ph4', seed: 1),
              DraftPhoto(id: 'ph5', seed: 4),
            ],
            idFront: UploadedDoc(name: 'id-front.jpg'),
            idBack: UploadedDoc(name: 'id-back.jpg'),
          ),
        ),
        MyListing(
          id: 'l3',
          status: ListingStatus.draft,
          draft: const ListingDraft(
            id: 'l3',
            title: 'Studio — Marina walk',
            propertyType: 'studio',
            city: 'Dubai',
            community: 'Dubai Marina',
            address: 'Marina Walk, Dubai Marina, Dubai',
            beds: 1,
            baths: 1,
            bua: 520,
          ),
        ),
        MyListing(
          id: 'l4',
          status: ListingStatus.closed,
          reference: '71-4318',
          verified: true,
          views: 2140,
          enquiries: 58,
          saves: 143,
          draft: const ListingDraft(
            id: 'l4',
            title: '3BR townhouse — JVC',
            propertyType: 'villa',
            city: 'Dubai',
            community: 'JVC',
            address: 'District 12, JVC, Dubai',
            beds: 3,
            baths: 3,
            bua: 1820,
            price: 135000,
            furnishing: 'Unfurnished',
            photos: [
              DraftPhoto(id: 'ph6', seed: 2),
              DraftPhoto(id: 'ph7', seed: 6),
            ],
            idFront: UploadedDoc(name: 'id-front.jpg'),
            idBack: UploadedDoc(name: 'id-back.jpg'),
            selfie: UploadedDoc(name: 'selfie.jpg'),
          ),
        ),
      ];

  // ---------------------------------------------------------------------
  // Seed data
  // ---------------------------------------------------------------------

  static const _description =
      "Bright, fully-furnished residence with a private beach club, dedicated "
      "parking and full sea views from every room. Chiller-free, one cheque "
      "accepted, available immediately for a qualified tenant.";

  /// Comparables behind the Fair Price verdict (screen 19).
  static const List<ComparableListing> _comparables = [
    ComparableListing(
      id: 'c1',
      title: 'Shoreline 9',
      beds: 2,
      sqft: 1060,
      price: 92000,
      recency: 'rented 3 wks ago',
      gradientSeed: 3,
    ),
    ComparableListing(
      id: 'c2',
      title: 'Golden Mile 4',
      beds: 2,
      sqft: 1080,
      price: 99500,
      recency: 'rented 1 mo ago',
      gradientSeed: 1,
    ),
    ComparableListing(
      id: 'c3',
      title: 'Al Nabat',
      beds: 2,
      sqft: 1020,
      price: 104000,
      recency: 'listed now',
      gradientSeed: 5,
    ),
  ];

  static const _agentSara = Agent(
    id: 'ag_1',
    name: 'Sara Ahmed',
    agency: 'Prime Realty',
    verified: true,
    responseTime: '~10 min',
  );

  static const List<Property> _seed = [
    Property(
      id: 'p1',
      lat: 25.0805,
      lng: 55.1403,
      title: 'Home in Palm Jumeirah',
      area: 'Dubai Marina',
      city: 'Dubai',
      purpose: Purpose.rent,
      type: 'apartment',
      beds: 2,
      baths: 2,
      sqft: 1050,
      occupancy: 4,
      furnishing: 'Furnished',
      ageYears: 3,
      price: 96000,
      currency: 'AED',
      period: RentPeriod.yearly,
      rating: 4.96,
      reviews: 217,
      verified: true,
      guestFavourite: true,
      listedByOwner: true,
      permitNo: '71-4402',
      gradientSeed: 0,
      amenities: [
        'Wifi',
        '65" HD TV',
        'Central A/C & Heating',
        'Covered Parking',
        'CCTV Security',
        'Shared Pool',
        'Sea View',
        'Private Gym',
        'Maintenance Staff',
      ],
      description: _description,
      addressLine: 'Al Nawras Building, Al Nahda 1, Al Nahda (Dubai), Dubai',
      agent: Agent.placeholder,
      fairPrice: FairPrice(
        verdict: PriceVerdict.fair,
        position: 0.5,
        comparableCount: 6,
        bandLow: 78000,
        fairLow: 88000,
        fairHigh: 104000,
        bandHigh: 120000,
      ),
    ),
    Property(
      id: 'p2',
      lat: 25.1972,
      lng: 55.2744,
      title: 'Condo in Downtown',
      area: 'Downtown',
      city: 'Dubai',
      purpose: Purpose.rent,
      type: 'apartment',
      beds: 3,
      baths: 2,
      sqft: 1420,
      occupancy: 6,
      furnishing: 'Furnished',
      ageYears: 2,
      price: 142000,
      currency: 'AED',
      period: RentPeriod.yearly,
      rating: 4.88,
      reviews: 96,
      verified: true,
      guestFavourite: true,
      gradientSeed: 1,
      amenities: ['Wifi', 'Covered Parking', 'Shared Pool', 'Private Gym'],
      description: _description,
      addressLine: 'Burj Views, Downtown Dubai, Dubai',
      agent: _agentSara,
      fairPrice: FairPrice(
          verdict: PriceVerdict.low, position: 0.24, comparableCount: 11),
    ),
    Property(
      id: 'p3',
      lat: 25.059,
      lng: 55.209,
      title: 'Villa in JVC',
      area: 'JVC',
      city: 'Dubai',
      purpose: Purpose.rent,
      type: 'villa',
      beds: 2,
      baths: 2,
      sqft: 1180,
      occupancy: 5,
      furnishing: 'Unfurnished',
      ageYears: 5,
      price: 118000,
      currency: 'AED',
      period: RentPeriod.yearly,
      rating: 4.79,
      reviews: 54,
      verified: true,
      featured: true,
      permitNo: '71-9911',
      gradientSeed: 2,
      amenities: ['Covered Parking', 'Shared Pool', "Maid's Room"],
      description: _description,
      addressLine: 'District 12, Jumeirah Village Circle, Dubai',
      agent: _agentSara,
      fairPrice: FairPrice(
          verdict: PriceVerdict.high, position: 0.78, comparableCount: 4),
    ),
    Property(
      id: 'p4',
      lat: 25.1125,
      lng: 55.139,
      title: 'Condo in Shoreline',
      area: 'Shoreline',
      city: 'Dubai',
      purpose: Purpose.rent,
      type: 'apartment',
      beds: 2,
      baths: 2,
      sqft: 1420,
      furnishing: 'Furnished',
      ageYears: 4,
      price: 134000,
      currency: 'AED',
      period: RentPeriod.yearly,
      rating: 4.72,
      reviews: 33,
      verified: true,
      gradientSeed: 3,
      amenities: ['Wifi', 'Sea View', 'Covered Parking'],
      description: _description,
      addressLine: 'Shoreline Apartments, Palm Jumeirah, Dubai',
      agent: Agent.placeholder,
      fairPrice: FairPrice(verdict: PriceVerdict.fair, position: 0.55),
    ),
    Property(
      id: 'p5',
      lat: 25.086,
      lng: 55.147,
      title: 'Marina Gate 2BR',
      area: 'Dubai Marina',
      city: 'Dubai',
      purpose: Purpose.rent,
      type: 'apartment',
      beds: 2,
      baths: 2,
      sqft: 1180,
      furnishing: 'Unfurnished',
      ageYears: 1,
      price: 118000,
      currency: 'AED',
      period: RentPeriod.yearly,
      rating: 4.81,
      reviews: 61,
      verified: true,
      gradientSeed: 4,
      amenities: ['Private Gym', 'Shared Pool', 'Covered Parking'],
      description: _description,
      addressLine: 'Marina Gate 1, Dubai Marina, Dubai',
      agent: _agentSara,
      fairPrice: FairPrice(verdict: PriceVerdict.fair, position: 0.46),
    ),
    Property(
      id: 'p6',
      lat: 25.079,
      lng: 55.121,
      title: 'Penthouse in Bluewaters',
      area: 'Bluewaters',
      city: 'Dubai',
      purpose: Purpose.sale,
      type: 'penthouse',
      beds: 4,
      baths: 5,
      sqft: 3860,
      furnishing: 'Furnished',
      ageYears: 2,
      price: 12500000,
      currency: 'AED',
      rating: 4.91,
      reviews: 12,
      verified: true,
      featured: true,
      permitNo: '71-2044',
      gradientSeed: 5,
      amenities: ['Sea View', 'Private Gym', "Maid's Room", 'Covered Parking'],
      description: _description,
      addressLine: 'Bluewaters Residences, Bluewaters Island, Dubai',
      agent: _agentSara,
      fairPrice: FairPrice(verdict: PriceVerdict.fair, position: 0.6),
    ),
    Property(
      id: 'p7',
      lat: 25.186,
      lng: 55.265,
      title: 'Studio in Business Bay',
      area: 'Business Bay',
      city: 'Dubai',
      purpose: Purpose.sale,
      type: 'studio',
      beds: 1,
      baths: 1,
      sqft: 480,
      furnishing: 'Unfurnished',
      ageYears: 6,
      price: 850000,
      currency: 'AED',
      rating: 4.4,
      reviews: 28,
      gradientSeed: 6,
      amenities: ['Covered Parking', 'Shared Pool'],
      description: _description,
      addressLine: 'Executive Towers, Business Bay, Dubai',
      agent: Agent.placeholder,
      fairPrice: FairPrice(verdict: PriceVerdict.low, position: 0.2),
    ),
  ];

  static const List<Community> _communities = [
    Community(id: 'c1', name: 'Dubai Marina', homes: 1204, gradientSeed: 0),
    Community(id: 'c2', name: 'Palm Jumeirah', homes: 486, gradientSeed: 1),
    Community(id: 'c3', name: 'JVC', homes: 932, gradientSeed: 2),
    Community(id: 'c4', name: 'Downtown', homes: 758, gradientSeed: 3),
  ];

  static const List<SearchSuggestion> _suggestions = [
    SearchSuggestion(
        id: 's1',
        title: 'Dubai Marina',
        subtitle: 'Community · Dubai',
        count: 1204),
    SearchSuggestion(
        id: 's2',
        title: 'Marina Gate Tower',
        subtitle: 'Tower · Dubai Marina',
        count: 86),
    SearchSuggestion(
        id: 's3',
        title: 'Marina Promenade',
        subtitle: 'Tower · Dubai Marina',
        count: 52),
    SearchSuggestion(
        id: 's4', title: 'Downtown', subtitle: 'Community · Dubai', count: 758),
    SearchSuggestion(
        id: 's5', title: 'JVC', subtitle: 'Community · Dubai', count: 932),
  ];

  static const List<Reel> _reels = [
    Reel(
        id: 'r1',
        propertyId: 'p1',
        agency: _agentSara,
        gradientSeed: 7,
        likes: 5000,
        comments: 6000),
    Reel(
        id: 'r2',
        propertyId: 'p2',
        agency: Agent.placeholder,
        gradientSeed: 2,
        likes: 3200,
        comments: 2400),
    Reel(
        id: 'r3',
        propertyId: 'p3',
        agency: _agentSara,
        gradientSeed: 5,
        likes: 8100,
        comments: 4000),
    Reel(
        id: 'r4',
        propertyId: 'p5',
        agency: Agent.placeholder,
        gradientSeed: 0,
        likes: 1900,
        comments: 900),
    Reel(
        id: 'r5',
        propertyId: 'p6',
        agency: _agentSara,
        gradientSeed: 3,
        likes: 6000,
        comments: 3300),
  ];
}

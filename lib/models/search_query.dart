import 'package:flutter/foundation.dart';
import 'geo.dart';
import 'property.dart';
import 'property_category.dart';

enum PropertySegment { residential, commercial }

/// Everything the Filters sheet, Sort sheet and search bar can express, in one
/// immutable object.
///
/// This is deliberately the same vocabulary as `GET /search` in the blueprint
/// (Appendix C.1). The filters UI mutates a copy of this and nothing else; the
/// repository turns it into query params. Adding a backend filter later means
/// adding a field here, not touching screen code.
@immutable
class SearchQuery {
  final String term;
  final Purpose purpose;
  final PropertySegment segment;
  final String? propertyType;
  final String? community;

  final int? priceMin;
  final int? priceMax;
  final int? beds;
  final int? baths;
  final int? buaMin;
  final int? buaMax;
  final String? furnishing;
  final Set<String> amenities;
  final bool verifiedOnly;
  final SortOption sort;

  // Off-plan only.
  final String? offPlanPurpose;
  final String? projectCompletion;
  final String? prehandoverPayment;
  final String? handoverYear;
  final String? projectStatus;
  final String? developer;

  /// Only listings inside this rectangle — set by "Search this area" on the
  /// results map, or an area picked on the map from Search / Filters.
  final GeoBounds? bounds;

  final int page;
  final int pageSize;

  const SearchQuery({
    this.term = '',
    this.purpose = Purpose.rent,
    this.segment = PropertySegment.residential,
    this.propertyType,
    this.community,
    this.priceMin,
    this.priceMax,
    this.beds,
    this.baths,
    this.buaMin,
    this.buaMax,
    this.furnishing,
    this.amenities = const {},
    this.verifiedOnly = false,
    this.sort = SortOption.relevance,
    this.offPlanPurpose,
    this.projectCompletion,
    this.prehandoverPayment,
    this.handoverYear,
    this.projectStatus,
    this.developer,
    this.bounds,
    this.page = 1,
    this.pageSize = 20,
  });

  SearchQuery copyWith({
    String? term,
    Purpose? purpose,
    PropertySegment? segment,
    String? propertyType,
    String? community,
    int? priceMin,
    int? priceMax,
    int? beds,
    int? baths,
    int? buaMin,
    int? buaMax,
    String? furnishing,
    Set<String>? amenities,
    bool? verifiedOnly,
    SortOption? sort,
    String? offPlanPurpose,
    String? projectCompletion,
    String? prehandoverPayment,
    String? handoverYear,
    String? projectStatus,
    String? developer,
    GeoBounds? bounds,
    bool clearBounds = false,
    int? page,
    int? pageSize,
    bool clearBeds = false,
    bool clearBaths = false,
    // copyWith can't distinguish "leave alone" from "set to null", so clearing
    // a nullable field needs an explicit flag. Needed by the Filters sheet when
    // switching property nature invalidates the selected type.
    bool clearPropertyType = false,
    bool clearPrice = false,
    bool clearBua = false,
    bool clearCommunity = false,
    bool clearFurnishing = false,
  }) {
    return SearchQuery(
      term: term ?? this.term,
      purpose: purpose ?? this.purpose,
      segment: segment ?? this.segment,
      propertyType:
          clearPropertyType ? null : (propertyType ?? this.propertyType),
      community: clearCommunity ? null : (community ?? this.community),
      priceMin: clearPrice ? priceMin : (priceMin ?? this.priceMin),
      priceMax: clearPrice ? priceMax : (priceMax ?? this.priceMax),
      beds: clearBeds ? null : (beds ?? this.beds),
      baths: clearBaths ? null : (baths ?? this.baths),
      buaMin: clearBua ? buaMin : (buaMin ?? this.buaMin),
      buaMax: clearBua ? buaMax : (buaMax ?? this.buaMax),
      furnishing: clearFurnishing ? null : (furnishing ?? this.furnishing),
      amenities: amenities ?? this.amenities,
      verifiedOnly: verifiedOnly ?? this.verifiedOnly,
      sort: sort ?? this.sort,
      offPlanPurpose: offPlanPurpose ?? this.offPlanPurpose,
      projectCompletion: projectCompletion ?? this.projectCompletion,
      prehandoverPayment: prehandoverPayment ?? this.prehandoverPayment,
      handoverYear: handoverYear ?? this.handoverYear,
      projectStatus: projectStatus ?? this.projectStatus,
      developer: developer ?? this.developer,
      bounds: clearBounds ? null : (bounds ?? this.bounds),
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
    );
  }

  bool get isOffPlan => propertyType == 'Off-Plan Homes';

  /// Chips shown under the results header — derived, never stored separately.
  List<String> get activeChips {
    final chips = <String>[purpose.label];
    // Display name, not the wire value — a chip reading "bed_space" is a leak.
    final typeTitle = PropertyCategory.titleForWire(propertyType);
    if (typeTitle != null) chips.add(typeTitle);
    if (priceMin != null || priceMax != null) {
      String k(int v) => v >= 1000000
          ? '${(v / 1000000).toStringAsFixed(v % 1000000 == 0 ? 0 : 1)}M'
          : v >= 1000
              ? '${(v / 1000).round()}k'
              : '$v';
      if (priceMin != null && priceMax != null) {
        chips.add('${k(priceMin!)}–${k(priceMax!)}');
      } else if (priceMin != null) {
        chips.add('From ${k(priceMin!)}');
      } else {
        chips.add('Up to ${k(priceMax!)}');
      }
    }
    if (beds != null) chips.add('$beds Beds');
    if (baths != null) chips.add('$baths Baths');
    if (buaMin != null || buaMax != null) {
      chips.add(buaMin != null && buaMax != null
          ? '${formatThousands(buaMin!)}–${formatThousands(buaMax!)} sqft'
          : buaMin != null
              ? '${formatThousands(buaMin!)}+ sqft'
              : 'Up to ${formatThousands(buaMax!)} sqft');
    }
    if (furnishing != null && furnishing != 'Any') chips.add(furnishing!);
    for (final a in amenities) {
      chips.add(a);
    }
    if (verifiedOnly) chips.add('Verified');
    if (bounds != null) chips.add('Map area');
    return chips;
  }

  /// Number of user-applied filters, for the badge on the filter button.
  int get activeFilterCount {
    var n = 0;
    if (priceMin != null || priceMax != null) n++;
    if (beds != null) n++;
    if (baths != null) n++;
    if (buaMin != null || buaMax != null) n++;
    if (furnishing != null && furnishing != 'Any') n++;
    n += amenities.length;
    if (verifiedOnly) n++;
    if (propertyType != null) n++;
    if (bounds != null) n++;
    return n;
  }

  /// Query-string form. The API repository sends this straight to `/search`.
  Map<String, String> toQueryParameters() {
    final map = <String, String>{
      'purpose': purpose.wire,
      'segment': segment.name,
      'sort': sort.wire,
      'page': '$page',
      'page_size': '$pageSize',
    };
    void put(String key, Object? value) {
      if (value != null && '$value'.isNotEmpty) map[key] = '$value';
    }

    put('q', term);
    put('type', propertyType);
    put('area', community);
    put('price_min', priceMin);
    put('price_max', priceMax);
    put('beds', beds);
    put('baths', baths);
    put('bua_min', buaMin);
    put('bua_max', buaMax);
    put('furnishing', furnishing);
    if (amenities.isNotEmpty) map['amenities'] = amenities.join(',');
    if (verifiedOnly) map['verified'] = 'true';
    put('offplan_purpose', offPlanPurpose);
    put('project_completion', projectCompletion);
    put('prehandover_payment', prehandoverPayment);
    put('handover', handoverYear);
    put('project_status', projectStatus);
    put('developer', developer);
    final b = bounds;
    if (b != null) {
      map['min_lat'] = b.minLat.toStringAsFixed(6);
      map['max_lat'] = b.maxLat.toStringAsFixed(6);
      map['min_lng'] = b.minLng.toStringAsFixed(6);
      map['max_lng'] = b.maxLng.toStringAsFixed(6);
    }
    return map;
  }

  @override
  bool operator ==(Object other) =>
      other is SearchQuery &&
      other.term == term &&
      other.purpose == purpose &&
      other.segment == segment &&
      other.propertyType == propertyType &&
      other.community == community &&
      other.priceMin == priceMin &&
      other.priceMax == priceMax &&
      other.beds == beds &&
      other.baths == baths &&
      other.buaMin == buaMin &&
      other.buaMax == buaMax &&
      other.furnishing == furnishing &&
      setEquals(other.amenities, amenities) &&
      other.verifiedOnly == verifiedOnly &&
      other.sort == sort &&
      other.bounds == bounds &&
      other.page == page;

  @override
  int get hashCode => Object.hash(
        term,
        purpose,
        segment,
        propertyType,
        community,
        priceMin,
        priceMax,
        beds,
        baths,
        buaMin,
        buaMax,
        furnishing,
        Object.hashAllUnordered(amenities),
        verifiedOnly,
        sort,
        bounds,
        page,
      );
}

enum SortOption {
  relevance('The most relevant', 'relevance'),
  newest('Newest first', 'newest'),
  priceAsc('Price: low to high', 'price_asc'),
  priceDesc('Price: high to low', 'price_desc'),
  pricePerSqft('Price per sqft', 'price_per_sqft_asc'),
  buaDesc('Biggest area (BUA)', 'bua_desc');

  final String label;
  final String wire;
  const SortOption(this.label, this.wire);
}

/// One page of results plus the facet data the header renders.
@immutable
class ListingPage {
  final List<Property> results;
  final int total;
  final int page;
  final bool hasMore;

  /// Same search under the other purpose (rent ↔ sale). Lets the results
  /// screen switch instead of showing "No results".
  final int otherTotal;

  const ListingPage({
    required this.results,
    required this.total,
    this.page = 1,
    this.hasMore = false,
    this.otherTotal = 0,
  });

  factory ListingPage.fromJson(Map<String, dynamic> json) {
    final results = (json['results'] as List? ?? const [])
        .map((e) => Property.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
    final total = json['total'] as int? ?? results.length;
    final page = json['page'] as int? ?? 1;
    final pageSize = json['page_size'] as int? ?? results.length;
    return ListingPage(
      results: results,
      total: total,
      page: page,
      hasMore: page * pageSize < total,
      otherTotal: (json['other_total'] as num?)?.toInt() ?? 0,
    );
  }

  static const ListingPage empty = ListingPage(results: [], total: 0);
}

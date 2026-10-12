import 'package:flutter/material.dart';

import 'geo.dart';

enum Purpose { rent, sale }

enum RentPeriod { yearly, monthly, weekly, nightly }

enum PriceVerdict { low, fair, high }

extension PurposeX on Purpose {
  String get wire => name == 'rent' ? 'rent' : 'sale';
  String get label => this == Purpose.rent ? 'For Rent' : 'For Sale';

  static Purpose parse(String? v) =>
      v == 'sale' ? Purpose.sale : Purpose.rent;
}

extension RentPeriodX on RentPeriod {
  String get label => switch (this) {
        RentPeriod.yearly => 'year',
        RentPeriod.monthly => 'month',
        RentPeriod.weekly => 'week',
        RentPeriod.nightly => 'night',
      };

  static RentPeriod? parse(String? v) => switch (v) {
        'yearly' => RentPeriod.yearly,
        'monthly' => RentPeriod.monthly,
        'weekly' => RentPeriod.weekly,
        'nightly' => RentPeriod.nightly,
        _ => null,
      };
}

/// The lister's contact details for one listing.
@immutable
class ListingContact {
  final String? phone;
  final String? whatsapp;
  final String? email;

  const ListingContact({this.phone, this.whatsapp, this.email});

  static const ListingContact none = ListingContact();

  factory ListingContact.fromJson(Map<String, dynamic> json) {
    String? clean(Object? v) {
      final s = (v as String?)?.trim();
      return s == null || s.isEmpty ? null : s;
    }

    return ListingContact(
      phone: clean(json['phone']),
      whatsapp: clean(json['whatsapp']),
      email: clean(json['email']),
    );
  }

  bool get isEmpty => phone == null && whatsapp == null && email == null;
}

/// Seller/agent shown on the listing detail and reel header.
@immutable
class Agent {
  final String id;
  final String name;
  final String agency;
  final String? avatarUrl;
  final bool verified;
  final String responseTime;

  const Agent({
    required this.id,
    required this.name,
    required this.agency,
    this.avatarUrl,
    this.verified = false,
    this.responseTime = '~15 min',
  });

  factory Agent.fromJson(Map<String, dynamic> json) => Agent(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        agency: json['agency_name'] as String? ?? '',
        avatarUrl: json['avatar_url'] as String?,
        verified: json['verified'] as bool? ?? false,
        responseTime: json['response_time'] as String? ?? '~15 min',
      );

  static const Agent placeholder = Agent(
    id: 'ag_0',
    name: 'Tarik Abdullah',
    agency: 'Prime Realty',
    verified: true,
  );
}

/// Home8 fair-price band (blueprint §3.2 / screen 20).
///
/// [bandLow], [fairLow], [fairHigh] and [bandHigh] were added for the Fair
/// Price sheet, which labels the axis with real money rather than just
/// Low/Fair/High. They're nullable so a backend that only returns a verdict and
/// a position still renders — the sheet falls back to the unlabelled gauge.
@immutable
class FairPrice {
  final PriceVerdict verdict;

  /// 0.0 = bottom of the Low band, 1.0 = top of the High band. Drives the
  /// gauge marker, so the backend controls the position rather than the UI.
  final double position;
  final int comparableCount;

  /// Absolute band edges, in the listing's currency.
  final int? bandLow;
  final int? fairLow;
  final int? fairHigh;
  final int? bandHigh;

  const FairPrice({
    required this.verdict,
    required this.position,
    this.comparableCount = 0,
    this.bandLow,
    this.fairLow,
    this.fairHigh,
    this.bandHigh,
  });

  factory FairPrice.fromJson(Map<String, dynamic> json) => FairPrice(
        verdict: switch (json['verdict'] as String?) {
          'low' => PriceVerdict.low,
          'high' => PriceVerdict.high,
          _ => PriceVerdict.fair,
        },
        position: (json['position'] as num?)?.toDouble() ?? 0.5,
        comparableCount: json['comparable_count'] as int? ?? 0,
        bandLow: (json['band_low'] as num?)?.round(),
        fairLow: (json['fair_low'] as num?)?.round(),
        fairHigh: (json['fair_high'] as num?)?.round(),
        bandHigh: (json['band_high'] as num?)?.round(),
      );

  /// False when there is no verdict at all (a new listing with too few
  /// comparable homes) — the detail page then hides the fair-price parts.
  bool get isKnown => !identical(this, FairPrice.unknown) || hasBands;

  /// True when the sheet can label the axis with money.
  bool get hasBands =>
      bandLow != null &&
      fairLow != null &&
      fairHigh != null &&
      bandHigh != null;

  String get verdictLabel => switch (verdict) {
        PriceVerdict.low => 'Good deal',
        PriceVerdict.fair => 'Fair price',
        PriceVerdict.high => 'Above market',
      };

  /// Sentence shown in the tinted callout on the Fair Price sheet.
  String verdictSentence(String currency, int price) => switch (verdict) {
        PriceVerdict.low =>
          'Asking $currency ${formatThousands(price)} — below the fair band '
              'for this area',
        PriceVerdict.fair =>
          'Asking $currency ${formatThousands(price)} — priced fairly for '
              'this area',
        PriceVerdict.high =>
          'Asking $currency ${formatThousands(price)} — above the fair band '
              'for this area',
      };

  static const FairPrice unknown =
      FairPrice(verdict: PriceVerdict.fair, position: 0.5);
}

/// One recently-transacted or currently-listed home used as evidence on the
/// Fair Price sheet, and as the right-hand column on the Compare screen.
@immutable
class ComparableListing {
  final String id;
  final String title;
  final int beds;
  final int sqft;
  final int price;
  final String currency;

  /// Human phrase from the backend — "rented 3 wks ago", "listed now".
  final String recency;
  final String? photoUrl;
  final int gradientSeed;

  const ComparableListing({
    required this.id,
    required this.title,
    required this.beds,
    required this.sqft,
    required this.price,
    this.currency = 'AED',
    this.recency = '',
    this.photoUrl,
    this.gradientSeed = 0,
  });

  factory ComparableListing.fromJson(Map<String, dynamic> json) => ComparableListing(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        beds: json['beds'] as int? ?? 0,
        sqft: json['bua_sqft'] as int? ?? 0,
        price: (json['price'] as num?)?.round() ?? 0,
        currency: json['currency'] as String? ?? 'AED',
        recency: json['recency'] as String? ?? '',
        photoUrl: json['photo_url'] as String?,
        gradientSeed: json['id'].hashCode.abs(),
      );

  String get subtitle =>
      [if (sqft > 0) '${formatThousands(sqft)} sqft', if (recency.isNotEmpty) recency]
          .join(' · ');

  String get label => beds > 0 ? '${beds}BR · $title' : title;
}

@immutable
class Property {
  final String id;
  final String title;
  final String area;
  final String city;
  final Purpose purpose;
  final String type;

  final int beds;
  final int baths;
  final int sqft;
  final int? occupancy;
  final String? furnishing;
  final int? ageYears;

  final int price;
  final String currency;
  final RentPeriod? period;

  final double rating;
  final int reviews;

  final bool verified;
  final bool featured;
  final bool guestFavourite;
  final bool listedByOwner;
  final String? permitNo;

  /// Remote photo URLs. Empty until the backend serves media — the UI falls
  /// back to a deterministic gradient keyed by [gradientSeed].
  final List<String> photos;
  final int gradientSeed;

  final List<String> amenities;
  final String description;
  final String addressLine;

  final Agent agent;
  final FairPrice fairPrice;

  /// Previous asking price, when the listing has been reduced. Drives the
  /// "▼ AED 4,000" badge and the struck-through old price on the Saved screen.
  /// Null means no recorded change — not "no change".
  final int? previousPrice;

  /// False once a listing is rented/sold/withdrawn. Saved cards stay visible
  /// but render dimmed with "No longer available", because silently dropping a
  /// home someone saved is worse than showing it as gone.
  final bool available;

  /// Why it's unavailable — "RENTED", "SOLD". Only meaningful when
  /// [available] is false.
  final String? unavailableReason;

  /// Real coordinates. Never shown to buyers directly — maps use
  /// [mapLocation], which is offset to protect the owner's exact address.
  final double? lat;
  final double? lng;

  /// Walkthrough video, when the lister uploaded one.
  final String? videoUrl;

  /// How buyers reach the lister — the Email / Call / WhatsApp bar.
  final ListingContact contact;

  const Property({
    required this.id,
    required this.title,
    required this.area,
    required this.city,
    required this.purpose,
    required this.type,
    required this.beds,
    required this.baths,
    required this.sqft,
    required this.price,
    required this.currency,
    this.period,
    this.occupancy,
    this.furnishing,
    this.ageYears,
    this.rating = 0,
    this.reviews = 0,
    this.verified = false,
    this.featured = false,
    this.guestFavourite = false,
    this.listedByOwner = false,
    this.permitNo,
    this.photos = const [],
    this.gradientSeed = 0,
    this.amenities = const [],
    this.description = '',
    this.addressLine = '',
    this.agent = Agent.placeholder,
    this.fairPrice = FairPrice.unknown,
    this.previousPrice,
    this.available = true,
    this.unavailableReason,
    this.lat,
    this.lng,
    this.videoUrl,
    this.contact = ListingContact.none,
  });

  bool get hasLocation => lat != null && lng != null;

  /// The buyer-facing map position: near the listing, never exactly on it.
  /// Null when the listing has no coordinates yet.
  GeoPoint? get mapLocation => hasLocation
      ? approximateLocation(id, GeoPoint(lat!, lng!))
      : null;

  /// Matches the search response shape in blueprint Appendix C.1, so the API
  /// repository can hand raw JSON straight in.
  factory Property.fromJson(Map<String, dynamic> json) {
    final badges = (json['badges'] as List?)?.cast<String>() ?? const <String>[];
    return Property(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      area: json['area'] as String? ?? '',
      city: json['city'] as String? ?? '',
      purpose: PurposeX.parse(json['purpose'] as String?),
      type: json['type'] as String? ?? 'apartment',
      beds: json['beds'] as int? ?? 0,
      baths: json['baths'] as int? ?? 0,
      sqft: json['bua_sqft'] as int? ?? 0,
      occupancy: json['occupancy'] as int?,
      furnishing: json['furnishing'] as String?,
      ageYears: json['age_years'] as int?,
      price: (json['price'] as num?)?.round() ?? 0,
      currency: json['currency'] as String? ?? 'AED',
      period: RentPeriodX.parse(json['rent_period'] as String?),
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      reviews: json['reviews'] as int? ?? 0,
      verified: badges.contains('verified'),
      featured: json['featured'] as bool? ?? false,
      guestFavourite: badges.contains('guest_favourite'),
      listedByOwner: badges.contains('owner'),
      permitNo: json['permit_no'] as String?,
      photos: (json['photos'] as List?)?.cast<String>() ??
          [if (json['cover'] != null) json['cover'] as String],
      gradientSeed: json['id'].hashCode.abs(),
      amenities: (json['amenities'] as List?)?.cast<String>() ?? const [],
      description: json['description'] as String? ?? '',
      addressLine: json['address'] as String? ?? '',
      agent: json['agent'] != null
          ? Agent.fromJson(json['agent'] as Map<String, dynamic>)
          : Agent.placeholder,
      fairPrice: json['fair_price'] != null
          ? FairPrice.fromJson(json['fair_price'] as Map<String, dynamic>)
          : FairPrice.unknown,
      previousPrice: (json['previous_price'] as num?)?.round(),
      available: json['available'] as bool? ?? true,
      unavailableReason: json['unavailable_reason'] as String?,
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
      videoUrl: json['video_url'] as String?,
      contact: json['contact'] is Map
          ? ListingContact.fromJson(
              Map<String, dynamic>.from(json['contact'] as Map))
          : ListingContact.none,
    );
  }

  int get pricePerSqft => sqft == 0 ? 0 : (price / sqft).round();

  /// Positive when the price has come down. Negative rises are deliberately
  /// not surfaced as a badge — nobody wants a "price went up" chip on a home
  /// they saved — but the number is available if you want it.
  int get priceDrop {
    final prev = previousPrice;
    if (prev == null) return 0;
    return prev - price;
  }

  bool get hasPriceDrop => priceDrop > 0;

  String get badgeLabel {
    if (guestFavourite) return 'Guest Favourite';
    if (featured) return 'Featured';
    return '';
  }

  String get priceFormatted => formatThousands(price);

  String get specLine =>
      '$beds Bedrooms · $baths Bathrooms · ${formatThousands(sqft)} sqft';
}

String formatThousands(int value) {
  final s = value.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final fromEnd = s.length - i;
    buf.write(s[i]);
    if (fromEnd > 1 && fromEnd % 3 == 1) buf.write(',');
  }
  return buf.toString();
}

@immutable
class Community {
  final String id;
  final String name;
  final int homes;
  final String? photoUrl;
  final int gradientSeed;

  const Community({
    required this.id,
    required this.name,
    required this.homes,
    this.photoUrl,
    this.gradientSeed = 0,
  });

  factory Community.fromJson(Map<String, dynamic> json) => Community(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        homes: json['homes'] as int? ?? 0,
        photoUrl: json['photo_url'] as String?,
        gradientSeed: json['id'].hashCode.abs(),
      );
}

@immutable
class SearchSuggestion {
  final String id;
  final String title;
  final String subtitle;
  final int count;

  const SearchSuggestion({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.count,
  });

  factory SearchSuggestion.fromJson(Map<String, dynamic> json) =>
      SearchSuggestion(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        subtitle: json['subtitle'] as String? ?? '',
        count: json['count'] as int? ?? 0,
      );
}

/// One vertical video/photo card in the Reels feed.
@immutable
class Reel {
  final String id;
  final String propertyId;
  final Agent agency;
  final String? mediaUrl;
  final int gradientSeed;
  final int likes;
  final int comments;
  final bool saved;

  const Reel({
    required this.id,
    required this.propertyId,
    required this.agency,
    this.mediaUrl,
    this.gradientSeed = 0,
    this.likes = 0,
    this.comments = 0,
    this.saved = false,
  });

  factory Reel.fromJson(Map<String, dynamic> json) => Reel(
        id: json['id'] as String,
        propertyId: json['listing_id'] as String? ?? '',
        agency: json['agent'] != null
            ? Agent.fromJson(json['agent'] as Map<String, dynamic>)
            : Agent.placeholder,
        mediaUrl: json['media_url'] as String?,
        gradientSeed: json['id'].hashCode.abs(),
        likes: json['likes'] as int? ?? 0,
        comments: json['comments'] as int? ?? 0,
        saved: json['saved'] as bool? ?? false,
      );
}

/// Compact counts, e.g. 5200 -> "5.2k".
String formatCount(int value) {
  if (value < 1000) return '$value';
  final k = value / 1000;
  final text = k >= 10 ? k.round().toString() : k.toStringAsFixed(1);
  return '${text.endsWith('.0') ? text.substring(0, text.length - 2) : text}k';
}

/// Palette used to render a deterministic gradient stand-in for a photo.
const List<List<Color>> kPhotoGradients = [
  [Color(0xFF0D5C63), Color(0xFF13848D)],
  [Color(0xFF244B54), Color(0xFF3F7C82)],
  [Color(0xFFB5731E), Color(0xFFE07A3C)],
  [Color(0xFF55666E), Color(0xFF1A2B34)],
  [Color(0xFF2C7A54), Color(0xFF0D5C63)],
  [Color(0xFF8A5A34), Color(0xFFE07A3C)],
  [Color(0xFF0D5C63), Color(0xFF55666E)],
  [Color(0xFF083F44), Color(0xFF2C7A54)],
];

import 'package:flutter/foundation.dart';

import 'listing_draft.dart';
import 'property.dart';

/// Where one of the user's own listings sits in its lifecycle.
///
/// These are the seller's view of a listing, which is a different thing from
/// `Property.available` — a buyer only ever sees [live] ones. Keeping the
/// vocabulary separate stops seller states leaking into search results.
enum ListingStatus {
  draft('DRAFT', 'Draft'),
  inReview('IN REVIEW', 'In review'),
  live('LIVE', 'Live'),

  /// Rented, sold or withdrawn. Still visible to the seller for its numbers.
  closed('CLOSED', 'Closed'),

  /// Turned down at review. Distinct from [draft] so the reason can be shown.
  rejected('REJECTED', 'Needs changes');

  /// Uppercase badge on the listing card's photo.
  final String badge;

  /// Sentence-case label for tabs and menus.
  final String label;

  const ListingStatus(this.badge, this.label);

  static ListingStatus parse(String? value) {
    for (final s in ListingStatus.values) {
      if (s.name == value) return s;
    }
    return ListingStatus.draft;
  }
}

/// The tabs across the top of My Listings. [all] is a view, not a status, which
/// is why it isn't part of [ListingStatus].
enum ListingFilter {
  all('All'),
  live('Approved'),
  inReview('In review'),
  rejected('Rejected'),
  draft('Draft');

  final String label;
  const ListingFilter(this.label);

  bool matches(MyListing listing) => switch (this) {
        ListingFilter.all => true,
        ListingFilter.live => listing.status == ListingStatus.live,
        ListingFilter.inReview => listing.status == ListingStatus.inReview,
        ListingFilter.draft => listing.status == ListingStatus.draft,
        ListingFilter.rejected => listing.status == ListingStatus.rejected,
      };
}

/// One row on the My Listings screen.
///
/// Carries its [draft] so "Continue editing" can reopen the post flow exactly
/// where it was left, rather than re-fetching and re-hydrating. For a live
/// listing the draft is still the source of the title, price and photos shown
/// on the row — one shape for both, so the card doesn't need two code paths.
@immutable
class MyListing {
  final String id;
  final ListingDraft draft;
  final ListingStatus status;

  /// Public reference, e.g. "71-4402". Empty until the listing goes live.
  final String reference;

  final bool verified;

  /// Days until the listing expires and needs renewing. Null when it doesn't
  /// expire yet (drafts, listings in review).
  final int? expiresInDays;

  /// Human phrase from the backend — "submitted 1 h ago". Not a DateTime,
  /// because the wording differs by market and the server already renders it
  /// for the web app.
  final String submittedAgo;

  /// How far through review, 0..1. Drives the amber progress bar.
  final double reviewProgress;

  /// What review is currently doing — "Permit check", "Photo check".
  final String reviewStage;

  final int views;
  final int enquiries;
  final int saves;

  /// Why review turned it down ("Photos are blurry"). Empty otherwise.
  final String reviewNote;

  const MyListing({
    required this.id,
    required this.draft,
    required this.status,
    this.reference = '',
    this.verified = false,
    this.expiresInDays,
    this.submittedAgo = '',
    this.reviewProgress = 0,
    this.reviewStage = '',
    this.views = 0,
    this.enquiries = 0,
    this.saves = 0,
    this.reviewNote = '',
  });

  /// From the `my_listings()` / `save_listing()` / `submit_listing()` RPCs.
  factory MyListing.fromJson(Map<String, dynamic> j) => MyListing(
        id: j['id'] as String,
        draft: ListingDraft.fromJson(
            Map<String, dynamic>.from(j['draft'] as Map? ?? const {})),
        status: ListingStatus.parse(j['status'] as String?),
        reference: j['reference'] as String? ?? '',
        verified: j['verified'] as bool? ?? false,
        submittedAgo: j['submitted_ago'] as String? ?? '',
        reviewProgress: (j['review_progress'] as num?)?.toDouble() ?? 0,
        reviewStage: j['review_stage'] as String? ?? '',
        views: (j['views'] as num?)?.toInt() ?? 0,
        enquiries: (j['enquiries'] as num?)?.toInt() ?? 0,
        saves: (j['saves'] as num?)?.toInt() ?? 0,
        reviewNote: j['review_note'] as String? ?? '',
      );

  MyListing copyWith({
    ListingDraft? draft,
    ListingStatus? status,
    String? reference,
    bool? verified,
    int? expiresInDays,
    String? submittedAgo,
    double? reviewProgress,
    String? reviewStage,
    int? views,
    int? enquiries,
    int? saves,
  }) =>
      MyListing(
        id: id,
        draft: draft ?? this.draft,
        status: status ?? this.status,
        reference: reference ?? this.reference,
        verified: verified ?? this.verified,
        expiresInDays: expiresInDays ?? this.expiresInDays,
        submittedAgo: submittedAgo ?? this.submittedAgo,
        reviewProgress: reviewProgress ?? this.reviewProgress,
        reviewStage: reviewStage ?? this.reviewStage,
        views: views ?? this.views,
        enquiries: enquiries ?? this.enquiries,
        saves: saves ?? this.saves,
        reviewNote: reviewNote,
      );

  String get title =>
      draft.title.trim().isEmpty ? 'Untitled listing' : draft.title;

  /// "AED 96,000 / yr · Ref 71-4402" — the row's second line for a live
  /// listing. Drafts show what's missing instead; see [subtitle].
  String get priceLine {
    final price = draft.price;
    if (price == null || price == 0) return 'Price not set';
    final period = draft.purpose == Purpose.rent && draft.period != null
        ? ' / ${_shortPeriod(draft.period!)}'
        : '';
    final ref = reference.isEmpty ? '' : ' · Ref $reference';
    return '${draft.currency} ${formatThousands(price)}$period$ref';
  }

  /// The line under the title, which differs by status: a draft says what it
  /// needs, a listing in review says when it was sent, a live one shows money.
  String get subtitle => switch (status) {
        ListingStatus.draft => draft.missingSummary.isEmpty
            ? 'Ready to submit'
            : 'Missing: ${draft.missingSummary}',
        ListingStatus.inReview => submittedAgo.isEmpty
            ? priceLine
            : '$priceLine · $submittedAgo',
        ListingStatus.rejected =>
          reviewNote.isEmpty ? 'Needs changes' : 'Needs changes: $reviewNote',
        _ => priceLine,
      };

  /// "Verified · expires in 24 days".
  String get statusLine {
    final parts = <String>[
      if (verified) 'Verified',
      if (expiresInDays != null) 'expires in $expiresInDays days',
    ];
    return parts.join(' · ');
  }

  /// Only live listings can be boosted or have their numbers looked at.
  bool get hasMetrics => status == ListingStatus.live ||
      status == ListingStatus.closed;

  static String _shortPeriod(PricePeriod p) => switch (p) {
        PricePeriod.yearly => 'yr',
        PricePeriod.monthly => 'mo',
        PricePeriod.weekly => 'wk',
        PricePeriod.nightly => 'night',
      };
}

/// The four figures in the dark profile header on screen 30.
///
/// [rating] is the seller's own rating from completed deals, not a listing
/// rating — which is why it lives here and not on `Property`.
@immutable
class ListerStats {
  final int saved;
  final int listings;
  final int viewings;
  final double rating;

  /// Server-computed trust score, 0–100. Shown as the "TRUST 92" pill.
  final int? trustScore;

  final bool idVerified;

  const ListerStats({
    this.saved = 0,
    this.listings = 0,
    this.viewings = 0,
    this.rating = 0,
    this.trustScore,
    this.idVerified = false,
  });

  static const ListerStats empty = ListerStats();

  factory ListerStats.fromJson(Map<String, dynamic> j) => ListerStats(
        saved: (j['saved'] as num?)?.toInt() ?? 0,
        listings: (j['listings'] as num?)?.toInt() ?? 0,
        viewings: (j['viewings'] as num?)?.toInt() ?? 0,
        rating: (j['rating'] as num?)?.toDouble() ?? 0,
        trustScore: (j['trust_score'] as num?)?.toInt(),
        idVerified: j['id_verified'] as bool? ?? false,
      );

  String get ratingLabel => rating <= 0 ? '—' : rating.toStringAsFixed(1);
}

/// The three windows on the Performance screen.
enum PerformanceRange {
  days30('30 days', 30),
  days7('7 days', 7),
  hours24('24 h', 1);

  final String label;

  /// Days covered. Used to label the axis and to size the request.
  final int days;

  const PerformanceRange(this.label, this.days);
}

/// One point on the views chart.
@immutable
class PerformancePoint {
  /// Axis label the backend supplies — "17 Jun", "14:00". Rendering dates
  /// client-side would need a locale-aware formatter the app doesn't have yet.
  final String label;
  final int value;

  const PerformancePoint(this.label, this.value);
}

/// Everything the Performance screen renders for one listing over one window.
@immutable
class ListingPerformance {
  final String listingId;
  final PerformanceRange range;
  final List<PerformancePoint> series;

  final int totalViews;
  final int enquiries;
  final int saves;

  /// Percentage change against the previous window of the same length.
  /// Positive is up. Null when there's no previous window to compare against —
  /// a brand-new listing shouldn't claim "▲ 0%".
  final double? viewsChangePct;

  /// Enquiries ÷ views, as a percentage.
  final double conversionPct;

  /// Where the save count sits against comparable listings — "top 10% in area".
  /// Empty when the backend has too few comparables to say.
  final String savesRank;

  /// What a boost costs in this market, e.g. "AED 99". Empty hides the banner
  /// rather than showing a price we made up.
  final String boostPrice;

  const ListingPerformance({
    required this.listingId,
    required this.range,
    required this.series,
    this.totalViews = 0,
    this.enquiries = 0,
    this.saves = 0,
    this.viewsChangePct,
    this.conversionPct = 0,
    this.savesRank = '',
    this.boostPrice = '',
  });

  factory ListingPerformance.fromJson(
    String listingId,
    PerformanceRange range,
    Map<String, dynamic> j,
  ) =>
      ListingPerformance(
        listingId: listingId,
        range: range,
        series: [
          for (final p in (j['series'] as List? ?? const []))
            if (p is Map)
              PerformancePoint(
                p['label'] as String? ?? '',
                (p['value'] as num?)?.toInt() ?? 0,
              ),
        ],
        totalViews: (j['total_views'] as num?)?.toInt() ?? 0,
        enquiries: (j['enquiries'] as num?)?.toInt() ?? 0,
        saves: (j['saves'] as num?)?.toInt() ?? 0,
        viewsChangePct: (j['views_change_pct'] as num?)?.toDouble(),
        conversionPct: (j['conversion_pct'] as num?)?.toDouble() ?? 0,
        savesRank: j['saves_rank'] as String? ?? '',
        boostPrice: j['boost_price'] as String? ?? '',
      );

  /// Highest point, used to scale the chart. Never zero, so the painter can
  /// divide by it without a guard at every call site.
  int get peak =>
      series.isEmpty ? 1 : series.map((p) => p.value).reduce((a, b) => a > b ? a : b).clamp(1, 1 << 30);
}

/// Who is posting — shown on the listing's agent card. Sent with submit.
@immutable
class ListerSummary {
  final String name;

  /// Agency / company name. Empty for an owner.
  final String agency;
  final String? avatarUrl;

  /// 'individual', 'agent' or 'company'.
  final String type;

  const ListerSummary({
    required this.name,
    this.agency = '',
    this.avatarUrl,
    this.type = 'individual',
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'agency': agency,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
        'type': type,
      };
}

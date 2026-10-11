import 'package:flutter/foundation.dart';

import 'property.dart';
import 'search_query.dart';
import 'uploaded_doc.dart';

/// Which numbered step of the post flow a field belongs to.
///
/// The stepper header renders "STEP 2 OF 4" off this, and the Preview screen's
/// "Edit a step" chips jump back to it. [location] is deliberately **not**
/// numbered: it's reached from the Map link on [basics] and edited as part of
/// it, which is why the Figma shows four numbered steps but five edit chips.
enum PostStep {
  basics('Basics', 'What are you listing?'),
  location('Location', 'Where is your property?'),
  details('Details & price', 'Details & price'),
  media('Photos', 'Add photos & media'),
  permit('Permit', 'Verify your listing');

  final String chipLabel;
  final String title;
  const PostStep(this.chipLabel, this.title);

  /// The four steps that carry a number in the header. Location is edited
  /// inside Basics, so it doesn't get a slot in the progress bar.
  static const List<PostStep> numbered = [basics, details, media, permit];

  /// 1-based position for "STEP n OF 4". Location reports its parent's number
  /// because that's the step the user believes they're on.
  int get number => this == location ? 1 : numbered.indexOf(this) + 1;
}

/// One photo attached to a draft.
///
/// [seed] exists because no photography ships with the app: `PropertyImage`
/// renders a deterministic brand gradient from it, so a draft with four photos
/// looks like four distinct photos rather than four identical grey boxes. When
/// a real picker lands, [localPath] is set and the gradient becomes the
/// fallback it was always meant to be.
@immutable
class DraftPhoto {
  final String id;
  final int seed;
  final String? localPath;
  final String? remoteUrl;

  const DraftPhoto({
    required this.id,
    required this.seed,
    this.localPath,
    this.remoteUrl,
  });
}

/// Units the BUA field offers. Both are in play across the markets — the Gulf
/// quotes sqft, Pakistan quotes sqft but thinks in marla, Europe quotes sqm.
enum AreaUnit {
  sqft('sqft'),
  sqm('sqm');

  final String label;
  const AreaUnit(this.label);
}

/// How a rent figure is quoted. Sale listings have no period at all, which is
/// why `ListingDraft.period` is nullable rather than defaulting to yearly.
enum PricePeriod {
  yearly('year'),
  monthly('month'),
  weekly('week'),
  nightly('night');

  final String label;
  const PricePeriod(this.label);

  RentPeriod? get asRentPeriod => switch (this) {
        PricePeriod.yearly => RentPeriod.yearly,
        PricePeriod.monthly => RentPeriod.monthly,
        PricePeriod.weekly => RentPeriod.weekly,
        // The Property model has no nightly period; short stays fall back to
        // weekly for display until it gains one.
        PricePeriod.nightly => RentPeriod.weekly,
      };
}

/// Everything the post flow collects, in one immutable object.
///
/// Same reasoning as `SearchQuery`: the screens mutate a copy through
/// `PostListingController` and nothing else, so adding a field the backend
/// wants means editing this file rather than hunting through seven screens.
///
/// Field names mirror the `POST /listings` body in blueprint §9.3, so
/// [toJson] can go straight over the wire.
@immutable
class ListingDraft {
  /// Server id, once the draft has been saved at least once. Null for a draft
  /// that has only ever lived on this device.
  final String? id;

  // --- Step 1: Basics ------------------------------------------------------
  final Purpose purpose;
  final PropertySegment segment;

  /// Wire value from `PropertyCategory`, e.g. `studio`, `villa`. Null until the
  /// user taps a tile.
  final String? propertyType;

  // --- Location (edited inside Basics) -------------------------------------
  /// Market code — 'AE', 'PK'. Defaults from `AppState.market` when the flow
  /// opens rather than being hardcoded here.
  final String countryCode;
  final String city;

  /// Building and community as one line, e.g. "Al Nawras Building, Al Nahda 1".
  final String address;

  /// Community shown to buyers. The exact pin is withheld until an enquiry is
  /// accepted — see the note on the location screen — so these are two
  /// separate facts, not one.
  final String community;

  final double? latitude;
  final double? longitude;

  // --- Step 2: Details & price --------------------------------------------
  final int beds;
  final int baths;
  final int? bua;
  final AreaUnit areaUnit;
  final int? price;
  final String currency;
  final PricePeriod? period;
  final String? furnishing;
  final String title;
  final String description;

  // --- Step 3: Photos & media ---------------------------------------------
  final List<DraftPhoto> photos;

  /// Index into [photos] of the cover shot. The first photo is the cover by
  /// default; reordering is a later feature.
  final int coverIndex;

  final bool hasVideo;

  /// The paid 360° capture visit, booked from the media step.
  final bool tourBooked;

  // --- Step 4: Permit / verification --------------------------------------
  final UploadedDoc? titleDeed;
  final bool idScanned;
  final bool selfieDone;

  const ListingDraft({
    this.id,
    this.purpose = Purpose.rent,
    this.segment = PropertySegment.residential,
    this.propertyType,
    this.countryCode = 'AE',
    this.city = 'Dubai',
    this.address = '',
    this.community = '',
    this.latitude,
    this.longitude,
    this.beds = 2,
    this.baths = 2,
    this.bua,
    this.areaUnit = AreaUnit.sqft,
    this.price,
    this.currency = 'AED',
    this.period = PricePeriod.yearly,
    this.furnishing,
    this.title = '',
    this.description = '',
    this.photos = const [],
    this.coverIndex = 0,
    this.hasVideo = false,
    this.tourBooked = false,
    this.titleDeed,
    this.idScanned = false,
    this.selfieDone = false,
  });

  ListingDraft copyWith({
    String? id,
    Purpose? purpose,
    PropertySegment? segment,
    String? propertyType,
    String? countryCode,
    String? city,
    String? address,
    String? community,
    double? latitude,
    double? longitude,
    int? beds,
    int? baths,
    int? bua,
    AreaUnit? areaUnit,
    int? price,
    String? currency,
    PricePeriod? period,
    String? furnishing,
    String? title,
    String? description,
    List<DraftPhoto>? photos,
    int? coverIndex,
    bool? hasVideo,
    bool? tourBooked,
    UploadedDoc? titleDeed,
    bool? idScanned,
    bool? selfieDone,
    // copyWith can't tell "leave alone" from "set to null", so clearing a
    // nullable field needs a flag — same pattern as SearchQuery.
    bool clearPropertyType = false,
    bool clearPeriod = false,
    bool clearTitleDeed = false,
    bool clearLocation = false,
  }) =>
      ListingDraft(
        id: id ?? this.id,
        purpose: purpose ?? this.purpose,
        segment: segment ?? this.segment,
        propertyType:
            clearPropertyType ? null : (propertyType ?? this.propertyType),
        countryCode: countryCode ?? this.countryCode,
        city: city ?? this.city,
        address: address ?? this.address,
        community: community ?? this.community,
        latitude: clearLocation ? null : (latitude ?? this.latitude),
        longitude: clearLocation ? null : (longitude ?? this.longitude),
        beds: beds ?? this.beds,
        baths: baths ?? this.baths,
        bua: bua ?? this.bua,
        areaUnit: areaUnit ?? this.areaUnit,
        price: price ?? this.price,
        currency: currency ?? this.currency,
        period: clearPeriod ? null : (period ?? this.period),
        furnishing: furnishing ?? this.furnishing,
        title: title ?? this.title,
        description: description ?? this.description,
        photos: photos ?? this.photos,
        coverIndex: coverIndex ?? this.coverIndex,
        hasVideo: hasVideo ?? this.hasVideo,
        tourBooked: tourBooked ?? this.tourBooked,
        titleDeed: clearTitleDeed ? null : (titleDeed ?? this.titleDeed),
        idScanned: idScanned ?? this.idScanned,
        selfieDone: selfieDone ?? this.selfieDone,
      );

  // --- Completeness --------------------------------------------------------
  //
  // Each step knows what "done" means for it. The stepper uses these to enable
  // its CTA, the Preview screen uses them for "All checks passed", and
  // MyListings uses them for the "Missing: photos, price" line on a draft card.
  // One definition, three consumers — so a draft can never look complete on one
  // screen and incomplete on another.

  bool get basicsComplete => propertyType != null && address.trim().isNotEmpty;

  bool get locationComplete => address.trim().isNotEmpty && city.isNotEmpty;

  bool get detailsComplete =>
      (bua ?? 0) > 0 && (price ?? 0) > 0 && title.trim().isNotEmpty;

  /// Two photos is the floor for a listing that doesn't look abandoned. The
  /// media screen still nudges towards eight, which is where the enquiry
  /// numbers actually improve.
  bool get mediaComplete => photos.length >= 2;

  bool get permitComplete => titleDeed != null && idScanned;

  bool completed(PostStep step) => switch (step) {
        PostStep.basics => basicsComplete,
        PostStep.location => locationComplete,
        PostStep.details => detailsComplete,
        PostStep.media => mediaComplete,
        PostStep.permit => permitComplete,
      };

  /// Ready to publish. Location rides along with basics.
  bool get readyToPublish =>
      basicsComplete && detailsComplete && mediaComplete && permitComplete;

  /// Short human list of what's missing — "photos, price". Drives the draft
  /// card on My Listings, so the user knows what to come back for.
  String get missingSummary {
    final missing = <String>[
      if (propertyType == null) 'type',
      if (address.trim().isEmpty) 'location',
      if ((price ?? 0) <= 0) 'price',
      if ((bua ?? 0) <= 0) 'area',
      if (title.trim().isEmpty) 'title',
      if (!mediaComplete) 'photos',
      if (!permitComplete) 'permit',
    ];
    return missing.join(', ');
  }

  // --- Display -------------------------------------------------------------

  /// "AED 96,000 / year" — the price as the preview card and the submitted
  /// screen show it.
  String get priceLine {
    final p = price;
    if (p == null || p == 0) return 'Price not set';
    final suffix = purpose == Purpose.rent && period != null
        ? ' / ${period!.label}'
        : '';
    return '$currency ${formatThousands(p)}$suffix';
  }

  /// "2 Bed · 2 Bath · 1,050 sqft · Furnished · Al Nahda 1".
  String get specLine => [
        '$beds Bed',
        '$baths Bath',
        if ((bua ?? 0) > 0) '${formatThousands(bua!)} ${areaUnit.label}',
        if (furnishing != null && furnishing!.isNotEmpty) furnishing!,
        if (community.isNotEmpty) community,
      ].join(' · ');

  int get pricePerUnit {
    final p = price ?? 0;
    final a = bua ?? 0;
    if (p == 0 || a == 0) return 0;
    return (p / a).round();
  }

  /// Stable seed for the gradient stand-in, so a draft keeps the same colours
  /// between the media step, the preview and My Listings.
  int get gradientSeed =>
      photos.isNotEmpty ? photos[coverIndex.clamp(0, photos.length - 1)].seed
          : (id ?? title).hashCode.abs();

  /// Body for `POST /listings`. Media is referenced by URL, so this is only
  /// sendable once the photos have been uploaded to Storage.
  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'purpose': purpose.wire,
        'segment': segment.name,
        'type': propertyType,
        'country': countryCode,
        'city': city,
        'address': address,
        'community': community,
        if (latitude != null) 'lat': latitude,
        if (longitude != null) 'lng': longitude,
        'beds': beds,
        'baths': baths,
        'bua': bua,
        'area_unit': areaUnit.label,
        'price': price,
        'currency': currency,
        if (period != null) 'rent_period': period!.name,
        'furnishing': furnishing,
        'title': title,
        'description': description,
        'photos': [
          for (final p in photos)
            if (p.remoteUrl != null) p.remoteUrl,
        ],
        'has_video': hasVideo,
        'tour_booked': tourBooked,
        if (titleDeed != null) 'title_deed': titleDeed!.toJson(),
        'id_scanned': idScanned,
        'selfie_done': selfieDone,
      };
}

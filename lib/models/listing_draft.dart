import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'property.dart';
import 'search_query.dart';
import 'uploaded_doc.dart';

/// The six steps of "Post a listing", in the order the prototype shows them:
/// Basics → Details & price → Photos → Location → Verify → Reels package,
/// then Preview.
enum PostStep {
  basics('Basics', 'What are you listing?'),
  details('Details & price', 'Details & price'),
  media('Photos', 'Add photos & media'),
  location('Location', 'Where is your property?'),
  permit('Permit', 'Verify your listing'),
  reels('Reels', 'Reels Package');

  final String chipLabel;
  final String title;
  const PostStep(this.chipLabel, this.title);

  /// Order of the stepper (and the progress bar).
  static const List<PostStep> numbered = [
    basics,
    details,
    media,
    location,
    permit,
    reels,
  ];

  /// Order of the "Edit a step" chips on Preview, as designed.
  static const List<PostStep> chipOrder = [
    basics,
    location,
    details,
    media,
    permit,
    reels,
  ];

  /// 1-based position for "STEP n OF 6".
  int get number => numbered.indexOf(this) + 1;
}

enum PhotoUploadState { uploading, done, failed }

/// One photo on a draft.
///
/// While it uploads, [bytes] holds the picked (already compressed) image so
/// the tile shows it straight away. Once uploaded, [remoteUrl] is the public
/// Storage URL and [bytes] is dropped.
@immutable
class DraftPhoto {
  final String id;

  /// Fallback gradient while nothing can be shown.
  final int seed;
  final String? remoteUrl;

  /// Path inside the `listing-photos` bucket, for deleting the file.
  final String? storagePath;
  final Uint8List? bytes;
  final PhotoUploadState state;

  const DraftPhoto({
    required this.id,
    required this.seed,
    this.remoteUrl,
    this.storagePath,
    this.bytes,
    this.state = PhotoUploadState.done,
  });

  bool get isUploaded => remoteUrl != null && state == PhotoUploadState.done;

  DraftPhoto copyWith({
    String? remoteUrl,
    String? storagePath,
    PhotoUploadState? state,
    bool dropBytes = false,
  }) =>
      DraftPhoto(
        id: id,
        seed: seed,
        remoteUrl: remoteUrl ?? this.remoteUrl,
        storagePath: storagePath ?? this.storagePath,
        bytes: dropBytes ? null : bytes,
        state: state ?? this.state,
      );

  /// A saved photo coming back from the server.
  factory DraftPhoto.fromUrl(String url, int index) => DraftPhoto(
        id: 'ph_${url.hashCode.abs()}_$index',
        seed: url.hashCode.abs() % 97 + index,
        remoteUrl: url,
        storagePath: storagePathFromUrl(url, 'listing-photos'),
      );
}

/// "…/storage/v1/object/public/listing-photos/uid/x.jpg" → "uid/x.jpg".
String? storagePathFromUrl(String url, String bucket) {
  final marker = '/$bucket/';
  final i = url.indexOf(marker);
  if (i < 0) return null;
  return url.substring(i + marker.length);
}

/// Units the BUA field offers.
enum AreaUnit {
  sqft('sqft'),
  sqm('sqm');

  final String label;
  const AreaUnit(this.label);

  static AreaUnit parse(String? v) => v == 'sqm' ? sqm : sqft;
}

/// How a rent figure is quoted. Sale listings have no period.
enum PricePeriod {
  yearly('year'),
  monthly('month'),
  weekly('week'),
  nightly('night');

  final String label;
  const PricePeriod(this.label);

  RentPeriod get asRentPeriod => switch (this) {
        PricePeriod.yearly => RentPeriod.yearly,
        PricePeriod.monthly => RentPeriod.monthly,
        PricePeriod.weekly => RentPeriod.weekly,
        PricePeriod.nightly => RentPeriod.nightly,
      };

  static PricePeriod? parse(String? v) {
    for (final p in values) {
      if (p.name == v) return p;
    }
    return null;
  }
}

/// Step 6 — the reels package the seller picked (or skipped).
enum ReelsPackage {
  unlimited30d(
    'unlimited_30d',
    'Unlimited — 30 days',
    'Unlimited reels package will allow you to add as many reels you want',
    99,
  ),
  century(
    'century',
    'Century Package',
    '100 reels can be added related to your Property',
    29,
  );

  final String wire;
  final String title;
  final String blurb;

  /// Price in AED, as designed.
  final int priceAed;

  const ReelsPackage(this.wire, this.title, this.blurb, this.priceAed);

  static ReelsPackage? parse(String? v) {
    for (final p in values) {
      if (p.wire == v) return p;
    }
    return null;
  }
}

/// Everything the post flow collects, in one immutable object.
///
/// Field names in [toJson] / [ListingDraft.fromJson] match the database
/// functions `save_listing` / `submit_listing` / `my_listings`.
@immutable
class ListingDraft {
  /// Server id, once saved at least once.
  final String? id;

  // --- Step 1: Basics ------------------------------------------------------
  final Purpose purpose;
  final PropertySegment segment;
  final String? propertyType;

  // --- Step 2: Details & price ---------------------------------------------
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

  /// "What this place offers" on the detail screen.
  final List<String> amenities;

  /// "4 people" in the detail header. Optional.
  final int? occupancy;

  /// "6 years old" on the detail screen. Optional.
  final int? ageYears;

  /// Buyers' Email / Call / WhatsApp buttons on the detail screen.
  final String contactEmail;
  final String contactPhone;
  final String contactWhatsapp;

  // --- Step 3: Photos & media ----------------------------------------------
  final List<DraftPhoto> photos;

  /// Index into [photos] of the cover shot. Saved as the first photo.
  final int coverIndex;

  /// Walkthrough video (uploaded), or null.
  final UploadedDoc? video;

  /// 360° capture visit requested.
  final bool tourBooked;

  // --- Step 4: Location ----------------------------------------------------
  final String countryCode;
  final String city;

  /// Exact address. Private — buyers only see [community] and [city].
  final String address;

  /// Community buyers see ("Dubai Marina").
  final String community;

  /// Exact pin. Private — buyers see a nearby approximate area.
  final double? latitude;
  final double? longitude;

  // --- Step 5: Verify ------------------------------------------------------
  final UploadedDoc? titleDeed;
  final UploadedDoc? idFront;
  final UploadedDoc? idBack;
  final UploadedDoc? selfie;

  /// Permit / advertising number shown on the listing ("Permit #7145").
  final String permitNo;

  // --- Step 6: Reels -------------------------------------------------------
  final ReelsPackage? reelsPackage;

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
    this.amenities = const [],
    this.occupancy,
    this.ageYears,
    this.contactEmail = '',
    this.contactPhone = '',
    this.contactWhatsapp = '',
    this.photos = const [],
    this.coverIndex = 0,
    this.video,
    this.tourBooked = false,
    this.titleDeed,
    this.idFront,
    this.idBack,
    this.selfie,
    this.permitNo = '',
    this.reelsPackage,
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
    List<String>? amenities,
    int? occupancy,
    int? ageYears,
    String? contactEmail,
    String? contactPhone,
    String? contactWhatsapp,
    List<DraftPhoto>? photos,
    int? coverIndex,
    UploadedDoc? video,
    bool? tourBooked,
    UploadedDoc? titleDeed,
    UploadedDoc? idFront,
    UploadedDoc? idBack,
    UploadedDoc? selfie,
    String? permitNo,
    ReelsPackage? reelsPackage,
    // copyWith can't tell "leave alone" from "set to null", so clearing a
    // nullable field needs a flag — same pattern as SearchQuery.
    bool clearPropertyType = false,
    bool clearPeriod = false,
    bool clearTitleDeed = false,
    bool clearLocation = false,
    bool clearVideo = false,
    bool clearIdFront = false,
    bool clearIdBack = false,
    bool clearSelfie = false,
    bool clearReelsPackage = false,
    bool clearOccupancy = false,
    bool clearAgeYears = false,
    bool clearBua = false,
    bool clearPrice = false,
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
        bua: clearBua ? null : (bua ?? this.bua),
        areaUnit: areaUnit ?? this.areaUnit,
        price: clearPrice ? null : (price ?? this.price),
        currency: currency ?? this.currency,
        period: clearPeriod ? null : (period ?? this.period),
        furnishing: furnishing ?? this.furnishing,
        title: title ?? this.title,
        description: description ?? this.description,
        amenities: amenities ?? this.amenities,
        occupancy: clearOccupancy ? null : (occupancy ?? this.occupancy),
        ageYears: clearAgeYears ? null : (ageYears ?? this.ageYears),
        contactEmail: contactEmail ?? this.contactEmail,
        contactPhone: contactPhone ?? this.contactPhone,
        contactWhatsapp: contactWhatsapp ?? this.contactWhatsapp,
        photos: photos ?? this.photos,
        coverIndex: coverIndex ?? this.coverIndex,
        video: clearVideo ? null : (video ?? this.video),
        tourBooked: tourBooked ?? this.tourBooked,
        titleDeed: clearTitleDeed ? null : (titleDeed ?? this.titleDeed),
        idFront: clearIdFront ? null : (idFront ?? this.idFront),
        idBack: clearIdBack ? null : (idBack ?? this.idBack),
        selfie: clearSelfie ? null : (selfie ?? this.selfie),
        permitNo: permitNo ?? this.permitNo,
        reelsPackage:
            clearReelsPackage ? null : (reelsPackage ?? this.reelsPackage),
      );

  // --- Verification shortcuts ---------------------------------------------

  /// Both sides of the ID photographed and uploaded.
  bool get idScanned => idFront != null && idBack != null;

  bool get selfieDone => selfie != null;

  bool get hasVideo => video != null;

  /// UAE listings need a deed, ID and permit number to publish (and the
  /// server checks the same). Elsewhere verification is optional.
  bool get verificationRequired => countryCode == 'AE';

  /// Name of the national ID for this market.
  String get idDocumentName => switch (countryCode) {
        'AE' => 'Emirates ID',
        'PK' => 'CNIC',
        'SA' => 'National ID / Iqama',
        'QA' => 'Qatar ID',
        _ => 'ID card',
      };

  // --- Completeness --------------------------------------------------------
  //
  // Each step knows what "done" means for it. The stepper enables its CTA off
  // these, Preview uses them for "All checks passed", and My Listings for the
  // "Missing: …" line. The database checks the same rules on submit.

  bool get basicsComplete => propertyType != null;

  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static int _digits(String v) => v.replaceAll(RegExp(r'[^0-9]'), '').length;

  bool get phoneValid => _digits(contactPhone) >= 8;

  /// WhatsApp is required — it's how most buyers reach listers.
  bool get whatsappValid => _digits(contactWhatsapp) >= 8;

  bool get emailValid =>
      contactEmail.trim().isEmpty || _emailPattern.hasMatch(contactEmail.trim());

  bool get contactComplete => phoneValid && whatsappValid && emailValid;

  /// What still blocks [step], in words — shown when "Next" is tapped early.
  List<String> missingFor(PostStep step) => switch (step) {
        PostStep.basics => [if (propertyType == null) 'property type'],
        PostStep.details => [
            if ((bua ?? 0) <= 0) 'built-up area',
            if ((price ?? 0) <= 0) 'price',
            if (title.trim().length < 5) 'title (at least 5 characters)',
            if (description.trim().length < 20)
              'description (at least 20 characters)',
            if (!emailValid) 'a valid email',
            if (!phoneValid) 'phone number',
            if (!whatsappValid) 'WhatsApp number',
          ],
        PostStep.media => [
            if (photosUploading) 'photos to finish uploading',
            if (!photosUploading && uploadedPhotoCount < 2) 'at least 2 photos',
          ],
        PostStep.location => [
            if (address.trim().isEmpty) 'address',
            if (city.isEmpty) 'city',
            if (latitude == null || longitude == null) 'map pin on the entrance',
          ],
        PostStep.permit => [
            if (verificationRequired && titleDeed == null) 'title deed',
            if (verificationRequired && !idScanned) '$idDocumentName (front & back)',
            if (verificationRequired && permitNo.trim().isEmpty) 'permit number',
          ],
        PostStep.reels => const [],
      };

  bool get detailsComplete =>
      (bua ?? 0) > 0 &&
      (price ?? 0) > 0 &&
      title.trim().length >= 5 &&
      description.trim().length >= 20 &&
      contactComplete;

  bool get photosUploading =>
      photos.any((p) => p.state == PhotoUploadState.uploading);

  int get uploadedPhotoCount => photos.where((p) => p.isUploaded).length;

  /// Two uploaded photos is the floor; nothing may still be uploading.
  bool get mediaComplete => uploadedPhotoCount >= 2 && !photosUploading;

  bool get locationComplete =>
      address.trim().isNotEmpty &&
      city.isNotEmpty &&
      latitude != null &&
      longitude != null;

  bool get permitComplete => verificationRequired
      ? titleDeed != null && idScanned && permitNo.trim().isNotEmpty
      : true;

  bool completed(PostStep step) => switch (step) {
        PostStep.basics => basicsComplete,
        PostStep.details => detailsComplete,
        PostStep.media => mediaComplete,
        PostStep.location => locationComplete,
        PostStep.permit => permitComplete,
        PostStep.reels => true,
      };

  bool get readyToPublish =>
      basicsComplete &&
      detailsComplete &&
      mediaComplete &&
      locationComplete &&
      permitComplete;

  /// "photos, price" — what's still needed.
  String get missingSummary {
    final missing = <String>[
      if (propertyType == null) 'type',
      if ((price ?? 0) <= 0) 'price',
      if ((bua ?? 0) <= 0) 'area',
      if (title.trim().length < 5) 'title',
      if (description.trim().length < 20) 'description',
      if (!contactComplete) 'contact',
      if (!mediaComplete) 'photos',
      if (!locationComplete) 'location',
      if (!permitComplete) 'verification',
    ];
    return missing.join(', ');
  }

  // --- Display -------------------------------------------------------------

  /// "AED 96,000 / year".
  String get priceLine {
    final p = price;
    if (p == null || p == 0) return 'Price not set';
    final suffix =
        purpose == Purpose.rent && period != null ? ' / ${period!.label}' : '';
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

  /// Built-up area in sqft, whatever unit was typed.
  int get buaSqft {
    final a = bua ?? 0;
    return areaUnit == AreaUnit.sqm ? (a * 10.7639).round() : a;
  }

  int get gradientSeed => photos.isNotEmpty
      ? photos[coverIndex.clamp(0, photos.length - 1)].seed
      : (id ?? title).hashCode.abs();

  /// Uploaded photo URLs with the cover first — the order buyers see.
  List<String> get orderedPhotoUrls {
    final uploaded = <String>[];
    final cover = coverIndex.clamp(0, photos.isEmpty ? 0 : photos.length - 1);
    if (photos.isNotEmpty && photos[cover].isUploaded) {
      uploaded.add(photos[cover].remoteUrl!);
    }
    for (var i = 0; i < photos.length; i++) {
      if (i == cover) continue;
      if (photos[i].isUploaded) uploaded.add(photos[i].remoteUrl!);
    }
    return uploaded;
  }

  String? get coverUrl {
    final urls = orderedPhotoUrls;
    return urls.isEmpty ? null : urls.first;
  }

  /// The listing as buyers will see it — for "preview the full page".
  /// Same rules as the server: public address is community + city, and the
  /// map shows the approximate area.
  Property toPreviewProperty({
    required String agentName,
    required String agency,
    String? avatarUrl,
    FairPrice? fairPrice,
  }) =>
      Property(
        id: id ?? 'preview',
        title: title.trim().isEmpty ? 'Untitled listing' : title.trim(),
        area: community,
        city: city,
        purpose: purpose,
        type: propertyType ?? 'apartment',
        beds: beds,
        baths: baths,
        sqft: buaSqft,
        occupancy: occupancy,
        furnishing: furnishing,
        ageYears: ageYears,
        price: price ?? 0,
        currency: currency,
        period: purpose == Purpose.rent ? period?.asRentPeriod : null,
        verified: titleDeed != null && idScanned,
        listedByOwner: agency == 'Property owner',
        fairPrice: fairPrice ?? FairPrice.unknown,
        permitNo: permitNo.trim().isEmpty ? null : permitNo.trim(),
        photos: orderedPhotoUrls
            .where((u) => u.startsWith('http'))
            .toList(growable: false),
        gradientSeed: gradientSeed,
        amenities: amenities,
        description: description.trim(),
        addressLine: [
          if (community.isNotEmpty) community,
          if (city.isNotEmpty) city,
        ].join(', '),
        agent: Agent(
          id: 'me',
          name: agentName,
          agency: agency,
          avatarUrl: avatarUrl,
        ),
        lat: latitude == null ? null : double.parse(latitude!.toStringAsFixed(3)),
        lng: longitude == null ? null : double.parse(longitude!.toStringAsFixed(3)),
        videoUrl: (video?.remoteUrl?.startsWith('http') ?? false)
            ? video!.remoteUrl
            : null,
        contact: ListingContact(
          phone: contactPhone.trim().isEmpty ? null : contactPhone.trim(),
          whatsapp:
              contactWhatsapp.trim().isEmpty ? null : contactWhatsapp.trim(),
          email: contactEmail.trim().isEmpty ? null : contactEmail.trim(),
        ),
      );

  /// Body for `save_listing` / `submit_listing`.
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
        if (purpose == Purpose.rent && period != null) 'rent_period': period!.name,
        'furnishing': furnishing,
        'title': title.trim(),
        'description': description.trim(),
        'amenities': amenities,
        'occupancy': occupancy,
        'age_years': ageYears,
        'contact_email': contactEmail.trim(),
        'contact_phone': contactPhone.trim(),
        'contact_whatsapp': contactWhatsapp.trim(),
        'photos': orderedPhotoUrls,
        'video_url': video?.remoteUrl,
        'tour_requested': tourBooked,
        'title_deed': titleDeed?.toJson(),
        'id_front': idFront?.toJson(),
        'id_back': idBack?.toJson(),
        'selfie': selfie?.toJson(),
        'permit_no': permitNo.trim(),
        'reels_package': reelsPackage?.wire,
      };

  /// From `my_listings()` / `save_listing()` → `draft`.
  factory ListingDraft.fromJson(Map<String, dynamic> j) {
    UploadedDoc? doc(String k) {
      final v = j[k];
      return v is Map ? UploadedDoc.fromJson(Map<String, dynamic>.from(v)) : null;
    }

    final photoUrls = (j['photos'] as List?)?.whereType<String>().toList() ??
        const <String>[];
    final videoUrl = j['video_url'] as String?;
    final purpose = PurposeX.parse(j['purpose'] as String?);

    return ListingDraft(
      id: j['id'] as String?,
      purpose: purpose,
      segment: j['segment'] == 'commercial'
          ? PropertySegment.commercial
          : PropertySegment.residential,
      propertyType: j['type'] as String?,
      countryCode: (j['country'] as String?) ?? 'AE',
      city: (j['city'] as String?) ?? '',
      address: (j['address'] as String?) ?? '',
      community: (j['community'] as String?) ?? '',
      latitude: (j['lat'] as num?)?.toDouble(),
      longitude: (j['lng'] as num?)?.toDouble(),
      beds: (j['beds'] as num?)?.toInt() ?? 0,
      baths: (j['baths'] as num?)?.toInt() ?? 0,
      bua: _positiveOrNull(j['bua']),
      areaUnit: AreaUnit.parse(j['area_unit'] as String?),
      price: _positiveOrNull(j['price']),
      currency: (j['currency'] as String?) ?? 'AED',
      period: purpose == Purpose.rent
          ? (PricePeriod.parse(j['rent_period'] as String?) ?? PricePeriod.yearly)
          : null,
      furnishing: j['furnishing'] as String?,
      title: (j['title'] as String?) ?? '',
      description: (j['description'] as String?) ?? '',
      amenities: (j['amenities'] as List?)?.whereType<String>().toList() ??
          const [],
      occupancy: (j['occupancy'] as num?)?.toInt(),
      ageYears: (j['age_years'] as num?)?.toInt(),
      contactEmail: (j['contact_email'] as String?) ?? '',
      contactPhone: (j['contact_phone'] as String?) ?? '',
      contactWhatsapp: (j['contact_whatsapp'] as String?) ?? '',
      photos: [
        for (var i = 0; i < photoUrls.length; i++)
          DraftPhoto.fromUrl(photoUrls[i], i),
      ],
      coverIndex: 0,
      video: videoUrl == null
          ? null
          : UploadedDoc(
              name: 'Walkthrough video',
              remoteUrl: videoUrl,
              storagePath: storagePathFromUrl(videoUrl, 'listing-videos'),
            ),
      tourBooked: j['tour_requested'] as bool? ?? false,
      titleDeed: doc('title_deed'),
      idFront: doc('id_front'),
      idBack: doc('id_back'),
      selfie: doc('selfie'),
      permitNo: (j['permit_no'] as String?) ?? '',
      reelsPackage: ReelsPackage.parse(j['reels_package'] as String?),
    );
  }

  static int? _positiveOrNull(Object? v) {
    final n = (v as num?)?.toInt();
    return n == null || n <= 0 ? null : n;
  }
}

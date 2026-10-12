import 'package:flutter/foundation.dart';

import 'uploaded_doc.dart';

/// How someone lists on Home8 — screen 28, "How will you use Home8?".
///
/// This is **not** the same question as `UserIntent`. `UserIntent` is "did you
/// come here to find or to list"; this is "when you list, who are you". Someone
/// can browse as a guest for a month, tap `+`, and become a [ListerType.agent]
/// without their intent ever having been `listProperty`.
///
/// The distinction matters because verification keys off this, not off intent:
/// an individual selling their own flat uploads a title deed, an agent uploads
/// a licence, and a company uploads a trade licence. Same flow, different
/// document and different badge.
enum ListerType {
  individual(
    'Individual',
    'Searching, renting or selling my own home',
  ),
  agent(
    'Agent',
    'I list properties professionally — needs licence verification',
  ),
  company(
    'Real Estate Company',
    'Agency with multiple agents - trade license required',
  );

  final String label;
  final String blurb;
  const ListerType(this.label, this.blurb);

  /// Agents and companies pass through screen 29 before they reach the app;
  /// individuals go straight through.
  ///
  /// Individuals still verify — but per *listing*, at the permit step, because
  /// a title deed belongs to a property rather than to a person. Company
  /// verification is per *account*, which is why it happens once at sign-up.
  ///
  /// Everyone verifies now: only approved individuals, agents and companies
  /// can publish listings.
  bool get needsAccountVerification => true;

  /// Verification screen title (prototype 63 / 64 / 65).
  String get verifyTitle => switch (this) {
        ListerType.individual => 'Individual Verification',
        ListerType.agent => 'Agent Verification',
        ListerType.company => 'Verify your Company',
      };

  /// Line under the title.
  String get verifySubtitle => switch (this) {
        ListerType.individual =>
          'Required to earn the Verified-Seller badge and post unlimited listings.',
        ListerType.agent =>
          'Required to earn the Verified-Agent badge and post unlimited listings.',
        ListerType.company =>
          'Required to earn the Verified-Company badge and post unlimited listings.',
      };

  /// Label above the company field (agents and companies).
  String get organisationLabel =>
      this == ListerType.company ? 'Company name' : 'Associated Company';

  static ListerType? parse(String? value) {
    for (final t in ListerType.values) {
      if (t.name == value) return t;
    }
    return null;
  }
}

/// Where an account's verification stands.
///
/// [pending] is a real state with real consequences, not a spinner: a pending
/// account can browse and save, but its listings stay in draft. Screen 29 says
/// so in the amber note, and `MyListingsScreen` enforces it.
enum VerificationStatus {
  /// Nothing submitted. Individuals sit here permanently and that's fine.
  none,

  /// Submitted, under review — up to one business day.
  pending,

  verified,

  /// Reviewed and turned down. Kept distinct from [none] so the UI can explain
  /// what happened rather than silently offering the form again.
  rejected;

  static VerificationStatus parse(String? value) {
    for (final s in VerificationStatus.values) {
      if (s.name == value) return s;
    }
    return VerificationStatus.none;
  }
}

/// The seller side of an account.
///
/// Deliberately separate from `AuthUser` rather than fields bolted onto it:
/// most accounts never have one of these, and keeping it nullable is how the
/// rest of the app asks "is this a lister?" without a boolean that can drift
/// out of sync with the data behind it.
@immutable
class ListerProfile {
  final ListerType type;

  /// Company or agency name. Empty for an individual.
  final String organisation;

  /// RERA / trade licence number, as typed. Not validated here — format varies
  /// by market and the backend is the only thing that can actually check it.
  final String licenceNumber;

  final UploadedDoc? tradeLicence;
  final UploadedDoc? brokerCard;
  final VerificationStatus status;

  /// Individuals: name as on the ID, and both sides of the card.
  final String legalName;
  final UploadedDoc? idFront;
  final UploadedDoc? idBack;

  /// Why the last request was rejected. Empty otherwise.
  final String reviewNote;

  /// When the current request was sent (from the server).
  final DateTime? submittedAt;

  /// Trust score shown on the profile header ("TRUST 92"). Computed server-side
  /// from verification, response time and listing quality — the app only
  /// displays it. Null until the backend returns one.
  final int? trustScore;

  const ListerProfile({
    required this.type,
    this.organisation = '',
    this.licenceNumber = '',
    this.tradeLicence,
    this.brokerCard,
    this.status = VerificationStatus.none,
    this.trustScore,
    this.legalName = '',
    this.idFront,
    this.idBack,
    this.reviewNote = '',
    this.submittedAt,
  });

  ListerProfile copyWith({
    ListerType? type,
    String? organisation,
    String? licenceNumber,
    UploadedDoc? tradeLicence,
    UploadedDoc? brokerCard,
    VerificationStatus? status,
    int? trustScore,
    String? legalName,
    UploadedDoc? idFront,
    UploadedDoc? idBack,
    String? reviewNote,
    DateTime? submittedAt,
    bool clearTradeLicence = false,
    bool clearBrokerCard = false,
  }) =>
      ListerProfile(
        type: type ?? this.type,
        organisation: organisation ?? this.organisation,
        licenceNumber: licenceNumber ?? this.licenceNumber,
        tradeLicence:
            clearTradeLicence ? null : (tradeLicence ?? this.tradeLicence),
        brokerCard: clearBrokerCard ? null : (brokerCard ?? this.brokerCard),
        status: status ?? this.status,
        trustScore: trustScore ?? this.trustScore,
        legalName: legalName ?? this.legalName,
        idFront: idFront ?? this.idFront,
        idBack: idBack ?? this.idBack,
        reviewNote: reviewNote ?? this.reviewNote,
        submittedAt: submittedAt ?? this.submittedAt,
      );

  /// Screen 29's CTA only enables when there's something to review.
  bool get canSubmit => type == ListerType.individual
      ? legalName.trim().isNotEmpty && idFront != null && idBack != null
      : organisation.trim().isNotEmpty &&
          licenceNumber.trim().isNotEmpty &&
          tradeLicence != null;

  /// Drives the "Verified-Agent" badge on listing cards and the profile header.
  bool get isVerified => status == VerificationStatus.verified;

  /// True while listings must stay in draft — see the amber note on screen 29.
  bool get listingsBlocked => status != VerificationStatus.verified;

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'organisation': organisation,
        'licence_number': licenceNumber,
        'status': status.name,
        if (legalName.isNotEmpty) 'legal_name': legalName,
        if (trustScore != null) 'trust_score': trustScore,
        if (tradeLicence != null) 'trade_licence': tradeLicence!.toJson(),
        if (brokerCard != null) 'broker_card': brokerCard!.toJson(),
      };

  factory ListerProfile.fromJson(Map<String, dynamic> json) => ListerProfile(
        type: ListerType.parse(json['type'] as String?) ??
            ListerType.individual,
        organisation: json['organisation'] as String? ?? '',
        licenceNumber: json['licence_number'] as String? ?? '',
        status: VerificationStatus.parse(json['status'] as String?),
        legalName: json['legal_name'] as String? ?? '',
        trustScore: json['trust_score'] as int?,
        tradeLicence: json['trade_licence'] == null
            ? null
            : UploadedDoc.fromJson(
                json['trade_licence'] as Map<String, dynamic>),
        brokerCard: json['broker_card'] == null
            ? null
            : UploadedDoc.fromJson(json['broker_card'] as Map<String, dynamic>),
      );
}

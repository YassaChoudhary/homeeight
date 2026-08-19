import 'package:flutter/foundation.dart';

import '../models/lister_profile.dart';
import 'guest_migration.dart';

/// What the user said they came for on screen 26.
enum UserIntent {
  findProperty('Find a Property'),
  listProperty('List a property');

  final String label;
  const UserIntent(this.label);
}

/// How the session was started. Kept so the profile screen can show it and so
/// the API layer later knows which token endpoint to refresh against.
enum AuthMethod { phone, email, google, apple }

/// The signed-in user.
///
/// **This is frontend-only.** There is no token, no expiry and no server
/// round-trip — [AuthController.verifyCode] accepts any six digits. When the
/// backend lands, this class gains `accessToken` / `refreshToken`, and the
/// mock branches in [AuthController] become real calls behind an
/// `AuthRepository` in the same shape as `ListingRepository`.
@immutable
class AuthUser {
  final String id;
  final String name;
  final String? phone;
  final String? email;
  final String? avatarUrl;
  final AuthMethod method;
  final UserIntent intent;
  final int memberSince;
  final bool phoneVerified;
  final bool emailVerified;

  /// The seller side of this account, or null for someone who has only ever
  /// browsed.
  ///
  /// Nullable rather than a `bool isAgent` flag: the presence of the object is
  /// the answer, so there's no boolean that can drift out of step with the
  /// company name and licence sitting next to it.
  final ListerProfile? listerProfile;

  const AuthUser({
    required this.id,
    required this.name,
    this.phone,
    this.email,
    this.avatarUrl,
    this.method = AuthMethod.phone,
    this.intent = UserIntent.findProperty,
    this.memberSince = 2026,
    this.phoneVerified = false,
    this.emailVerified = false,
    this.listerProfile,
  });

  AuthUser copyWith({
    String? name,
    String? phone,
    String? email,
    String? avatarUrl,
    UserIntent? intent,
    bool? phoneVerified,
    bool? emailVerified,
    ListerProfile? listerProfile,
  }) =>
      AuthUser(
        id: id,
        name: name ?? this.name,
        phone: phone ?? this.phone,
        email: email ?? this.email,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        method: method,
        intent: intent ?? this.intent,
        memberSince: memberSince,
        phoneVerified: phoneVerified ?? this.phoneVerified,
        emailVerified: emailVerified ?? this.emailVerified,
        listerProfile: listerProfile ?? this.listerProfile,
      );

  /// True once the account has a seller side — which is what swaps the profile
  /// menu to the lister one.
  ///
  /// Two ways in, both legitimate: picking "List a property" on screen 27, or
  /// tapping `+` as a browser and completing screen 28. Someone who came to
  /// find a home and then decided to rent theirs out shouldn't have to redo
  /// onboarding to get the seller menu.
  bool get isLister =>
      listerProfile != null || intent == UserIntent.listProperty;

  /// The lister's type, defaulting to individual once they're a lister but
  /// before screen 28 has been answered.
  ListerType get listerType => listerProfile?.type ?? ListerType.individual;

  /// "Member since 2026 · Dubai" — the city comes from AppState, not here.
  String memberLine(String city) => 'Member since $memberSince · $city';

  /// Phone with the middle digits masked, for the OTP screen's "We sent a
  /// 6-digit code to +971 50 ••• 4567".
  static String maskPhone(String dial, String number) {
    final digits = number.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 6) return '$dial $number';
    final head = digits.substring(0, 2);
    final tail = digits.substring(digits.length - 4);
    return '$dial $head ••• $tail';
  }
}

/// Session state, deliberately separate from `AppState`.
///
/// `AppState` is watched by nearly every screen for market and language, so
/// putting auth in it would rebuild the world on sign-in. This is its own
/// notifier for the same reason `SavedListingsStore` is.
///
/// Everything here is local and synchronous apart from a simulated delay, so
/// the button loading states are exercised for real before a backend exists.
class AuthController extends ChangeNotifier {
  AuthUser? _user;

  /// Set while a step is in flight, so CTAs can show their loading state.
  bool _busy = false;

  /// Carried between the login screen and the OTP screen.
  String _pendingDial = '+971';
  String _pendingPhone = '';
  String? _pendingEmail;

  /// Simulated round-trip. Zero in tests.
  final Duration latency;

  AuthController({this.latency = const Duration(milliseconds: 600)});

  AuthUser? get user => _user;
  bool get isSignedIn => _user != null;
  bool get busy => _busy;
  String get pendingDial => _pendingDial;
  String get pendingPhone => _pendingPhone;
  String? get pendingEmail => _pendingEmail;

  String get maskedTarget => _pendingEmail ??
      AuthUser.maskPhone(_pendingDial, _pendingPhone);

  void _setBusy(bool value) {
    if (_busy == value) return;
    _busy = value;
    notifyListeners();
  }

  Future<void> _wait() async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
  }

  /// Step 1 (screen 23) — record the number and "send" a code.
  Future<void> requestPhoneCode({
    required String dial,
    required String phone,
  }) async {
    _pendingDial = dial;
    _pendingPhone = phone;
    _pendingEmail = null;
    _setBusy(true);
    await _wait();
    _setBusy(false);
  }

  /// Step 1, email variant (screen 24).
  Future<void> requestEmailCode(String email) async {
    _pendingEmail = email;
    _setBusy(true);
    await _wait();
    _setBusy(false);
  }

  /// Step 2 (screen 25). **Accepts any six digits** — there is nothing to
  /// verify against yet. The signature already returns a bool so the screen's
  /// error path exists and will work unchanged against a real endpoint.
  Future<bool> verifyCode(String code) async {
    if (code.replaceAll(RegExp(r'\D'), '').length != 6) return false;
    _setBusy(true);
    await _wait();
    _user = AuthUser(
      id: 'u_local',
      name: 'Syed Salman Ali',
      phone: _pendingEmail == null
          ? '$_pendingDial ${_pendingPhone.trim()}'
          : null,
      email: _pendingEmail,
      method: _pendingEmail == null ? AuthMethod.phone : AuthMethod.email,
      phoneVerified: _pendingEmail == null,
      emailVerified: _pendingEmail != null,
    );
    await _onSignedIn();
    _setBusy(false);
    notifyListeners();
    return true;
  }

  /// Google / Apple buttons. No SDK wired, so this signs in directly.
  Future<void> signInWithProvider(AuthMethod method) async {
    _setBusy(true);
    await _wait();
    _user = AuthUser(
      id: 'u_local',
      name: 'Syed Salman Ali',
      email: 'salman.ali@gmail.com',
      method: method,
      emailVerified: true,
    );
    await _onSignedIn();
    _setBusy(false);
    notifyListeners();
  }

  /// Runs on every successful sign-in, whatever the method.
  ///
  /// Snapshots the guest's local state (market, language, searches, detected
  /// city) and parks it for upload, so nothing they set up before signing in is
  /// lost. Capture and upload are separate steps on purpose: if the upload
  /// fails the payload stays on the device and is retried next launch.
  Future<void> _onSignedIn() async {
    await GuestMigration.capture();
    await GuestMigration.flush();
  }

  /// Step 3 (screen 26).
  void setIntent(UserIntent intent) {
    final u = _user;
    if (u == null) return;
    _user = u.copyWith(intent: intent);
    notifyListeners();
  }

  void updateProfile({
    String? name,
    String? phone,
    String? email,
    String? avatarUrl,
  }) {
    final u = _user;
    if (u == null) return;
    _user = u.copyWith(
      name: name,
      phone: phone,
      email: email,
      avatarUrl: avatarUrl,
    );
    notifyListeners();
  }

  /// Screen 28 — records who the user is when they list.
  ///
  /// Also flips [UserIntent] to `listProperty`: someone who has just told us
  /// they're an agency is a lister regardless of which button they pressed on
  /// screen 27, and leaving intent behind would give them the buyer menu.
  void setListerProfile(ListerProfile profile) {
    final u = _user;
    if (u == null) return;
    _user = u.copyWith(
      listerProfile: profile,
      intent: UserIntent.listProperty,
    );
    notifyListeners();
  }

  /// Screen 29 — advances verification after the repository accepts the
  /// documents. Kept separate from [setListerProfile] so the status can only
  /// move as the result of a server call, never as a side effect of editing a
  /// form field.
  void setVerificationStatus(VerificationStatus status) {
    final u = _user;
    final profile = u?.listerProfile;
    if (u == null || profile == null) return;
    _user = u.copyWith(listerProfile: profile.copyWith(status: status));
    notifyListeners();
  }

  void signOut() {
    _user = null;
    _pendingPhone = '';
    _pendingEmail = null;
    notifyListeners();
  }
}

/// Dialling codes for the country picker on screen 23. Ordered with the launch
/// markets first, which is why this isn't just sorted alphabetically.
class DialCode {
  final String country;
  final String dial;
  final String flagAsset;

  const DialCode(this.country, this.dial, this.flagAsset);

  static const List<DialCode> all = [
    DialCode('United Arab Emirates', '+971', 'assets/images/flags/uae.png'),
    DialCode('Saudi Arabia', '+966', 'assets/images/flags/ksa.png'),
    DialCode('Qatar', '+974', 'assets/images/flags/qatar.png'),
    DialCode('Pakistan', '+92', 'assets/images/flags/pakistan.png'),
    DialCode('United Kingdom', '+44', 'assets/images/flags/uk.png'),
    DialCode('United States', '+1', 'assets/images/flags/usa.png'),
    DialCode('Canada', '+1', 'assets/images/flags/canada.png'),
    DialCode('Australia', '+61', 'assets/images/flags/australia.png'),
    DialCode('New Zealand', '+64', 'assets/images/flags/newzealand.png'),
  ];

  String get label => '$country ($dial)';
}

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show Supabase, FunctionException;

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
/// Built from two sources: the Firebase Auth account (uid, email, login
/// method, verified flags) and the user's record in Firestore at
/// `users/{uid}` (name edits, intent, lister profile). Firebase holds the
/// tokens itself, so nothing token-shaped lives here.
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

/// A sign-in step failed in a way the user should be told about.
///
/// [message] is already written for people, so screens can show it as-is in a
/// snackbar or under the form. A user cancelling the Google sheet is *not* an
/// error and never produces one of these.
class AuthException implements Exception {
  final String message;
  const AuthException(this.message);

  @override
  String toString() => message;
}

/// Session state, deliberately separate from `AppState`.
///
/// `AppState` is watched by nearly every screen for market and language, so
/// putting auth in it would rebuild the world on sign-in. This is its own
/// notifier for the same reason `SavedListingsStore` is.
///
/// Two modes:
///
/// * **Firebase** (`useFirebase: true`, set by `main.dart` when
///   `Firebase.initializeApp()` succeeds — today that's Android). Google is
///   plain Firebase Auth. Email codes go through the free Supabase Edge
///   Function `email-auth`, which returns a Firebase custom token — so every
///   user is a Firebase user either way. The session survives restarts
///   because Firebase persists it; [_onAuthStateChanged] restores it on launch. The user record
///   lives in Firestore at `users/{uid}`.
/// * **Local** (Firebase unavailable — iOS/web until they're configured, and
///   widget tests). The old frontend-only behaviour: any six-digit code passes
///   and nothing leaves the device. Kept so the app still runs everywhere.
///
/// Phone OTP and Apple stay local-only for now: phone needs the paid Blaze plan
/// plus an SMS budget, and Apple needs an Apple Developer account. The login
/// screen checks [usesFirebase] and tells the user to pick Email or Google.
class AuthController extends ChangeNotifier {
  AuthController({
    this.latency = const Duration(milliseconds: 600),
    bool useFirebase = false,
    bool useSupabase = false,
  })  : _useFirebase = useFirebase,
        _useSupabase = useSupabase {
    if (_useFirebase) {
      _authSub =
          FirebaseAuth.instance.authStateChanges().listen(_onAuthStateChanged);
    }
  }

  final bool _useFirebase;

  /// True when Supabase is initialised — the email-code Edge Function and the
  /// Google users' Supabase claim both go through it.
  final bool _useSupabase;

  /// True when sign-in goes to Firebase rather than the local stand-in.
  bool get usesFirebase => _useFirebase;

  AuthUser? _user;

  /// Set while a step is in flight, so CTAs can show their loading state.
  bool _busy = false;

  /// True between starting a sign-in and finishing its Firestore record, so
  /// the auth-state listener doesn't race the sign-in method to write it.
  bool _signingIn = false;

  bool _lastSignInWasNew = false;

  StreamSubscription<User?>? _authSub;

  /// Carried between the login screen and the OTP screen (local mode only).
  String _pendingDial = '+971';
  String _pendingPhone = '';
  String? _pendingEmail;

  /// Simulated round-trip for the local mode. Zero in tests.
  final Duration latency;

  AuthUser? get user => _user;
  bool get isSignedIn => _user != null;
  bool get busy => _busy;
  String get pendingDial => _pendingDial;
  String get pendingPhone => _pendingPhone;
  String? get pendingEmail => _pendingEmail;

  /// True when the most recent sign-in created the account (or the account had
  /// no Firestore record yet). Screens use it to ask the "what brings you to
  /// Home8" question once, instead of on every login.
  bool get lastSignInWasNew => _lastSignInWasNew;

  String get maskedTarget =>
      _pendingEmail ?? AuthUser.maskPhone(_pendingDial, _pendingPhone);

  FirebaseAuth get _firebaseAuth => FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _users =>
      FirebaseFirestore.instance.collection('users');

  void _setBusy(bool value) {
    if (_busy == value) return;
    _busy = value;
    notifyListeners();
  }

  Future<void> _wait() async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
  }

  // ---------------------------------------------------------------------------
  // Email one-time code (Supabase Edge Function `email-auth` → Firebase login)
  // ---------------------------------------------------------------------------

  /// Calls supabase/functions/email-auth/index.ts. Returns its JSON body;
  /// failures become [AuthException] with the server's own message
  /// ("That code isn't right. 3 attempts left.").
  Future<Map<String, dynamic>> _emailAuth(Map<String, Object?> body) async {
    if (!_useSupabase) {
      throw const AuthException(
          'Email sign-in needs the Supabase connection. Run the app with '
          '--dart-define-from-file=env.json');
    }
    try {
      final res = await Supabase.instance.client.functions
          .invoke('email-auth', body: body)
          .timeout(const Duration(seconds: 25));
      final data = res.data;
      return data is Map ? Map<String, dynamic>.from(data) : const {};
    } on FunctionException catch (e) {
      debugPrint('email-auth ${e.status}: ${e.details}');
      throw AuthException(_edgeMessage(e));
    } on TimeoutException {
      throw const AuthException(
          'The server took too long to respond. Please try again.');
    } on AuthException {
      rethrow;
    } catch (e) {
      debugPrint('email-auth unreachable: $e');
      throw const AuthException(
          'No internet connection. Check your network and try again.');
    }
  }

  /// Step 1 (screen 24) — email a 6-digit code to [email].
  ///
  /// One flow for everyone: a new address gets an account when the code is
  /// verified, an existing one just signs in. Throws [AuthException] (rate
  /// limit, bad address, email service down) with a message to show as-is.
  Future<void> requestEmailCode(String email) async {
    _pendingEmail = email.trim();
    _pendingPhone = '';

    if (!_useFirebase) {
      _setBusy(true);
      await _wait();
      _setBusy(false);
      return;
    }

    await _run(() async {
      await _emailAuth({'action': 'send', 'email': _pendingEmail});
    });
  }

  /// "Resend code" on the OTP screen — same address, fresh code.
  Future<void> resendCode() async {
    final email = _pendingEmail;
    if (email == null) return;
    await requestEmailCode(email);
  }

  /// Step 2 (screen 25) — check the code and sign in.
  ///
  /// Returns true when signed in. With Firebase on, a wrong, expired or
  /// locked-out code throws [AuthException] carrying the server's message
  /// ("That code isn't right. 3 attempts left."). In local mode any six
  /// digits pass.
  Future<bool> verifyCode(String code) async {
    final digits = code.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 6) return false;
    if (!_useFirebase) return _verifyLocally();

    final email = _pendingEmail;
    if (email == null) {
      throw const AuthException('Enter your email again to get a new code.');
    }

    await _run(() async {
      final data = await _emailAuth(
          {'action': 'verify', 'email': email, 'code': digits});
      final token = data['token'] as String?;
      if (token == null) {
        throw const AuthException('Sign-in failed. Please try again.');
      }
      final credential = await _firebaseAuth.signInWithCustomToken(token);
      await _completeSignIn(credential, AuthMethod.email);
    });
    return true;
  }

  // ---------------------------------------------------------------------------
  // Google (Firebase)
  // ---------------------------------------------------------------------------

  static Future<void>? _googleInit;

  /// Runs `GoogleSignIn.initialize` once per app run. On Android the web client
  /// ID is read from google-services.json, so no client IDs are passed here.
  Future<void> _ensureGoogleReady() =>
      _googleInit ??= GoogleSignIn.instance.initialize();

  /// Shows Google's account picker and signs into Firebase with the result.
  ///
  /// Returns false if the user closed the picker — that's a choice, not an
  /// error, so the screen should just stay where it is.
  Future<bool> signInWithGoogle() async {
    if (!_useFirebase) {
      await signInWithProvider(AuthMethod.google);
      return true;
    }

    var completed = false;
    await _run(() async {
      try {
        await _ensureGoogleReady();
        final account = await GoogleSignIn.instance.authenticate();
        final idToken = account.authentication.idToken;
        if (idToken == null) {
          throw const AuthException(
              "Google didn't return a sign-in token. Please try again.");
        }
        final credential = await _firebaseAuth.signInWithCredential(
          GoogleAuthProvider.credential(idToken: idToken),
        );
        await _completeSignIn(credential, AuthMethod.google);
        completed = true;
      } on GoogleSignInException catch (e) {
        if (e.code == GoogleSignInExceptionCode.canceled ||
            e.code == GoogleSignInExceptionCode.interrupted) {
          return; // closed the picker
        }
        debugPrint('Google sign-in failed: ${e.code} ${e.description}');
        throw AuthException(_googleMessage(e));
      }
    });
    return completed;
  }

  // ---------------------------------------------------------------------------
  // Shared sign-in plumbing
  // ---------------------------------------------------------------------------

  /// Busy flag, the listener guard and error translation, around one step.
  Future<void> _run(Future<void> Function() step) async {
    _setBusy(true);
    _signingIn = true;
    try {
      await step();
    } on FirebaseAuthException catch (e) {
      debugPrint('FirebaseAuthException: ${e.code} ${e.message}');
      throw AuthException(_firebaseMessage(e));
    } on FirebaseException catch (e) {
      debugPrint('FirebaseException: ${e.plugin} ${e.code} ${e.message}');
      throw const AuthException(
          'Something went wrong talking to the server. Please try again.');
    } finally {
      _signingIn = false;
      _setBusy(false);
    }
  }

  void _requireFirebase() {
    if (!_useFirebase) {
      throw const AuthException(
          'Sign-in is not configured on this device yet.');
    }
  }

  /// After Firebase accepts the credentials: load or create `users/{uid}`,
  /// publish the user, and hand guest settings to the account.
  Future<void> _completeSignIn(
    UserCredential credential,
    AuthMethod method, {
    String? name,
  }) async {
    final account = credential.user;
    if (account == null) {
      throw const AuthException('Sign-in failed. Please try again.');
    }

    final base = _fromFirebase(account, method: method, nameOverride: name);
    final existed = await _loadOrCreateRecord(account, base);
    await _ensureSupabaseRole(account);

    _lastSignInWasNew =
        (credential.additionalUserInfo?.isNewUser ?? false) || !existed;
    await _onSignedIn();
    notifyListeners();
  }

  /// Fills [_user] from Firestore, creating the record if it doesn't exist.
  /// Returns whether it already existed.
  ///
  /// A Firestore failure (no database created yet, offline, rules) does **not**
  /// fail the sign-in — the person is signed in either way, and the record is
  /// retried on the next launch by [_onAuthStateChanged].
  Future<bool> _loadOrCreateRecord(User account, AuthUser base) async {
    _user = base;
    try {
      final doc = _users.doc(account.uid);
      final snapshot = await doc.get().timeout(const Duration(seconds: 10));
      if (_firebaseAuth.currentUser?.uid != account.uid) return true;

      final data = snapshot.data();
      if (snapshot.exists && data != null) {
        _user = _mergeRecord(base, data);
        return true;
      }

      await doc.set({
        ..._recordFields(base),
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return false;
    } catch (error) {
      debugPrint('User record unavailable, continuing signed in: $error');
      return true;
    }
  }

  /// Fires on launch (session restore), on sign-in and on sign-out.
  Future<void> _onAuthStateChanged(User? account) async {
    if (account == null) {
      if (_user != null) {
        _user = null;
        notifyListeners();
      }
      return;
    }
    // A sign-in method is already loading the record; let it finish.
    if (_signingIn) return;
    if (_user?.id == account.uid) return;

    // Before publishing the user, so anything that reacts to sign-in (the
    // saved hearts) already talks to Supabase as this user.
    await _ensureSupabaseRole(account);
    _user = _fromFirebase(account);
    notifyListeners();
    await _loadOrCreateRecord(account, _user!);
    notifyListeners();
  }

  /// Makes sure this login's Firebase ID token carries `role: authenticated`,
  /// which is what Supabase needs to treat the person as signed in (without
  /// it they read listings as an anonymous visitor and can't save hearts).
  ///
  /// Email-code logins already have it from the custom token. Google logins
  /// get it once from the `email-auth` Edge Function ("ensure-role"), then the
  /// token is refreshed so the claim takes effect immediately. Never fails
  /// sign-in.
  Future<void> _ensureSupabaseRole(User account) async {
    if (!_useSupabase) return;
    try {
      final current = await account.getIdTokenResult();
      if (current.claims?['role'] == 'authenticated') return;
      await _emailAuth({
        'action': 'ensure-role',
        'idToken': current.token ?? await account.getIdToken(),
      });
      await account.getIdToken(true);
    } catch (error) {
      debugPrint('Supabase role claim not set (will retry next launch): $error');
    }
  }

  /// Runs on every successful sign-in, whatever the method.
  ///
  /// Snapshots the guest's local state (market, language, searches, detected
  /// city) and parks it for upload, so nothing they set up before signing in is
  /// lost. Capture and upload are separate steps on purpose: if the upload
  /// fails the payload stays on the device and is retried next launch.
  ///
  /// The upload isn't awaited: it can take seconds on a weak connection, and
  /// the user shouldn't sit on a spinner for settings they already have.
  Future<void> _onSignedIn() async {
    await GuestMigration.capture();
    unawaited(GuestMigration.flush());
  }

  // ---------------------------------------------------------------------------
  // Local stand-in (phone OTP, Apple, and every method when Firebase is off)
  // ---------------------------------------------------------------------------

  /// Step 1 (screen 23) — record the number and "send" a code. Local only.
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

  /// Local-mode code check: **accepts any six digits**.
  Future<bool> _verifyLocally() async {
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
    _lastSignInWasNew = true;
    await _onSignedIn();
    _setBusy(false);
    notifyListeners();
    return true;
  }

  /// Local-mode provider sign-in. No SDK involved.
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
    _lastSignInWasNew = true;
    await _onSignedIn();
    _setBusy(false);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Profile edits — local state first, then written to users/{uid}
  // ---------------------------------------------------------------------------

  /// Step 3 (screen 26).
  void setIntent(UserIntent intent) {
    final u = _user;
    if (u == null) return;
    _user = u.copyWith(intent: intent);
    _saveRecord({'intent': intent.name});
    notifyListeners();
  }

  /// Name, phone and photo are saved to the user record.
  ///
  /// [email] only changes the profile record, not the login email — changing
  /// the address you sign in with needs Firebase's re-verification flow, which
  /// isn't built yet.
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
    _saveRecord({
      if (name != null) 'name': name,
      if (phone != null) 'phone': phone,
      if (email != null) 'email': email,
      if (avatarUrl != null) 'photoUrl': avatarUrl,
    });
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
    _saveRecord({
      'lister': profile.toJson(),
      'intent': UserIntent.listProperty.name,
    });
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
    final next = profile.copyWith(status: status);
    _user = u.copyWith(listerProfile: next);
    _saveRecord({'lister': next.toJson()});
    notifyListeners();
  }

  void signOut() {
    _user = null;
    _pendingPhone = '';
    _pendingEmail = null;
    _lastSignInWasNew = false;
    notifyListeners();

    if (_useFirebase) {
      unawaited(_firebaseAuth.signOut());
      // Also forget the Google account, so the next "Continue with Google"
      // shows the picker instead of silently reusing the last account.
      final init = _googleInit;
      if (init != null) {
        unawaited(init
            .then((_) => GoogleSignIn.instance.signOut())
            .catchError((Object e) => debugPrint('Google sign-out: $e')));
      }
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Firestore record mapping
  // ---------------------------------------------------------------------------

  /// Fire-and-forget merge into `users/{uid}`. Firestore queues writes while
  /// offline and sends them when the connection returns.
  void _saveRecord(Map<String, dynamic> fields) {
    if (!_useFirebase) return;
    final uid = _firebaseAuth.currentUser?.uid;
    if (uid == null || fields.isEmpty) return;
    _users
        .doc(uid)
        .set({...fields, 'updatedAt': FieldValue.serverTimestamp()},
            SetOptions(merge: true))
        .catchError((Object e) => debugPrint('User record save failed: $e'));
  }

  /// Fields written when the record is first created.
  Map<String, dynamic> _recordFields(AuthUser u) => {
        'uid': u.id,
        'name': u.name,
        'email': u.email,
        'phone': u.phone,
        'photoUrl': u.avatarUrl,
        'authMethod': u.method.name,
        'emailVerified': u.emailVerified,
        'phoneVerified': u.phoneVerified,
        'intent': u.intent.name,
        'memberSince': u.memberSince,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  /// Builds the user from the Firebase account alone.
  AuthUser _fromFirebase(
    User account, {
    AuthMethod? method,
    String? nameOverride,
  }) {
    final email = account.email;
    final fallbackName =
        email != null && email.contains('@') ? email.split('@').first : 'Home8 user';
    return AuthUser(
      id: account.uid,
      name: (nameOverride?.isNotEmpty ?? false)
          ? nameOverride!
          : (account.displayName?.isNotEmpty ?? false)
              ? account.displayName!
              : fallbackName,
      email: email,
      phone: account.phoneNumber,
      avatarUrl: account.photoURL,
      method: method ?? _methodOf(account),
      memberSince:
          account.metadata.creationTime?.year ?? DateTime.now().year,
      emailVerified: account.emailVerified,
      phoneVerified: account.phoneNumber != null,
    );
  }

  /// Applies the Firestore record on top of the Firebase account.
  AuthUser _mergeRecord(AuthUser base, Map<String, dynamic> data) {
    UserIntent? intent;
    final intentName = data['intent'];
    for (final i in UserIntent.values) {
      if (i.name == intentName) intent = i;
    }

    ListerProfile? lister;
    final listerJson = data['lister'];
    if (listerJson is Map) {
      try {
        lister = ListerProfile.fromJson(Map<String, dynamic>.from(listerJson));
      } catch (error) {
        debugPrint('Ignoring unreadable lister profile: $error');
      }
    }

    String? text(String key) {
      final v = data[key];
      return v is String && v.isNotEmpty ? v : null;
    }

    return AuthUser(
      id: base.id,
      name: text('name') ?? base.name,
      phone: text('phone') ?? base.phone,
      email: base.email ?? text('email'),
      avatarUrl: text('photoUrl') ?? base.avatarUrl,
      method: base.method,
      intent: intent ?? base.intent,
      memberSince: (data['memberSince'] as num?)?.toInt() ?? base.memberSince,
      // Verified flags come from Firebase, never from the editable record.
      phoneVerified: base.phoneVerified,
      emailVerified: base.emailVerified,
      listerProfile: lister,
    );
  }

  static AuthMethod _methodOf(User account) {
    for (final info in account.providerData) {
      switch (info.providerId) {
        case 'google.com':
          return AuthMethod.google;
        case 'apple.com':
          return AuthMethod.apple;
        case 'phone':
          return AuthMethod.phone;
      }
    }
    return AuthMethod.email;
  }

  static String _firebaseMessage(FirebaseAuthException e) => switch (e.code) {
        'invalid-email' => 'That email address doesn\'t look right.',
        'user-disabled' => 'This account has been disabled.',
        'user-not-found' ||
        'wrong-password' ||
        'invalid-credential' ||
        'INVALID_LOGIN_CREDENTIALS' =>
          'Email or password is incorrect.',
        'email-already-in-use' =>
          'An account already exists with this email. Try signing in instead.',
        'weak-password' => 'Password is too weak — use at least 6 characters.',
        'too-many-requests' =>
          'Too many attempts. Please wait a moment and try again.',
        'network-request-failed' =>
          'No internet connection. Check your network and try again.',
        'operation-not-allowed' =>
          'This sign-in method is turned off in Firebase. Enable it under '
              'Authentication → Sign-in method.',
        'account-exists-with-different-credential' =>
          'This email is already registered with a different sign-in method.',
        _ => e.message ?? 'Sign-in failed. Please try again.',
      };

  /// The Edge Function already writes user-facing messages for everything it
  /// handles (wrong code, expired, rate limit…), in `{error: {message}}`.
  static String _edgeMessage(FunctionException e) {
    final details = e.details;
    if (details is Map && details['error'] is Map) {
      final message = (details['error'] as Map)['message'];
      if (message is String && message.isNotEmpty) return message;
    }
    return switch (e.status) {
      404 => "Email sign-in isn't set up on the server yet "
          '(email-auth function not deployed).',
      401 => 'Email sign-in is misconfigured: turn off "Verify JWT" for the '
          'email-auth function in Supabase.',
      _ => 'Something went wrong. Please try again.',
    };
  }

  static String _googleMessage(GoogleSignInException e) => switch (e.code) {
        GoogleSignInExceptionCode.clientConfigurationError ||
        GoogleSignInExceptionCode.providerConfigurationError =>
          'Google sign-in isn\'t set up correctly for this app yet. Check the '
              'SHA-1 fingerprint and that Google is enabled in Firebase.',
        GoogleSignInExceptionCode.uiUnavailable =>
          'Google sign-in couldn\'t open on this device.',
        _ => 'Google sign-in failed. Please try again.',
      };
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

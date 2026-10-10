import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'prefs_store.dart';

/// Everything a guest accumulated before signing in, packaged so it can be
/// attached to their account the moment one exists.
///
/// The rule: **a user must never lose work by signing in.** Someone who spent
/// ten minutes setting their market, language and searches should find all of
/// it there afterwards — not a reset app that behaves like they just installed
/// it.
///
/// ## How it flows
///
/// 1. Guest uses the app. `AppState` writes to [Prefs] as they go.
/// 2. They sign in. [GuestMigration.capture] snapshots the local state and
///    parks it in [Prefs] as a *pending* payload.
/// 3. [GuestMigration.flush] pushes it to the backend and clears the pending
///    flag on success.
///
/// Step 3 is deliberately separate from step 2 so a failed upload doesn't lose
/// the data — the payload survives in local storage and is retried on the next
/// launch. That matters on the connections this app is aimed at.
///
/// Right now `flush` has nowhere to send it, so it logs and leaves the payload
/// parked. When the `profiles` table exists, fill in [_upload] — nothing else
/// changes.
@immutable
class GuestMigration {
  final String? market;
  final String? language;
  final String? currency;
  final String? detectedCity;
  final String? detectedCountry;
  final List<String> recentSearches;
  final bool pushEnabled;
  final bool emailEnabled;
  final bool smsEnabled;
  final List<String> notifTopics;

  /// When the snapshot was taken, so a stale payload can be judged on the
  /// server rather than silently overwriting newer settings from another
  /// device.
  final String capturedAt;

  const GuestMigration({
    this.market,
    this.language,
    this.currency,
    this.detectedCity,
    this.detectedCountry,
    this.recentSearches = const [],
    this.pushEnabled = true,
    this.emailEnabled = true,
    this.smsEnabled = false,
    this.notifTopics = const [],
    required this.capturedAt,
  });

  Map<String, dynamic> toJson() => {
        'market': market,
        'language': language,
        'currency': currency,
        'detected_city': detectedCity,
        'detected_country': detectedCountry,
        'recent_searches': recentSearches,
        'notif_push': pushEnabled,
        'notif_email': emailEnabled,
        'notif_sms': smsEnabled,
        'notif_topics': notifTopics,
        'captured_at': capturedAt,
      };

  factory GuestMigration.fromJson(Map<String, dynamic> json) => GuestMigration(
        market: json['market'] as String?,
        language: json['language'] as String?,
        currency: json['currency'] as String?,
        detectedCity: json['detected_city'] as String?,
        detectedCountry: json['detected_country'] as String?,
        recentSearches:
            (json['recent_searches'] as List?)?.cast<String>() ?? const [],
        pushEnabled: json['notif_push'] as bool? ?? true,
        emailEnabled: json['notif_email'] as bool? ?? true,
        smsEnabled: json['notif_sms'] as bool? ?? false,
        notifTopics:
            (json['notif_topics'] as List?)?.cast<String>() ?? const [],
        capturedAt: json['captured_at'] as String? ??
            DateTime.now().toUtc().toIso8601String(),
      );

  /// Snapshots current local state and parks it as pending.
  ///
  /// Call this the moment sign-in succeeds, before anything server-side has a
  /// chance to overwrite local settings.
  static Future<void> capture() async {
    if (!Prefs.isReady) return;
    final prefs = Prefs.instance;

    final payload = GuestMigration(
      market: prefs.market,
      language: prefs.language,
      currency: prefs.currencyOverride,
      detectedCity: prefs.detectedCity,
      detectedCountry: prefs.detectedCountry,
      recentSearches: prefs.recentSearches,
      pushEnabled: prefs.pushEnabled,
      emailEnabled: prefs.emailEnabled,
      smsEnabled: prefs.smsEnabled,
      notifTopics: prefs.notifTopics,
      capturedAt: DateTime.now().toUtc().toIso8601String(),
    );

    await prefs.setPendingMigration(payload.toJson());
    debugPrint('GuestMigration: captured ${payload.toJson()}');
  }

  /// Pushes any pending payload to the backend, then clears it.
  ///
  /// Safe to call on every launch and after every sign-in — it no-ops when
  /// there's nothing pending. Failure is silent by design: the payload stays
  /// parked and the next launch retries.
  static Future<void> flush() async {
    if (!Prefs.isReady) return;
    final prefs = Prefs.instance;
    final raw = prefs.pendingMigration;
    if (raw == null) return;

    try {
      await _upload(GuestMigration.fromJson(raw));
      await prefs.setPendingMigration(null);
      debugPrint('GuestMigration: flushed');
    } catch (error) {
      // Keep the payload. Retried next launch.
      debugPrint('GuestMigration: flush failed, will retry — $error');
    }
  }

  /// Writes the snapshot onto the signed-in user's Firestore record, under
  /// `users/{uid}.guestState`.
  ///
  /// Throws when nobody is signed in, so [flush] keeps the payload and retries
  /// next launch. With Firebase not configured (iOS/web for now) there is
  /// nowhere to send it, so it's treated as done rather than retried forever.
  ///
  /// Saved listings are **not** in this payload: saving already requires a
  /// signed-in account (see `SignInPrompt.gate`), so a guest can't accumulate
  /// any. If that rule ever changes, add them here and merge server-side rather
  /// than replacing.
  static Future<void> _upload(GuestMigration payload) async {
    if (Firebase.apps.isEmpty) {
      debugPrint('GuestMigration: Firebase not configured, payload dropped');
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('not signed in');
    await FirebaseFirestore.instance.collection('users').doc(uid).set(
      {'guestState': payload.toJson()},
      SetOptions(merge: true),
    ).timeout(const Duration(seconds: 10));
  }
}

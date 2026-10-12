import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';

/// Keeps `presence/{uid}` up to date so others see "Online now" or
/// "Last seen …".
///
/// * App open (foreground) → online, with a check-in every minute.
/// * App in background / closed / signed out → offline + last seen.
///
/// A phone that dies without saying goodbye stops counting as online after
/// ~2.5 minutes without a check-in (see `Presence.isOnline`).
class PresenceService with WidgetsBindingObserver {
  PresenceService._();
  static final PresenceService instance = PresenceService._();

  String? _uid;
  Timer? _heartbeat;
  bool _observing = false;
  bool _foreground = true;

  /// Call whenever the signed-in user may have changed (null = signed out).
  void follow(String? uid) {
    if (uid == _uid) return;
    final previous = _uid;
    if (previous != null) _write(previous, online: false);
    _uid = uid;
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    _restart();
  }

  void _restart() {
    _heartbeat?.cancel();
    final uid = _uid;
    if (uid == null || !_foreground) return;
    _write(uid, online: true);
    _heartbeat = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _write(uid, online: true),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final uid = _uid;
    switch (state) {
      case AppLifecycleState.resumed:
        _foreground = true;
        _restart();
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        if (!_foreground) return;
        _foreground = false;
        _heartbeat?.cancel();
        if (uid != null) _write(uid, online: false);
      case AppLifecycleState.inactive:
        break;
    }
  }

  void _write(String uid, {required bool online}) {
    try {
      FirebaseFirestore.instance.collection('presence').doc(uid).set({
        'online': online,
        'lastSeen': FieldValue.serverTimestamp(),
      }).catchError((Object e) {
        debugPrint('Presence write failed: $e');
      });
    } catch (e) {
      debugPrint('Presence unavailable: $e');
    }
  }
}

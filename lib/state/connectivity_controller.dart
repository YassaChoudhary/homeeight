import 'dart:async';

import 'package:flutter/widgets.dart';

import 'net_probe.dart';

/// Watches whether the device can reach the internet.
///
/// ## Why it debounces before declaring "offline"
///
/// Mobile networks blip constantly — a handover between cells, a lift, a Wi-Fi
/// roam. If a single failed probe threw up a full-screen takeover, the app would
/// flash the offline screen several times an hour on a perfectly usable
/// connection, which is far more annoying than a two-second delay in noticing a
/// real outage. So it takes [_failuresToGoOffline] consecutive failures to go
/// offline, but only **one** success to come back — being slow to recover is the
/// worse error.
///
/// ## Why polling, and why the interval changes
///
/// There's no dependency here, so there's no OS connectivity stream to
/// subscribe to; polling is the only option. Once offline it polls faster
/// ([_offlineInterval]) so recovery feels immediate, and while online it polls
/// slowly ([_onlineInterval]) to stay off the battery. Polling also pauses
/// entirely while the app is backgrounded — see [didChangeAppLifecycleState] —
/// because probing from the background wakes the radio for nothing, and the
/// state is rechecked on resume anyway.
///
/// A `ValueNotifier<bool>` rather than a `ChangeNotifier` with fields, so the
/// offline gate rebuilds on the one value it cares about.
class ConnectivityController extends ValueNotifier<bool>
    with WidgetsBindingObserver {
  static const Duration _onlineInterval = Duration(seconds: 8);
  static const Duration _offlineInterval = Duration(seconds: 3);
  static const int _failuresToGoOffline = 2;

  Timer? _timer;
  int _consecutiveFailures = 0;
  bool _checking = false;
  bool _disposed = false;

  /// True until the first probe returns, so the app doesn't flash the offline
  /// screen during startup before anything has actually been measured.
  bool _hasResult = false;
  bool get hasResult => _hasResult;

  /// Starts optimistic. An app that assumes offline until proven otherwise
  /// shows a scary screen to every user for the first second.
  ConnectivityController() : super(true) {
    WidgetsBinding.instance.addObserver(this);
    _schedule();
    check();
  }

  bool get isOnline => value;

  void _schedule() {
    _timer?.cancel();
    if (_disposed) return;
    _timer = Timer.periodic(
      value ? _onlineInterval : _offlineInterval,
      (_) => check(),
    );
  }

  /// Runs a probe now. Safe to call from a retry button or after a failed
  /// request — overlapping calls collapse into one.
  Future<void> check() async {
    if (_checking || _disposed) return;
    _checking = true;
    try {
      final reachable = await probeInternet();
      if (_disposed) return;

      _hasResult = true;

      if (reachable) {
        _consecutiveFailures = 0;
        _set(true);
      } else {
        _consecutiveFailures++;
        if (_consecutiveFailures >= _failuresToGoOffline) _set(false);
      }
    } finally {
      _checking = false;
    }
  }

  /// Call from the repository layer when a request fails, so a real outage is
  /// noticed on the failed request rather than up to [_onlineInterval] later.
  ///
  /// This does **not** assume offline — a 500 from a healthy server is not a
  /// connectivity problem. It only triggers an early probe.
  void reportRequestFailure() {
    if (!value) return;
    check();
  }

  void _set(bool online) {
    if (value == online) return;
    value = online;
    // Interval depends on the state, so re-arm whenever it flips.
    _schedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        // Connectivity very often changed while we were away.
        _schedule();
        check();
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _timer?.cancel();
      case AppLifecycleState.inactive:
        break;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

/// Makes [ConnectivityController] available below it.
///
/// Separate from `AppScope` on purpose: this changes on its own schedule and has
/// nothing to do with session or market state, and keeping it out means
/// `AppScope` doesn't gain a field that every screen would rebuild on.
///
/// `InheritedNotifier` handles the subscription, so
/// `ConnectivityScope.isOnline(context)` both reads and subscribes.
class ConnectivityScope extends InheritedNotifier<ConnectivityController> {
  const ConnectivityScope({
    super.key,
    required ConnectivityController controller,
    required super.child,
  }) : super(notifier: controller);

  /// Reads and subscribes. Use in `build` to react to going offline.
  static bool isOnline(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<ConnectivityScope>();
    return scope?.notifier?.value ?? true;
  }

  /// Reads without subscribing. Use in callbacks — e.g. a retry button.
  static ConnectivityController? maybeOf(BuildContext context) {
    return context
        .getInheritedWidgetOfExactType<ConnectivityScope>()
        ?.notifier;
  }
}

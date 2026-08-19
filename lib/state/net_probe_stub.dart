/// Web stub.
///
/// Browsers don't allow raw sockets. Reporting "online" unconditionally is the
/// safe default: a false offline overlay would block a working app, which is
/// worse than missing an offline state. For real web support, read
/// `navigator.onLine` and the `online`/`offline` window events through
/// `package:web`, or add `connectivity_plus`, which covers both.
Future<bool> probeInternet({
  Duration timeout = const Duration(seconds: 3),
}) async =>
    true;

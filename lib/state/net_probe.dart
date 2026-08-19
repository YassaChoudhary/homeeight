/// Platform-specific reachability probe.
///
/// A raw socket is the cheapest honest test of "is there internet", but
/// `dart:io` doesn't exist on web — importing it unconditionally breaks
/// `flutter build web`. This conditional export picks the socket implementation
/// on mobile/desktop and a stub on web, so both targets still compile.
export 'net_probe_io.dart'
    if (dart.library.js_interop) 'net_probe_stub.dart';

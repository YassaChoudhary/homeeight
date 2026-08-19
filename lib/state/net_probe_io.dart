import 'dart:io';

/// True when a TCP connection to a public DNS resolver succeeds.
///
/// Why a socket rather than an HTTP GET: no HTTP client is in the dependency
/// list, and a socket to port 53 is a few bytes with no DNS lookup of its own —
/// so it can't be fooled by a cached DNS answer the way `InternetAddress.lookup`
/// can. Two resolvers are tried because captive portals and some corporate
/// networks block one but not the other.
///
/// Note this reports *reachability*, not whether your API is up. A captive
/// portal that accepts TCP on 53 will read as online. That's the trade-off for
/// having no networking dependency; once `ApiListingRepository` exists, prefer
/// probing your own health endpoint and let this be the fallback.
Future<bool> probeInternet({
  Duration timeout = const Duration(seconds: 3),
}) async {
  const hosts = [
    ('1.1.1.1', 53),
    ('8.8.8.8', 53),
  ];

  for (final (host, port) in hosts) {
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      socket.destroy();
      return true;
    } on SocketException {
      continue;
    } on Object {
      // Anything else (platform restrictions, sandboxing) is inconclusive —
      // treat as unreachable and let the next host decide.
      continue;
    }
  }
  return false;
}

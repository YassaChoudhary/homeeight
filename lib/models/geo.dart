import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// A latitude/longitude pair. The app's own type, so no screen or model
/// imports the map SDK — only `widgets/home8_map.dart` does.
@immutable
class GeoPoint {
  final double lat;
  final double lng;

  const GeoPoint(this.lat, this.lng);

  @override
  bool operator ==(Object other) =>
      other is GeoPoint && other.lat == lat && other.lng == lng;

  @override
  int get hashCode => Object.hash(lat, lng);

  @override
  String toString() => 'GeoPoint($lat, $lng)';
}

/// A rectangle on the map: what's on screen, or an area the user picked.
/// Sent to search as min/max lat/lng (see `search_listings` in SQL).
@immutable
class GeoBounds {
  final GeoPoint southwest;
  final GeoPoint northeast;

  const GeoBounds(this.southwest, this.northeast);

  double get minLat => math.min(southwest.lat, northeast.lat);
  double get maxLat => math.max(southwest.lat, northeast.lat);
  double get minLng => math.min(southwest.lng, northeast.lng);
  double get maxLng => math.max(southwest.lng, northeast.lng);

  GeoPoint get center =>
      GeoPoint((minLat + maxLat) / 2, (minLng + maxLng) / 2);

  bool contains(GeoPoint p) =>
      p.lat >= minLat && p.lat <= maxLat && p.lng >= minLng && p.lng <= maxLng;

  @override
  bool operator ==(Object other) =>
      other is GeoBounds &&
      other.southwest == southwest &&
      other.northeast == northeast;

  @override
  int get hashCode => Object.hash(southwest, northeast);
}

/// Default map centre per market (ISO country code), used when there is no
/// listing or device location to centre on.
GeoPoint marketCenter(String countryCode) => switch (countryCode) {
      'AE' => const GeoPoint(25.1972, 55.2744), // Dubai
      'SA' => const GeoPoint(24.7136, 46.6753), // Riyadh
      'QA' => const GeoPoint(25.2854, 51.5310), // Doha
      'PK' => const GeoPoint(24.8607, 67.0011), // Karachi
      'GB' => const GeoPoint(51.5072, -0.1276), // London
      'US' => const GeoPoint(40.7128, -74.0060), // New York
      'CA' => const GeoPoint(43.6532, -79.3832), // Toronto
      'AU' => const GeoPoint(-33.8688, 151.2093), // Sydney
      'NZ' => const GeoPoint(-36.8485, 174.7633), // Auckland
      _ => const GeoPoint(25.1972, 55.2744),
    };

/// Where a listing is shown to buyers: a point near, but not exactly at, the
/// real address.
///
/// The posting flow promises owners that "buyers see the community only — the
/// exact pin is revealed after you accept an enquiry". So every buyer-facing
/// map uses this instead of the real coordinates: the same listing always
/// lands on the same nearby spot (the offset comes from its id), between
/// roughly 120 and 280 metres away in some direction.
GeoPoint approximateLocation(String listingId, GeoPoint exact) {
  // Stable per-listing pseudo-random numbers from the id (FNV-1a hash).
  var hash = 0x811C9DC5;
  for (final unit in listingId.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  final angle = (hash & 0xFFFF) / 0xFFFF * 2 * math.pi;
  final distanceM = 120 + ((hash >> 16) & 0xFF) / 0xFF * 160;
  const metresPerDegLat = 111320.0;
  final metresPerDegLng = metresPerDegLat * math.cos(exact.lat * math.pi / 180);
  return GeoPoint(
    exact.lat + distanceM * math.sin(angle) / metresPerDegLat,
    exact.lng + distanceM * math.cos(angle) / metresPerDegLng,
  );
}

/// A circle of [radiusM] metres around [center], as a closed ring of points —
/// drawn as the "approximate area" shade on the property map.
List<GeoPoint> circleRing(GeoPoint center, double radiusM, {int steps = 48}) {
  const metresPerDegLat = 111320.0;
  final metresPerDegLng = metresPerDegLat * math.cos(center.lat * math.pi / 180);
  return [
    for (var i = 0; i <= steps; i++)
      GeoPoint(
        center.lat + radiusM * math.sin(2 * math.pi * i / steps) / metresPerDegLat,
        center.lng + radiusM * math.cos(2 * math.pi * i / steps) / metresPerDegLng,
      ),
  ];
}

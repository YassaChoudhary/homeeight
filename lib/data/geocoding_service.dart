import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/env.dart';
import '../models/geo.dart';

/// One place from the geocoder: an address, street, area or city.
@immutable
class PlaceSuggestion {
  /// Short name: "Marina Gate 1" or "Al Sufouh Road".
  final String name;

  /// Everything after the name: "Dubai Marina, Dubai, United Arab Emirates".
  final String context;

  /// Neighbourhood or locality — what buyers see as the community.
  final String community;

  /// City ("Dubai").
  final String city;

  final GeoPoint point;

  const PlaceSuggestion({
    required this.name,
    required this.context,
    required this.community,
    required this.city,
    required this.point,
  });

  /// "Marina Gate 1, Dubai Marina, Dubai" — the form the address field uses.
  String get addressLine {
    final parts = <String>[
      name,
      if (community.isNotEmpty && community != name) community,
      if (city.isNotEmpty && city != name && city != community) city,
    ];
    return parts.join(', ');
  }

  static PlaceSuggestion? fromFeature(Map<String, dynamic> feature) {
    final props = feature['properties'];
    if (props is! Map<String, dynamic>) return null;
    final coords = props['coordinates'];
    double? lat, lng;
    if (coords is Map<String, dynamic>) {
      lat = (coords['latitude'] as num?)?.toDouble();
      lng = (coords['longitude'] as num?)?.toDouble();
    }
    // Fallback: GeoJSON geometry is [lng, lat].
    final geometry = feature['geometry'];
    if ((lat == null || lng == null) && geometry is Map<String, dynamic>) {
      final c = geometry['coordinates'];
      if (c is List && c.length >= 2) {
        lng = (c[0] as num).toDouble();
        lat = (c[1] as num).toDouble();
      }
    }
    if (lat == null || lng == null) return null;

    String ctxName(String key) {
      final ctx = props['context'];
      if (ctx is! Map<String, dynamic>) return '';
      final entry = ctx[key];
      if (entry is! Map<String, dynamic>) return '';
      return (entry['name'] as String?) ?? '';
    }

    final neighborhood = ctxName('neighborhood');
    final locality = ctxName('locality');
    return PlaceSuggestion(
      name: (props['name'] as String?) ?? '',
      context: (props['place_formatted'] as String?) ?? '',
      community: neighborhood.isNotEmpty ? neighborhood : locality,
      city: ctxName('place'),
      point: GeoPoint(lat, lng),
    );
  }
}

/// Address lookups through the Mapbox Geocoding API (v6).
///
/// Free tier: 100,000 requests a month on the same public token as the map —
/// no card needed. Used only by the seller's location picker:
///
/// * [reverse] — the pin stopped here; what's the address?
/// * [search]  — the seller typed an address; where is it?
///
/// Every failure (no token, offline, quota) returns null / an empty list —
/// the picker still works, the seller just types the address.
///
/// Note: Mapbox's free geocoding is for showing results, not building a
/// database from them. We store the **pin the seller placed** and the
/// **address text the seller confirmed**, which is fine.
class GeocodingService {
  GeocodingService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _base = 'https://api.mapbox.com/search/geocode/v6';
  static const _timeout = Duration(seconds: 8);

  Future<PlaceSuggestion?> reverse(GeoPoint point, {String? language}) async {
    if (!Env.hasMapbox) return null;
    final uri = Uri.parse('$_base/reverse').replace(queryParameters: {
      'longitude': point.lng.toStringAsFixed(6),
      'latitude': point.lat.toStringAsFixed(6),
      'types': 'address,street,neighborhood,locality,place',
      'limit': '1',
      if (language != null) 'language': language,
      'access_token': Env.mapboxToken,
    });
    final features = await _get(uri);
    return features.isEmpty ? null : PlaceSuggestion.fromFeature(features.first);
  }

  Future<List<PlaceSuggestion>> search(
    String query, {
    String? countryCode,
    GeoPoint? near,
    String? language,
  }) async {
    final q = query.trim();
    if (!Env.hasMapbox || q.length < 3) return const [];
    final uri = Uri.parse('$_base/forward').replace(queryParameters: {
      'q': q,
      'limit': '5',
      'autocomplete': 'true',
      if (countryCode != null && countryCode.isNotEmpty)
        'country': countryCode.toLowerCase(),
      if (near != null)
        'proximity':
            '${near.lng.toStringAsFixed(5)},${near.lat.toStringAsFixed(5)}',
      if (language != null) 'language': language,
      'access_token': Env.mapboxToken,
    });
    final features = await _get(uri);
    return features
        .map(PlaceSuggestion.fromFeature)
        .whereType<PlaceSuggestion>()
        .toList();
  }

  Future<List<Map<String, dynamic>>> _get(Uri uri) async {
    try {
      final res = await _client.get(uri).timeout(_timeout);
      if (res.statusCode != 200) {
        debugPrint('Geocoding ${res.statusCode}: ${res.body}');
        return const [];
      }
      final body = jsonDecode(res.body);
      final features = body is Map<String, dynamic> ? body['features'] : null;
      if (features is! List) return const [];
      return features.whereType<Map<String, dynamic>>().toList();
    } catch (e) {
      debugPrint('Geocoding failed: $e');
      return const [];
    }
  }
}

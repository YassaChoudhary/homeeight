import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

/// Where the device is, resolved to a city and country.
@immutable
class DetectedPlace {
  /// Human-readable city, e.g. "Karachi", "Dubai".
  final String city;

  /// ISO country code, e.g. "PK", "AE". Used to pick the market.
  final String countryCode;

  final double latitude;
  final double longitude;

  const DetectedPlace({
    required this.city,
    required this.countryCode,
    required this.latitude,
    required this.longitude,
  });
}

enum LocationOutcome {
  /// Got a position and resolved a city.
  resolved,

  /// User said no. Not an error — the app carries on with the chosen market.
  denied,

  /// User said "never ask again". Only Settings can undo this.
  deniedForever,

  /// Location services switched off at the OS level.
  serviceDisabled,

  /// Permission was fine but the lookup failed (no signal, geocoder down).
  failed,
}

@immutable
class LocationResult {
  final LocationOutcome outcome;
  final DetectedPlace? place;

  const LocationResult(this.outcome, [this.place]);

  bool get granted =>
      outcome == LocationOutcome.resolved || outcome == LocationOutcome.failed;
}

/// Thin wrapper over `geolocator` + `geocoding`.
///
/// Kept behind its own class so screens never touch the plugins directly — the
/// same reason data goes through `ListingRepository`. It also means location
/// can be faked in tests and on desktop, where the plugins aren't available.
class LocationService {
  const LocationService();

  /// Asks for permission if needed, then resolves the city.
  ///
  /// Never throws. Every failure path is a [LocationOutcome] the caller can
  /// render, because a location lookup failing must never block the user from
  /// reaching the app.
  Future<LocationResult> requestAndResolve() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationResult(LocationOutcome.serviceDisabled);
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        return const LocationResult(LocationOutcome.deniedForever);
      }
      if (permission == LocationPermission.denied) {
        return const LocationResult(LocationOutcome.denied);
      }

      // Medium accuracy is plenty for "which city are you in" and is much
      // faster and cheaper on battery than best-accuracy GPS.
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 12),
        ),
      );

      final place = await _resolve(position.latitude, position.longitude);
      if (place == null) return const LocationResult(LocationOutcome.failed);
      return LocationResult(LocationOutcome.resolved, place);
    } catch (error) {
      debugPrint('LocationService failed: $error');
      return const LocationResult(LocationOutcome.failed);
    }
  }

  /// Resolves without prompting. Use on later launches when permission was
  /// already granted, so the city refreshes without a dialog.
  Future<LocationResult> resolveIfPermitted() async {
    try {
      final permission = await Geolocator.checkPermission();
      final allowed = permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
      if (!allowed) return const LocationResult(LocationOutcome.denied);
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationResult(LocationOutcome.serviceDisabled);
      }
      return requestAndResolve();
    } catch (_) {
      return const LocationResult(LocationOutcome.failed);
    }
  }

  Future<DetectedPlace?> _resolve(double lat, double lng) async {
    try {
      final marks = await placemarkFromCoordinates(lat, lng);
      if (marks.isEmpty) return null;
      final m = marks.first;

      // `locality` is the city on most devices, but it comes back empty in
      // parts of the GCC and South Asia — fall back through the wider
      // administrative names rather than showing a blank chip.
      final city = [
        m.locality,
        m.subAdministrativeArea,
        m.administrativeArea,
        m.country,
      ].firstWhere(
        (v) => v != null && v.trim().isNotEmpty,
        orElse: () => null,
      );

      if (city == null) return null;

      return DetectedPlace(
        city: city.trim(),
        countryCode: (m.isoCountryCode ?? '').toUpperCase(),
        latitude: lat,
        longitude: lng,
      );
    } catch (error) {
      debugPrint('Reverse geocode failed: $error');
      return null;
    }
  }

  /// Opens the OS settings page, for the "denied forever" case.
  Future<void> openSettings() => Geolocator.openAppSettings();
}

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:showtime_core/showtime_core.dart';

/// Why the location couldn't be used; shown to the user.
class LocationUnavailable implements Exception {
  const LocationUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Turns the phone's location into place names (city, district, state),
/// most specific first. Behind an interface for tests.
abstract interface class LocationGateway {
  Future<List<String>> placeNames();
}

/// geolocator (coarse fix) + the platform geocoder. The location is used
/// only to pick a city; it is never sent to the listings site (NFR-5).
class DeviceLocation implements LocationGateway {
  const DeviceLocation();

  @override
  Future<List<String>> placeNames() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationUnavailable('Location is turned off on this phone.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const LocationUnavailable('Location permission was not given.');
    }
    final Position pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 20),
        ),
      );
    } catch (_) {
      final last = await Geolocator.getLastKnownPosition();
      if (last == null) {
        throw const LocationUnavailable("Couldn't get a location fix.");
      }
      return _names(last.latitude, last.longitude);
    }
    return _names(pos.latitude, pos.longitude);
  }

  Future<List<String>> _names(double lat, double lon) async {
    final List<Placemark> marks;
    try {
      // English names so they match the listings' city keys.
      marks = await Geocoding(
        locale: const Locale('en', 'IN'),
      ).placemarkFromCoordinates(lat, lon);
    } catch (_) {
      throw const LocationUnavailable(
        "Couldn't look up your city (the phone's geocoder needs internet).",
      );
    }
    return [
      for (final m in marks) ...[
        ?m.locality,
        ?m.subAdministrativeArea,
        ?m.subLocality,
        ?m.administrativeArea,
      ],
    ].where((n) => n.trim().isNotEmpty).toList();
  }
}

final locationGatewayProvider = Provider<LocationGateway>(
  (ref) => const DeviceLocation(),
);

/// Matches geocoder place names to the source's city keys. Pure.
abstract final class CityMatcher {
  /// Geocoder name (normalised) -> the key the listings site uses.
  static const aliases = {
    'bangalore': 'bengaluru',
    'bengaluru-urban': 'bengaluru',
    'bangalore-urban': 'bengaluru',
    'gurugram': 'gurgaon',
    'delhi': 'new-delhi',
    'new-delhi': 'new-delhi',
    'central-delhi': 'new-delhi',
    'south-delhi': 'new-delhi',
    'visakhapatnam': 'vizag',
    'mangaluru': 'mangalore',
    'dakshina-kannada': 'mangalore',
    'prayagraj': 'allahabad',
    'thiruvananthapuram': 'trivandrum',
    'cochin': 'kochi',
    'ernakulam': 'kochi',
    'mysore': 'mysuru',
    'pondicherry': 'puducherry',
    'calcutta': 'kolkata',
    'bombay': 'mumbai',
    'mumbai-suburban': 'mumbai',
    'madras': 'chennai',
    'calicut': 'kozhikode',
    'baroda': 'vadodara',
    'secunderabad': 'hyderabad',
    'gautam-buddh-nagar': 'noida',
  };

  static String normalise(String name) => name
      .toLowerCase()
      .replaceAll(RegExp(r'\b(district|city|division)\b'), '')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  /// First of [names] (most specific first) that maps to a known city.
  static City? match(List<City> cities, List<String> names) {
    final byKey = {for (final c in cities) c.key: c};
    for (final raw in names) {
      final n = normalise(raw);
      if (n.isEmpty) continue;
      final hit = byKey[n] ?? byKey[aliases[n] ?? ''];
      if (hit != null) return hit;
    }
    return null;
  }
}

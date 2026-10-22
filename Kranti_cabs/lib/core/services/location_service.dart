import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

class LocationPermissionResult {
  final bool granted;
  final bool serviceEnabled;
  final bool permanentlyDenied;

  LocationPermissionResult({
    required this.granted,
    required this.serviceEnabled,
    required this.permanentlyDenied,
  });
}

enum LocationIssue { none, gpsOff, permissionDenied }

class LocationService {
  // ~50m Grid Memory Cache & Throttling/Skip State
  final Map<String, String> _gridCache = {};
  double? _lastGeocodedLat;
  double? _lastGeocodedLng;
  String? _lastGeocodedAddress;
  DateTime? _lastGeocodeTime;

  // The placemark lookup below already resolves these on every real geocode;
  // they were previously discarded after being joined into the flattened
  // address string. Exposed read-only so a caller (destination search
  // ranking) can get "current locality/city" for free — no extra geocode
  // call of its own, just whatever the last real lookup already found. Stay
  // set from the last real lookup while the <50m/3s skips above are in
  // effect, which is correct: those skips mean the device hasn't moved far
  // enough for the locality to plausibly have changed either.
  String? _lastGeocodedLocality;
  String? _lastGeocodedCity;

  /// The rider's current neighbourhood/area (e.g. "Vijay Nagar"), from the
  /// most recent reverse-geocode. Null until the first lookup completes.
  String? get lastKnownLocality => _lastGeocodedLocality;

  /// The rider's current city (e.g. "Indore"), from the most recent
  /// reverse-geocode. Null until the first lookup completes.
  String? get lastKnownCity => _lastGeocodedCity;

  /// Where location stands right now, without asking the rider anything.
  ///
  /// [ensurePermission] shows the system dialog when permission is undecided,
  /// which is right on a screen the rider opened but wrong every time the app
  /// returns to the foreground. This only reads the state, so it can be
  /// checked as often as needed.
  Future<LocationPermissionResult> checkStatus() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    final permission = await Geolocator.checkPermission();
    final granted =
        permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;

    return LocationPermissionResult(
      granted: granted && serviceEnabled,
      serviceEnabled: serviceEnabled,
      permanentlyDenied: permission == LocationPermission.deniedForever,
    );
  }

  Future<LocationPermissionResult> ensurePermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return LocationPermissionResult(
        granted: false,
        serviceEnabled: false,
        permanentlyDenied: false,
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      return LocationPermissionResult(
        granted: false,
        serviceEnabled: true,
        permanentlyDenied: true,
      );
    }

    final granted =
        permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;

    return LocationPermissionResult(
      granted: granted,
      serviceEnabled: true,
      permanentlyDenied: false,
    );
  }

  /// A GPS fix, waiting at most 10 seconds for it.
  ///
  /// Without a limit the request can wait forever - indoors, or on a slow first
  /// fix - and every screen waiting on it sits on "Fetching location...". On
  /// timeout the last known position is used; only if there is none does this
  /// throw, so callers keep their existing "no location" handling.
  Future<Position> getCurrentPosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } on TimeoutException {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) return lastKnown;
      rethrow;
    }
  }

  /// Why there is no location right now, without asking for anything: GPS
  /// switched off, permission refused, or neither (a fix just hasn't arrived).
  Future<LocationIssue> diagnose() async {
    if (!await Geolocator.isLocationServiceEnabled()) return LocationIssue.gpsOff;

    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return LocationIssue.permissionDenied;
    }
    return LocationIssue.none;
  }

  // 1) GPS stream pe geocode mat chalao - Returns raw positions only
  Stream<Position> watchPosition() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 20,
      ),
    );
  }

  double distanceMeters(double lat1, double lng1, double lat2, double lng2) {
    return Geolocator.distanceBetween(lat1, lng1, lat2, lng2);
  }

  String _gridKey(double lat, double lng) {
    // 2000 units per degree yields ~55m grid resolution
    final latGrid = (lat * 2000).round();
    final lngGrid = (lng * 2000).round();
    return '${latGrid}_$lngGrid';
  }

  Future<String> getAddressFromCoordinates(double lat, double lng) async {
    // 5) ~50m grid memory cache
    final key = _gridKey(lat, lng);
    if (_gridCache.containsKey(key)) {
      return _gridCache[key]!;
    }

    // 3) <50m move skip
    if (_lastGeocodedLat != null &&
        _lastGeocodedLng != null &&
        _lastGeocodedAddress != null &&
        _lastGeocodedAddress!.isNotEmpty) {
      final distance = distanceMeters(
        lat,
        lng,
        _lastGeocodedLat!,
        _lastGeocodedLng!,
      );
      if (distance < 50) {
        _gridCache[key] = _lastGeocodedAddress!;
        return _lastGeocodedAddress!;
      }
    }

    // 4) 3s throttle
    if (_lastGeocodeTime != null &&
        _lastGeocodedAddress != null &&
        _lastGeocodedAddress!.isNotEmpty) {
      final elapsed = DateTime.now().difference(_lastGeocodeTime!);
      if (elapsed.inSeconds < 3) {
        return _lastGeocodedAddress!;
      }
    }

    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final parts = [
          p.name,
          p.subLocality,
          p.locality,
        ].where((e) => e != null && e.isNotEmpty).toSet();
        final addr = parts.join(', ');

        if (addr.isNotEmpty) {
          _lastGeocodedLat = lat;
          _lastGeocodedLng = lng;
          _lastGeocodedAddress = addr;
          _lastGeocodeTime = DateTime.now();
          _gridCache[key] = addr;
          // subLocality is the neighbourhood/area ("Vijay Nagar"), locality
          // is the city ("Indore") — matches the Placemark package's actual
          // field semantics here, not their generic names.
          if ((p.subLocality ?? '').isNotEmpty) {
            _lastGeocodedLocality = p.subLocality;
          }
          if ((p.locality ?? '').isNotEmpty) {
            _lastGeocodedCity = p.locality;
          }
          return addr;
        }
      }
    } catch (_) {}

    return _lastGeocodedAddress ?? '';
  }
}

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

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

class LocationService {
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

    final granted = permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;

    return LocationPermissionResult(
      granted: granted,
      serviceEnabled: true,
      permanentlyDenied: false,
    );
  }

  Future<bool> isServiceEnabled() => Geolocator.isLocationServiceEnabled();

  Future<Position> getCurrentPosition() {
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );
  }

  Stream<Position> watchPosition({
    int distanceFilterMeters = 10,
    bool keepAliveInBackground = false,
  }) {
    return Geolocator.getPositionStream(
      locationSettings: streamSettings(
        distanceFilterMeters: distanceFilterMeters,
        keepAliveInBackground: keepAliveInBackground,
      ),
    );
  }

  /// Settings for [watchPosition].
  ///
  /// With [keepAliveInBackground], updates keep flowing after the driver leaves
  /// the app, which happens on every trip because navigation opens Google Maps.
  /// Without it both platforms stop delivering fixes as soon as the app is
  /// backgrounded, and the rider watches a car that has stopped moving.
  ///
  /// - Android runs geolocator's location foreground service. The ongoing
  ///   notification is what Android asks for in return, and a service started
  ///   while the app is on screen keeps running on while-in-use permission, so
  ///   no background-location permission is needed.
  /// - iOS keeps updating under the `location` background mode in Info.plist
  ///   and shows the blue location pill, which is what lets while-in-use
  ///   authorisation carry on in the background.
  ///
  /// Android 12+ refuses to start a location foreground service from the
  /// background, so only open a background stream while the app is visible.
  @visibleForTesting
  static LocationSettings streamSettings({
    required int distanceFilterMeters,
    required bool keepAliveInBackground,
    TargetPlatform? platform,
    bool isWeb = kIsWeb,
  }) {
    if (keepAliveInBackground && !isWeb) {
      switch (platform ?? defaultTargetPlatform) {
        case TargetPlatform.android:
          return AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: distanceFilterMeters,
            foregroundNotificationConfig: ForegroundNotificationConfig(
              notificationTitle: 'Sharing your location',
              notificationText:
                  'KrantiCabs Rider shares your location with riders while you are online or on a trip.',
              notificationChannelName: 'Location while online',
              enableWakeLock: true,
              setOngoing: true,
            ),
          );
        case TargetPlatform.iOS:
          return AppleSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: distanceFilterMeters,
            activityType: ActivityType.automotiveNavigation,
            pauseLocationUpdatesAutomatically: false,
            showBackgroundLocationIndicator: true,
            allowBackgroundLocationUpdates: true,
          );
        default:
          break;
      }
    }

    return LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: distanceFilterMeters,
    );
  }

  Stream<ServiceStatus> watchServiceStatus() => Geolocator.getServiceStatusStream();

  double distanceMeters(double lat1, double lng1, double lat2, double lng2) {
    return Geolocator.distanceBetween(lat1, lng1, lat2, lng2);
  }

  double bearingBetween(double lat1, double lng1, double lat2, double lng2) {
    return Geolocator.bearingBetween(lat1, lng1, lat2, lng2);
  }
}

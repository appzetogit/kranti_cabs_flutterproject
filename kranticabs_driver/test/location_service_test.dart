import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterdriver/core/services/location_service.dart';
import 'package:geolocator/geolocator.dart';

void main() {
  group('LocationService.streamSettings', () {
    test('keeps Android updates alive with a location foreground service', () {
      final settings = LocationService.streamSettings(
        distanceFilterMeters: 3,
        keepAliveInBackground: true,
        platform: TargetPlatform.android,
        isWeb: false,
      );

      expect(settings, isA<AndroidSettings>());
      final android = settings as AndroidSettings;
      expect(android.distanceFilter, 3);
      expect(android.accuracy, LocationAccuracy.high);
      expect(android.foregroundNotificationConfig, isNotNull);
      expect(android.foregroundNotificationConfig!.setOngoing, isTrue);
      expect(android.foregroundNotificationConfig!.enableWakeLock, isTrue);
    });

    test('keeps iOS updates alive in the background, with the location pill', () {
      final settings = LocationService.streamSettings(
        distanceFilterMeters: 25,
        keepAliveInBackground: true,
        platform: TargetPlatform.iOS,
        isWeb: false,
      );

      expect(settings, isA<AppleSettings>());
      final apple = settings as AppleSettings;
      expect(apple.distanceFilter, 25);
      expect(apple.allowBackgroundLocationUpdates, isTrue);
      expect(apple.showBackgroundLocationIndicator, isTrue);
      expect(apple.pauseLocationUpdatesAutomatically, isFalse);
      expect(apple.activityType, ActivityType.automotiveNavigation);
    });

    test('foreground-only streams start no service on either platform', () {
      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        final settings = LocationService.streamSettings(
          distanceFilterMeters: 250,
          keepAliveInBackground: false,
          platform: platform,
          isWeb: false,
        );

        expect(settings.runtimeType, LocationSettings, reason: '$platform');
        expect(settings.distanceFilter, 250);
      }
    });

    test('web never asks for background updates', () {
      final settings = LocationService.streamSettings(
        distanceFilterMeters: 10,
        keepAliveInBackground: true,
        platform: TargetPlatform.android,
        isWeb: true,
      );

      expect(settings.runtimeType, LocationSettings);
    });
  });
}

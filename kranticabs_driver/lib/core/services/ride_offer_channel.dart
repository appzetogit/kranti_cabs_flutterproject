import 'dart:developer' as developer;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// One answer the driver gave on the native full-screen offer card.
class RideOfferAction {
  final String action;
  final String rideId;

  const RideOfferAction({required this.action, required this.rideId});

  bool get isAccept => action == 'accept';
  bool get isReject => action == 'reject';
}

/// Which of the three special permissions the full-screen card still needs.
///
/// Each is a Settings page, not a runtime dialog — see [RideOfferChannel].
class RideOfferPermissionStatus {
  final bool fullScreenIntent;
  final bool overlay;
  final bool batteryOptimizations;

  const RideOfferPermissionStatus({
    required this.fullScreenIntent,
    required this.overlay,
    required this.batteryOptimizations,
  });

  /// Assumed missing, never granted. A check that failed tells us nothing, and
  /// defaulting to granted would hide a broken channel behind a clean banner.
  static const unknown = RideOfferPermissionStatus(
    fullScreenIntent: false,
    overlay: false,
    batteryOptimizations: false,
  );

  bool get allGranted => fullScreenIntent && overlay && batteryOptimizations;

  List<String> get missingLabels => [
        if (!fullScreenIntent) 'Full-screen alerts',
        if (!overlay) 'Display over other apps',
        if (!batteryOptimizations) 'Unrestricted battery',
      ];
}

/// Talks to the native ride-offer card.
///
/// The card is posted from Kotlin and answered while the app may be killed, so
/// answers are queued natively and drained from here — see
/// [consumePendingActions].
class RideOfferChannel {
  RideOfferChannel._();

  static const MethodChannel _channel = MethodChannel(
    'com.kranticabs.delivery/app_launcher',
  );

  static bool get _supported => !kIsWeb && Platform.isAndroid;

  /// Registers [onPending], called when native has queued a new answer.
  ///
  /// The callback should drain with [consumePendingActions] rather than expect
  /// the answer itself: the queue is the only delivery path, so a nudge that
  /// arrives twice costs nothing.
  static void setPendingActionListener(Future<void> Function() onPending) {
    if (!_supported) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onRideOfferActionsPending') {
        await onPending();
      }
    });
  }

  static void clearPendingActionListener() {
    if (!_supported) return;
    _channel.setMethodCallHandler(null);
  }

  /// Returns every answer given on the card since the last drain, and clears
  /// the native queue.
  static Future<List<RideOfferAction>> consumePendingActions() async {
    if (!_supported) return const [];
    try {
      final raw = await _channel.invokeMethod<List<Object?>>(
        'consumePendingRideOfferActions',
      );
      return (raw ?? const [])
          .whereType<Map>()
          .map((entry) => RideOfferAction(
                action: entry['action']?.toString() ?? '',
                rideId: entry['rideId']?.toString() ?? '',
              ))
          .where((entry) => entry.rideId.isNotEmpty)
          .toList();
    } on PlatformException catch (error) {
      developer.log('Could not read pending ride-offer actions: $error');
      return const [];
    }
  }

  /// Hands the signed-in session to native so the offer card can decline
  /// against the server with the app closed.
  ///
  /// Without this a decline only reached the server once the driver next opened
  /// the app, and dispatch kept re-offering the same ride in the meantime.
  static Future<void> saveSession({
    required String token,
    required String apiBaseUrl,
  }) async {
    if (!_supported || token.isEmpty) return;
    try {
      await _channel.invokeMethod('setDriverSession', {
        'token': token,
        'apiBaseUrl': apiBaseUrl,
      });
    } on PlatformException catch (error) {
      developer.log('Could not hand the driver session to native: $error');
    }
  }

  static Future<void> clearSession() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod('clearDriverSession');
    } on PlatformException catch (error) {
      developer.log('Could not clear the native driver session: $error');
    }
  }

  /// Mirrors the driver's chosen language code (en/hi/kn/ta/te) to native, so
  /// the background ride-offer voice speaks in it while the app is killed.
  static Future<void> setLocale(String code) async {
    if (!_supported || code.isEmpty) return;
    try {
      await _channel.invokeMethod('setDriverLocale', {'code': code});
    } on PlatformException catch (error) {
      developer.log('Could not hand the driver locale to native: $error');
    }
  }

  /// Takes down the native card for [rideId] — used when the offer ends inside
  /// the app (accepted, rejected, or withdrawn over the socket) and the card
  /// would otherwise outlive it.
  static Future<void> dismissOffer(String rideId) async {
    if (!_supported || rideId.isEmpty) return;
    try {
      await _channel.invokeMethod('dismissRideOffer', {'rideId': rideId});
    } on PlatformException catch (error) {
      developer.log('Could not dismiss the native ride-offer card: $error');
    }
  }

  static Future<RideOfferPermissionStatus> permissions() async {
    if (!_supported) {
      // Nothing to grant off Android — reporting everything granted here keeps
      // the banner off other platforms without faking a real check.
      return const RideOfferPermissionStatus(
        fullScreenIntent: true,
        overlay: true,
        batteryOptimizations: true,
      );
    }

    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'getRideOfferPermissions',
      );
      if (raw == null) return RideOfferPermissionStatus.unknown;

      return RideOfferPermissionStatus(
        fullScreenIntent: raw['fullScreenIntent'] == true,
        overlay: raw['overlay'] == true,
        batteryOptimizations: raw['batteryOptimizations'] == true,
      );
    } catch (error) {
      // Deliberately not defaulting to granted: that would swallow a channel
      // error and make a device with none of these look fully set up.
      developer.log('Ride-offer permission check failed: $error');
      return RideOfferPermissionStatus.unknown;
    }
  }

  /// Each returns whether a Settings page actually opened. Several OEM builds
  /// throw on the direct intents, and the caller needs to know so it does not
  /// sit waiting for a resume that will never come.
  static Future<bool> requestFullScreenIntent() =>
      _request('requestFullScreenIntentPermission');

  static Future<bool> requestOverlay() => _request('requestOverlayPermission');

  static Future<bool> requestIgnoreBatteryOptimizations() =>
      _request('requestIgnoreBatteryOptimizations');

  static Future<bool> _request(String method) async {
    if (!_supported) return false;
    try {
      return await _channel.invokeMethod<bool>(method) ?? false;
    } on PlatformException catch (error) {
      developer.log('Ride-offer permission request $method failed: $error');
      return false;
    }
  }
}

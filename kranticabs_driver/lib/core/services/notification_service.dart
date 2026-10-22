import 'dart:developer' as developer;
import 'dart:io' show Platform;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'app_launcher_service.dart';

/// Must be a top-level function so it can run in the background isolate.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  developer.log('Background FCM message: ${message.messageId}');

  // A ride offer is handled natively from here on: RideRequestMessagingService
  // posts the full-screen card before this isolate even runs.
  //
  // This deliberately does not try to launch the app. Starting an activity from
  // a Dart background isolate is blocked by Android 10+'s background-activity
  // rules, so it was never reliable — and on the paths where it did work it
  // opened the whole app instead of showing an offer the driver could answer in
  // place.
}

class NotificationService {
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _ready = false;

  static const _rideChannel = AndroidNotificationChannel(
    'ride_requests',
    'Ride Requests',
    description: 'New ride offers and trip status updates',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  static const _generalChannel = AndroidNotificationChannel(
    'driver_general',
    'General',
    description: 'Earnings, wallet, account and support updates',
    importance: Importance.high,
  );

  /// FCM rotates tokens (reinstall, restore, app-data clear). Without
  /// re-registering, the server keeps a dead token and the driver silently
  /// stops receiving ride offers.
  Stream<String> get onTokenRefresh => FirebaseMessaging.instance.onTokenRefresh;

  Future<String?> init({
    required void Function(RemoteMessage message) onForegroundMessage,
    required void Function(RemoteMessage message) onMessageOpened,
  }) async {
    try {
      // Background handler is registered once in main.dart, before Firebase's
      // isolate boots — registering it again here has no additional effect.
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings();
      await _localNotifications.initialize(
        const InitializationSettings(android: androidInit, iOS: iosInit),
      );
      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(_rideChannel);
      await androidPlugin?.createNotificationChannel(_generalChannel);

      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);

      FirebaseMessaging.onMessage.listen((message) {
        onForegroundMessage(message);
        _showLocalNotification(message);
      });
      FirebaseMessaging.onMessageOpenedApp.listen(onMessageOpened);

      _ready = true;
      final token = await messaging.getToken();
      // Plain print (not developer.log): this must show up in `adb logcat` on
      // a standalone-launched build with no debugger attached, since
      // developer.log only reaches a live VM-service listener.
      // ignore: avoid_print
      print(
        'NotificationService: FCM token ${token == null || token.isEmpty ? "UNAVAILABLE" : "obtained (${token.length} chars)"}',
      );
      return token;
    } catch (error) {
      // Defensive: keeps the app usable even if permission/token retrieval
      // fails on a given device (e.g. notifications permanently denied).
      // ignore: avoid_print
      print('NotificationService init failed: $error');
      return null;
    }
  }

  /// Clears the tray alert for a ride offer that is no longer actionable
  /// (accepted, rejected, expired, or withdrawn because no driver was matched).
  ///
  /// Uses the same id [_showLocalNotification] posts with, so a stale "New ride
  /// request" cannot outlive the offer it refers to.
  Future<void> cancelRideOfferNotification(String rideId) async {
    if (!_ready || rideId.isEmpty) return;
    try {
      await _localNotifications.cancel(rideId.hashCode);
    } catch (error) {
      developer.log('Failed to cancel ride-offer notification: $error');
    }
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    if (!_ready) return;
    final notification = message.notification;
    final type = message.data['type']?.toString();
    final isRide = type == 'ride_request' || type == 'ride_offer' || message.data.containsKey('rideId');

    if (isRide) {
      // Automatically open / bring app to foreground when ride notification arrives
      await AppLauncherService.bringToForeground();

      // On Android a ride offer is alerted natively: the full-screen card when
      // the app is backgrounded, the in-app request screen and its ringtone when
      // it is not. Posting a local notification here as well would stack a
      // second alert and a second sound on top of whichever one is running.
      if (!kIsWeb && Platform.isAndroid) return;
    }

    // Data-only pushes carry no `notification` block. Returning early on those
    // meant a ride offer that arrived while the socket was down produced no
    // alert at all, so the driver had nothing to tap.
    final title = notification?.title ??
        (isRide ? 'New ride request' : null);
    final body = notification?.body ??
        (isRide ? 'A new booking is waiting for your response.' : null);
    if (title == null && body == null) return;

    final channel = isRide ? _rideChannel : _generalChannel;
    await _localNotifications.show(
      // Collapse repeated dispatch waves for one ride into a single alert
      // instead of stacking a new notification per wave.
      isRide
          ? (message.data['rideId']?.hashCode ?? _rideChannel.id.hashCode)
          : (notification?.hashCode ?? message.hashCode),
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: channel.importance,
          priority: Priority.max,
          fullScreenIntent: isRide,
          category: isRide ? AndroidNotificationCategory.call : AndroidNotificationCategory.event,
          visibility: NotificationVisibility.public,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }
}


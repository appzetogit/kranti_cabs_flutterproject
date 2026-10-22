import 'dart:developer' as developer;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'audio_service.dart';

/// Must be a top-level function so it can run in the background isolate.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  developer.log('Background FCM message: ${message.messageId}');
}

class NotificationService {
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _ready = false;

  static const _channel = AndroidNotificationChannel(
    'ride_updates',
    'Ride Updates',
    description: 'Notifications about your ride status and offers',
    importance: Importance.high,
  );

  Future<String?> init({
    required void Function(RemoteMessage message) onForegroundMessage,
    required void Function(RemoteMessage message) onMessageOpened,
  }) async {
    try {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings();
      await _localNotifications.initialize(
        const InitializationSettings(android: androidInit, iOS: iosInit),
      );
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);

      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);

      FirebaseMessaging.onMessage.listen((message) {
        _checkAudioForNotification(message);
        onForegroundMessage(message);
        _showLocalNotification(message);
      });
      FirebaseMessaging.onMessageOpenedApp.listen(onMessageOpened);

      _ready = true;
      return await messaging.getToken();
    } catch (error) {
      if (kDebugMode) {
        developer.log('NotificationService init skipped: $error');
      }
      return null;
    }
  }

  void _checkAudioForNotification(RemoteMessage message) {
    final data = message.data;
    final type = (data['type'] ?? data['event'] ?? '').toString().toLowerCase();
    final status = (data['status'] ?? '').toString().toLowerCase();
    final title = (message.notification?.title ?? '').toLowerCase();
    final body = (message.notification?.body ?? '').toLowerCase();

    // Trip-start deliberately makes no sound — see the note in
    // `RideTrackingController._checkAudioTrigger`. Only completion still plays.
    final combined = '$type $status $title $body';
    if (combined.contains('complete') || combined.contains('end')) {
      AudioService.playRideEnded();
    }
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    if (!_ready) return;
    final notification = message.notification;
    if (notification == null) return;
    await _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }
}

import 'dart:developer' as developer;
import 'package:flutter/services.dart';

class AppLauncherService {
  static const MethodChannel _channel = MethodChannel(
    'com.kranticabs.delivery/app_launcher',
  );

  /// Brings the driver app to the foreground and wakes the device screen.
  static Future<void> bringToForeground() async {
    try {
      await _channel.invokeMethod('bringToForeground');
    } catch (e) {
      developer.log('AppLauncherService bringToForeground error: $e');
    }
  }

  /// Wakes up the screen if locked/sleeping.
  static Future<void> wakeScreen() async {
    try {
      await _channel.invokeMethod('wakeScreen');
    } catch (e) {
      developer.log('AppLauncherService wakeScreen error: $e');
    }
  }
}

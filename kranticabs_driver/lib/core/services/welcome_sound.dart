import 'dart:developer' as developer;

import 'package:audioplayers/audioplayers.dart';

/// Plays `welcome.mp3` when the home screen opens after login: once per
/// signed-in driver per app run, and again after a new login ([reset] on logout).
class WelcomeSound {
  WelcomeSound._();

  static final AudioPlayer _player = AudioPlayer();
  static String? _welcomed;

  static Future<void> play(String driverId) async {
    if (_welcomed == driverId) return;
    _welcomed = driverId;
    try {
      await _player.stop();
      // Relative to assets/, so assets/sound/welcome.mp3 (the folder is listed in pubspec).
      await _player.play(AssetSource('sound/welcome.mp3'));
    } catch (error) {
      developer.log('Could not play welcome.mp3: $error', name: 'welcome');
    }
  }

  static void reset() => _welcomed = null;
}

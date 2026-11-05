import 'dart:developer' as developer;
import 'package:audioplayers/audioplayers.dart';

class AudioService {
  AudioService._();

  static final AudioPlayer _player = AudioPlayer();
  static bool _playedStarted = false;
  static bool _playedEnded = false;

  static final AudioPlayer _welcomePlayer = AudioPlayer();
  static String? _welcomedUser;

  /// Plays `welcome.mp3` when the home screen opens after login. Once per
  /// signed-in user per app run: coming back to Home from another screen does
  /// not replay it, a new login does ([resetWelcome] on logout).
  static Future<void> playWelcome(String userId) async {
    if (_welcomedUser == userId) return;
    _welcomedUser = userId;
    try {
      await _welcomePlayer.stop();
      await _welcomePlayer.play(AssetSource('audio/welcome.mp3'));
    } catch (e) {
      developer.log('AudioService error playing welcome.mp3: $e');
    }
  }

  static void resetWelcome() => _welcomedUser = null;

  /// Plays `started.mp3` sound ONCE when the ride begins.
  static Future<void> playTripStarted() async {
    if (_playedStarted) return;
    _playedStarted = true;
    try {
      await _player.stop();
      await _player.play(AssetSource('audio/started.mp3'));
      developer.log('AudioService: Played started.mp3');
    } catch (e) {
      developer.log('AudioService error playing started.mp3: $e');
    }
  }

  /// Plays `ended.mp3` sound ONCE when the ride completes successfully.
  static Future<void> playRideEnded() async {
    if (_playedEnded) return;
    _playedEnded = true;
    try {
      await _player.stop();
      await _player.play(AssetSource('audio/ended.mp3'));
      developer.log('AudioService: Played ended.mp3');
    } catch (e) {
      developer.log('AudioService error playing ended.mp3: $e');
    }
  }

  /// Resets sound state for a new ride lifecycle.
  static void resetState() {
    _playedStarted = false;
    _playedEnded = false;
  }
}

import 'dart:async';
import 'dart:developer' as developer;

import 'package:audioplayers/audioplayers.dart';

/// Plays the looping ride-offer ringtone.
///
/// Driven by ride state rather than by the request screen: an offer can arrive
/// while the driver is on any screen (or while the app is only just waking on a
/// push), and the alert has to sound even if the screen is a beat behind.
class RingtoneService {
  final AudioPlayer _player = AudioPlayer();
  bool _isRinging = false;
  Timer? _maxDurationTimer;

  /// Hard ceiling on how long the loop can run unattended.
  ///
  /// Every path that should silence this — accept, reject, expiry, a
  /// `ride_request_closed` push/socket event — calls [stop] already, but each
  /// of those depends on a message actually arriving. If it doesn't (socket
  /// down at the wrong moment, a dropped push), nothing else ever calls
  /// [stop] and the loop would otherwise run forever. Mirrors the native
  /// Kotlin player's own `MAX_RING_MS` ceiling, which this Dart player never
  /// had.
  static const Duration _maxRingDuration = Duration(seconds: 120);

  /// Starts the ringtone on a loop. Repeated calls while already ringing are
  /// ignored, so successive dispatch waves for the same offer do not restart
  /// the sound from the top.
  Future<void> startRideRequestRingtone() async {
    if (_isRinging) return;
    _isRinging = true;
    _maxDurationTimer?.cancel();
    _maxDurationTimer = Timer(_maxRingDuration, stop);
    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      // Ride offers must be audible over the driver's music/navigation.
      await _player.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            isSpeakerphoneOn: false,
            stayAwake: true,
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.notificationRingtone,
            audioFocus: AndroidAudioFocus.gainTransientMayDuck,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: const {AVAudioSessionOptions.duckOthers},
          ),
        ),
      );
      // `AssetSource` is relative to `assets/`, so this resolves to
      // assets/sound/neworder.mp3 — which only ships because pubspec lists
      // `assets/sound/` explicitly; a bare `assets/` entry does not recurse.
      await _player.play(AssetSource('sound/neworder.mp3'));
    } catch (error) {
      // A device that refuses audio focus must never block the offer itself.
      _isRinging = false;
      _maxDurationTimer?.cancel();
      // Logged at error level on purpose: a missing asset here is silent from
      // the driver's side — the offer simply arrives with no sound — and that
      // went unnoticed for a long time.
      developer.log(
        'Ride-offer ringtone failed to start — the offer will arrive silent',
        name: 'RingtoneService',
        error: error,
        level: 1000,
      );
    }
  }

  /// Stops immediately. Safe to call when not ringing.
  Future<void> stop() async {
    _maxDurationTimer?.cancel();
    _maxDurationTimer = null;
    if (!_isRinging) return;
    _isRinging = false;
    try {
      await _player.stop();
    } catch (error) {
      developer.log('Ride-offer ringtone failed to stop: $error');
    }
  }

  Future<void> dispose() async {
    _isRinging = false;
    _maxDurationTimer?.cancel();
    _maxDurationTimer = null;
    await _player.dispose();
  }
}

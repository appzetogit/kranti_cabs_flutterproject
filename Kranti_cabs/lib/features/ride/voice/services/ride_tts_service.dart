import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_tts/flutter_tts.dart';

import '../data/ride_voice_config.dart';
import '../data/ride_voice_log.dart';

/// Speaks a line of text in a given language, using the device's own
/// text-to-speech engine.
///
/// Device TTS rather than a cloud voice on purpose: there is no API key to keep
/// off the phone, no per-ETA audio file to generate or cache, and it works with
/// no signal. The engine is created once and reused — re-creating it per
/// announcement is what makes TTS stutter and leak on Android.
class RideTtsService {
  RideTtsService._();

  static final RideTtsService instance = RideTtsService._();

  FlutterTts? _tts;
  bool _initFailed = false;
  Completer<void>? _speaking;

  /// App language code -> TTS locale.
  ///
  /// The Indian variants matter: `hi-IN` and `kn-IN` exist on Indian devices
  /// where a bare `hi` may not resolve, and `en-IN` reads Indian place names
  /// far better than `en-US`.
  static const Map<String, String> _localeByLanguage = {
    'en': 'en-IN',
    'hi': 'hi-IN',
    'kn': 'kn-IN',
    'ta': 'ta-IN',
    'te': 'te-IN',
    'mr': 'mr-IN',
    'gu': 'gu-IN',
    'bn': 'bn-IN',
  };

  static const String _fallbackLocale = 'en-IN';

  static String ttsLocaleFor(String languageCode) =>
      _localeByLanguage[languageCode.trim().toLowerCase()] ?? _fallbackLocale;

  bool get isSpeaking => _speaking != null && !_speaking!.isCompleted;

  Future<FlutterTts?> _engine() async {
    if (_initFailed) return null;
    final existing = _tts;
    if (existing != null) return existing;

    try {
      final tts = FlutterTts();

      // Queues rather than cutting off whatever is already being read, and —
      // on Android — lets `speak` await the utterance so the completion
      // callback below actually fires.
      await tts.setQueueMode(1);
      await tts.awaitSpeakCompletion(true);

      _tts = tts;
      return tts;
    } catch (error) {
      // One failure is enough: a device with no TTS engine will fail every
      // time, and retrying on each announcement would just burn battery.
      _initFailed = true;
      rideVoiceLog('TTS engine unavailable, voice disabled for this session ($error)');
      return null;
    }
  }

  /// Whether the engine can actually speak [languageCode]. Used to fall back to
  /// English rather than let the engine read Kannada text with an English
  /// voice, which is unintelligible.
  Future<bool> supportsLanguage(String languageCode) async {
    final tts = await _engine();
    if (tts == null) return false;
    try {
      final available = await tts.isLanguageAvailable(ttsLocaleFor(languageCode));
      return available == true;
    } catch (error) {
      rideVoiceLog('Language availability check failed for $languageCode ($error)');
      return false;
    }
  }

  /// Speaks [text] in [languageCode]. Returns whether anything was actually
  /// said.
  ///
  /// Never throws: the caller is on a live-trip code path and a failure here
  /// must not touch tracking, navigation or payment.
  Future<bool> speak({
    required String text,
    required String languageCode,
    RideVoiceSpeech speech = const RideVoiceSpeech(),
  }) async {
    if (kIsWeb) return false;
    if (text.trim().isEmpty) return false;

    final tts = await _engine();
    if (tts == null) return false;

    final requested = ttsLocaleFor(languageCode);
    var locale = requested;

    try {
      if (await tts.isLanguageAvailable(requested) != true) {
        // Only English is worth falling back to — it is the one voice that is
        // present on effectively every device, and the config's own fallback
        // language decided the *text*, so the text is already English here in
        // the normal case.
        rideVoiceLog('TTS locale $requested not installed, falling back to $_fallbackLocale');
        locale = _fallbackLocale;
      }

      await tts.setLanguage(locale);
      await tts.setSpeechRate(speech.rate);
      await tts.setPitch(speech.pitch);
      await tts.setVolume(speech.volume);

      final completer = Completer<void>();
      _speaking = completer;
      tts.setCompletionHandler(() {
        if (!completer.isCompleted) completer.complete();
      });
      tts.setCancelHandler(() {
        if (!completer.isCompleted) completer.complete();
      });
      tts.setErrorHandler((message) {
        rideVoiceLog('TTS error while speaking ($message)');
        if (!completer.isCompleted) completer.complete();
      });

      rideVoiceLog('TTS language: $locale');
      await tts.speak(text);

      // A stuck engine must not pin this future forever — the scheduler awaits
      // it before marking the announcement played.
      await completer.future.timeout(
        const Duration(seconds: 60),
        onTimeout: () => rideVoiceLog('TTS did not report completion within 60s'),
      );

      return true;
    } catch (error) {
      rideVoiceLog('TTS failed to speak ($error)');
      return false;
    } finally {
      _speaking = null;
    }
  }

  /// Stops mid-sentence. Used when the trip ends or is cancelled while an
  /// announcement is still being read out.
  Future<void> stop() async {
    final tts = _tts;
    if (tts == null) return;
    try {
      await tts.stop();
    } catch (error) {
      rideVoiceLog('TTS stop failed ($error)');
    }
  }
}

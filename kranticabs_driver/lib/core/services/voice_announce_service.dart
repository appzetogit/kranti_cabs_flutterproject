import 'package:flutter_tts/flutter_tts.dart';

/// Speaks new-order details aloud (amount, pickup, drop) so drivers who are not
/// comfortable reading can understand an incoming order. Language follows the
/// driver's selected app locale; falls back gracefully if a TTS voice for that
/// language is not installed on the device.
class VoiceAnnounceService {
  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;

  /// Maps our app locale codes to TTS BCP-47 language tags.
  static const Map<String, String> _ttsLang = {
    'en': 'en-IN',
    'hi': 'hi-IN',
    'kn': 'kn-IN',
    'ta': 'ta-IN',
    'te': 'te-IN',
  };

  Future<void> _ensureInit() async {
    if (_initialized) return;
    _initialized = true;
    try {
      await _tts.awaitSpeakCompletion(true);
      await _tts.setSpeechRate(0.45); // a little slower for clarity
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
    } catch (_) {
      // TTS engine may be missing on some devices — speak() will just no-op.
    }
  }

  /// Announce [text] in the given app [localeCode] (en/hi/kn/ta/te).
  Future<void> announce(String text, {required String localeCode}) async {
    if (text.trim().isEmpty) return;
    await _ensureInit();
    final lang = _ttsLang[localeCode] ?? 'en-IN';
    try {
      // Only set the language if the device actually has it; otherwise keep the
      // default so the announcement still plays (in whatever voice is available).
      final available = await _tts.isLanguageAvailable(lang);
      if (available == true) {
        await _tts.setLanguage(lang);
      }
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {
      // Never let a TTS failure affect the ride-offer flow.
    }
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:taxiuser/features/ride/voice/data/ride_voice_config.dart';
import 'package:taxiuser/features/ride/voice/services/ride_tts_service.dart';

/// Verbatim body of `GET https://zicab.in/api/v1/users/settings/ride-voice`,
/// unwrapped by `ApiClient` to the `data` object the repository actually sees.
const _liveResponse = '''
{
  "settings": {
    "enabled": true,
    "fallback_language": "en",
    "welcome": {
      "enabled": true,
      "delay_minutes": 5,
      "messages": {
        "en": "Ladies and gentlemen, welcome aboard Zi Cab. Sit back and relax. We expect to reach your destination in approximately {minutes} minutes. Thank you.",
        "hi": "लेडीज एंड जेंटलमैन, Zi Cab में आपका स्वागत है। आराम से बैठें। हम लगभग {minutes} मिनट में आपकी मंजिल तक पहुंच जाएंगे। धन्यवाद।",
        "kn": "ಪ್ರಿಯ ಗ್ರಾಹಕರೇ, Zi Cab ಗೆ ಸ್ವಾಗತ. ಆರಾಮವಾಗಿರಿ. ನಾವು ಸುಮಾರು {minutes} ನಿಮಿಷಗಳಲ್ಲಿ ನಿಮ್ಮ ಗಮ್ಯಸ್ಥಾನವನ್ನು ತಲುಪುತ್ತೇವೆ. ಧನ್ಯವಾದಗಳು."
      }
    },
    "arrival": {
      "enabled": true,
      "trigger_remaining_minutes": 10,
      "messages": {
        "en": "Attention, Zi Cab will be arriving at your destination in {minutes} minutes. Please check your belongings. It was a pleasure serving you. Thank you.",
        "hi": "ध्यान दें, Zi Cab {minutes} मिनट में आपकी मंजिल तक पहुंच जाएगी। अपना सामान चेक कर लें। आपके साथ सफर करके अच्छा लगा। शुक्रिया।",
        "kn": "ಗಮನಿಸಿ, Zi Cab ಇನ್ನು {minutes} ನಿಮಿಷಗಳಲ್ಲಿ ನಿಮ್ಮ ಗಮ್ಯಸ್ಥಾನವನ್ನು ತಲುಪಲಿದೆ. ನಿಮ್ಮ ಸಾಮಗ್ರಿಗಳನ್ನು ಪರಿಶೀಲಿಸಿ. ನಿಮ್ಮೊಂದಿಗೆ ಪ್ರಯಾಣಿಸಿದ್ದು ನಮಗೆ ಸಂತೋಷ. ಧನ್ಯವಾದಗಳು."
      }
    },
    "speech": { "rate": 0.5, "pitch": 1, "volume": 1 }
  }
}
''';

RideVoiceConfig _parseLive() =>
    RideVoiceConfig.fromJson(Map<String, dynamic>.from(jsonDecode(_liveResponse)));

void main() {
  group('RideVoiceConfig', () {
    test('parses the live production payload', () {
      final config = _parseLive();

      expect(config.enabled, isTrue);
      expect(config.fallbackLanguage, 'en');
      expect(config.welcome.triggerMinutes, 5);
      expect(config.arrival.triggerMinutes, 10);
      expect(config.welcome.messages.keys, containsAll(['en', 'hi', 'kn']));
      expect(config.speech.rate, 0.5);
    });

    test('renders the approved wording for each language', () {
      final config = _parseLive();

      expect(
        renderVoiceTemplate(config.welcome.templateFor('en', 'en')!, {'minutes': '40'}),
        'Ladies and gentlemen, welcome aboard Zi Cab. Sit back and relax. '
        'We expect to reach your destination in approximately 40 minutes. Thank you.',
      );

      expect(
        renderVoiceTemplate(config.welcome.templateFor('hi', 'en')!, {'minutes': '40'}),
        contains('लगभग 40 मिनट'),
      );

      expect(
        renderVoiceTemplate(config.welcome.templateFor('kn', 'en')!, {'minutes': '28'}),
        contains('ಸುಮಾರು 28 ನಿಮಿಷಗಳಲ್ಲಿ'),
      );

      expect(
        renderVoiceTemplate(config.arrival.templateFor('en', 'en')!, {'minutes': '10'}),
        'Attention, Zi Cab will be arriving at your destination in 10 minutes. '
        'Please check your belongings. It was a pleasure serving you. Thank you.',
      );
    });

    test('falls back to the configured language when one is untranslated', () {
      final config = _parseLive();

      // Tamil is offered in the app but has no voice template yet.
      expect(config.welcome.templateFor('ta', 'en'), config.welcome.messages['en']);
      expect(config.welcome.resolvedLanguageFor('ta', 'en'), 'en');

      // ...and a translated language is never diverted to the fallback.
      expect(config.welcome.resolvedLanguageFor('kn', 'en'), 'kn');
    });

    test('stays silent rather than guessing when there is no config', () {
      expect(RideVoiceConfig.silent.hasAnythingToSay, isFalse);
      expect(RideVoiceConfig.fromJson(const {}).hasAnythingToSay, isFalse);
    });

    test('survives a malformed payload without throwing', () {
      final config = RideVoiceConfig.fromJson(const {
        'enabled': 'yes',
        'welcome': {'delay_minutes': '7', 'messages': 'not a map'},
        'arrival': 'not a section',
      });

      expect(config.enabled, isTrue);
      expect(config.welcome.triggerMinutes, 7);
      expect(config.welcome.messages, isEmpty);
      expect(config.hasAnythingToSay, isFalse);
    });

    test('round-trips through the offline cache', () {
      final original = _parseLive();
      final restored = RideVoiceConfig.fromJson(
        Map<String, dynamic>.from(jsonDecode(jsonEncode(original.toJson()))),
      );

      expect(restored.welcome.messages, original.welcome.messages);
      expect(restored.arrival.triggerMinutes, original.arrival.triggerMinutes);
      expect(restored.enabled, isTrue);
    });

    test('leaves a variable it does not know rather than blanking the word', () {
      expect(
        renderVoiceTemplate('Arriving at {destination} in {minutes} minutes', {'minutes': '4'}),
        'Arriving at {destination} in 4 minutes',
      );
    });
  });

  group('TTS locale mapping', () {
    test('maps app languages to Indian voice locales', () {
      expect(RideTtsService.ttsLocaleFor('en'), 'en-IN');
      expect(RideTtsService.ttsLocaleFor('hi'), 'hi-IN');
      expect(RideTtsService.ttsLocaleFor('kn'), 'kn-IN');
    });

    test('falls back to English for a language the voice system does not know', () {
      expect(RideTtsService.ttsLocaleFor('xx'), 'en-IN');
      expect(RideTtsService.ttsLocaleFor(''), 'en-IN');
    });
  });
}

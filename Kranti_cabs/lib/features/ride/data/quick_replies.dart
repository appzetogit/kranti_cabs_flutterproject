/// Preset quick-reply messages the rider can tap in ride chat, in all five
/// supported languages. The rider app has no global localization, so the chat
/// screen lets the rider pick a language for these replies (remembered on the
/// device); the chosen-language text is sent as a normal chat message.
class QuickReplies {
  QuickReplies._();

  static const List<String> langOrder = ['en', 'hi', 'kn', 'ta', 'te'];

  /// Short label shown on the per-language selector chips.
  static const Map<String, String> langLabels = {
    'en': 'EN',
    'hi': 'हिं',
    'kn': 'ಕನ್ನಡ',
    'ta': 'தமிழ்',
    'te': 'తెలుగు',
  };

  /// Reply text per language (same order across every language).
  static const Map<String, List<String>> byLang = {
    'en': [
      'Okay',
      'Please wait for a minute',
      'Yes',
      "I'm still coming",
      'Please pick up the call',
      "I'm waiting at the pickup point",
    ],
    'hi': [
      'ठीक है',
      'कृपया एक मिनट रुकें',
      'हाँ',
      'मैं अभी भी आ रहा/रही हूँ',
      'कृपया कॉल उठाएँ',
      'मैं पिकअप पॉइंट पर इंतज़ार कर रहा/रही हूँ',
    ],
    'kn': [
      'ಸರಿ',
      'ದಯವಿಟ್ಟು ಒಂದು ನಿಮಿಷ ಕಾಯಿರಿ',
      'ಹೌದು',
      'ನಾನು ಇನ್ನೂ ಬರುತ್ತಿದ್ದೇನೆ',
      'ದಯವಿಟ್ಟು ಕರೆ ಸ್ವೀಕರಿಸಿ',
      'ನಾನು ಪಿಕಪ್ ಪಾಯಿಂಟ್‌ನಲ್ಲಿ ಕಾಯುತ್ತಿದ್ದೇನೆ',
    ],
    'ta': [
      'சரி',
      'தயவுசெய்து ஒரு நிமிடம் காத்திருங்கள்',
      'ஆம்',
      'நான் இன்னும் வருகிறேன்',
      'தயவுசெய்து அழைப்பை எடுக்கவும்',
      'நான் பிக்அப் பாயிண்ட்டில் காத்திருக்கிறேன்',
    ],
    'te': [
      'సరే',
      'దయచేసి ఒక నిమిషం వేచి ఉండండి',
      'అవును',
      'నేను ఇంకా వస్తున్నాను',
      'దయచేసి కాల్ ఎత్తండి',
      'నేను పికప్ పాయింట్ వద్ద వేచి ఉన్నాను',
    ],
  };

  static List<String> repliesFor(String lang) => byLang[lang] ?? byLang['en']!;
}

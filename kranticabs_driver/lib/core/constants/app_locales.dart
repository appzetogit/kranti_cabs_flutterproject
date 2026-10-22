import 'package:flutter/widgets.dart';

/// Central list of the languages the driver app supports. Keep this and the
/// JSON files under [path] in sync (one `<code>.json` per locale).
class AppLocales {
  AppLocales._();

  static const String path = 'assets/translations';
  static const Locale fallback = Locale('en');

  static const Locale english = Locale('en');
  static const Locale hindi = Locale('hi');
  static const Locale kannada = Locale('kn');
  static const Locale tamil = Locale('ta');
  static const Locale telugu = Locale('te');

  static const List<Locale> supported = [
    english,
    hindi,
    kannada,
    tamil,
    telugu,
  ];

  /// The translation key (under `language.*`) that names each locale in its own
  /// script — used to label the options on the selection screen.
  static const Map<String, String> nameKeys = {
    'en': 'language.english',
    'hi': 'language.hindi',
    'kn': 'language.kannada',
    'ta': 'language.tamil',
    'te': 'language.telugu',
  };
}

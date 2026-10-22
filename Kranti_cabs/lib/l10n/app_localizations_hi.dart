// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class AppLocalizationsHi extends AppLocalizations {
  AppLocalizationsHi([String locale = 'hi']) : super(locale);

  @override
  String get selectLanguageTitle => 'अपनी भाषा चुनें';

  @override
  String get selectLanguageSubtitle =>
      'Kranti Cabs इसी भाषा में ऐप दिखाएगा और सफर के दौरान बोलेगा।';

  @override
  String get selectLanguageContinue => 'आगे बढ़ें';

  @override
  String get selectLanguageChangeHint =>
      'आप इसे बाद में सेटिंग्स में बदल सकते हैं।';

  @override
  String get languageTitle => 'भाषा';

  @override
  String languageSetTo(String language) {
    return 'भाषा $language पर सेट की गई';
  }

  @override
  String get settingsTitle => 'सेटिंग्स';

  @override
  String get settingsNotifications => 'नोटिफिकेशन सेटिंग्स';

  @override
  String get settingsAppTheme => 'ऐप थीम';

  @override
  String get settingsPrivacyPolicy => 'प्राइवेसी पॉलिसी';

  @override
  String get settingsSecurity => 'सुरक्षा';

  @override
  String get settingsTerms => 'सेवा की शर्तें';

  @override
  String get settingsAbout => 'हमारे बारे में';

  @override
  String get rideVoiceTitle => 'राइड वॉइस अनाउंसमेंट';

  @override
  String get rideVoiceSubtitle => 'सफर की जानकारी अपनी भाषा में सुनें';

  @override
  String get rideVoiceUnavailable => 'इस डिवाइस पर वॉइस उपलब्ध नहीं है';
}

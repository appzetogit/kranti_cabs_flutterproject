// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Kannada (`kn`).
class AppLocalizationsKn extends AppLocalizations {
  AppLocalizationsKn([String locale = 'kn']) : super(locale);

  @override
  String get selectLanguageTitle => 'ನಿಮ್ಮ ಭಾಷೆಯನ್ನು ಆಯ್ಕೆಮಾಡಿ';

  @override
  String get selectLanguageSubtitle =>
      'Kranti Cabs ಆ್ಯಪ್‌ನಲ್ಲಿ ಮತ್ತು ಪ್ರಯಾಣದ ವೇಳೆ ಇದೇ ಭಾಷೆಯನ್ನು ಬಳಸುತ್ತದೆ.';

  @override
  String get selectLanguageContinue => 'ಮುಂದುವರಿಸಿ';

  @override
  String get selectLanguageChangeHint =>
      'ನೀವು ಇದನ್ನು ನಂತರ ಸೆಟ್ಟಿಂಗ್ಸ್‌ನಲ್ಲಿ ಬದಲಾಯಿಸಬಹುದು.';

  @override
  String get languageTitle => 'ಭಾಷೆ';

  @override
  String languageSetTo(String language) {
    return 'ಭಾಷೆ $language ಗೆ ಹೊಂದಿಸಲಾಗಿದೆ';
  }

  @override
  String get settingsTitle => 'ಸೆಟ್ಟಿಂಗ್ಸ್';

  @override
  String get settingsNotifications => 'ಅಧಿಸೂಚನೆ ಸೆಟ್ಟಿಂಗ್ಸ್';

  @override
  String get settingsAppTheme => 'ಆ್ಯಪ್ ಥೀಮ್';

  @override
  String get settingsPrivacyPolicy => 'ಗೌಪ್ಯತಾ ನೀತಿ';

  @override
  String get settingsSecurity => 'ಭದ್ರತೆ';

  @override
  String get settingsTerms => 'ಸೇವಾ ನಿಯಮಗಳು';

  @override
  String get settingsAbout => 'ನಮ್ಮ ಬಗ್ಗೆ';

  @override
  String get rideVoiceTitle => 'ರೈಡ್ ಧ್ವನಿ ಪ್ರಕಟಣೆಗಳು';

  @override
  String get rideVoiceSubtitle => 'ಪ್ರಯಾಣದ ಮಾಹಿತಿಯನ್ನು ನಿಮ್ಮ ಭಾಷೆಯಲ್ಲಿ ಕೇಳಿ';

  @override
  String get rideVoiceUnavailable => 'ಈ ಸಾಧನದಲ್ಲಿ ಧ್ವನಿ ಲಭ್ಯವಿಲ್ಲ';
}

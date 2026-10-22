// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Tamil (`ta`).
class AppLocalizationsTa extends AppLocalizations {
  AppLocalizationsTa([String locale = 'ta']) : super(locale);

  @override
  String get selectLanguageTitle => 'உங்கள் மொழியைத் தேர்ந்தெடுக்கவும்';

  @override
  String get selectLanguageSubtitle =>
      'Kranti Cabs செயலியிலும் பயணத்தின் போதும் இதே மொழியைப் பயன்படுத்தும்.';

  @override
  String get selectLanguageContinue => 'தொடரவும்';

  @override
  String get selectLanguageChangeHint => 'இதை பின்னர் அமைப்புகளில் மாற்றலாம்.';

  @override
  String get languageTitle => 'மொழி';

  @override
  String languageSetTo(String language) {
    return 'மொழி $language ஆக அமைக்கப்பட்டது';
  }

  @override
  String get settingsTitle => 'அமைப்புகள்';

  @override
  String get settingsNotifications => 'அறிவிப்பு அமைப்புகள்';

  @override
  String get settingsAppTheme => 'செயலி தோற்றம்';

  @override
  String get settingsPrivacyPolicy => 'தனியுரிமைக் கொள்கை';

  @override
  String get settingsSecurity => 'பாதுகாப்பு';

  @override
  String get settingsTerms => 'சேவை விதிமுறைகள்';

  @override
  String get settingsAbout => 'எங்களைப் பற்றி';

  @override
  String get rideVoiceTitle => 'பயண குரல் அறிவிப்புகள்';

  @override
  String get rideVoiceSubtitle => 'பயணத் தகவல்களை உங்கள் மொழியில் கேளுங்கள்';

  @override
  String get rideVoiceUnavailable => 'இந்தச் சாதனத்தில் குரல் கிடைக்கவில்லை';
}

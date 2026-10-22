// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get selectLanguageTitle => 'Choose your language';

  @override
  String get selectLanguageSubtitle =>
      'Kranti Cabs will use this for the app and for what you hear during a ride.';

  @override
  String get selectLanguageContinue => 'Continue';

  @override
  String get selectLanguageChangeHint =>
      'You can change this later in Settings.';

  @override
  String get languageTitle => 'Language';

  @override
  String languageSetTo(String language) {
    return 'Language set to $language';
  }

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsNotifications => 'Notification settings';

  @override
  String get settingsAppTheme => 'App theme';

  @override
  String get settingsPrivacyPolicy => 'Privacy policy';

  @override
  String get settingsSecurity => 'Security';

  @override
  String get settingsTerms => 'Terms of service';

  @override
  String get settingsAbout => 'About';

  @override
  String get rideVoiceTitle => 'Ride voice announcements';

  @override
  String get rideVoiceSubtitle =>
      'Hear trip updates spoken aloud in your language';

  @override
  String get rideVoiceUnavailable => 'Voice is not available on this device';
}

// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Telugu (`te`).
class AppLocalizationsTe extends AppLocalizations {
  AppLocalizationsTe([String locale = 'te']) : super(locale);

  @override
  String get selectLanguageTitle => 'మీ భాషను ఎంచుకోండి';

  @override
  String get selectLanguageSubtitle =>
      'Kranti Cabs యాప్‌లో మరియు ప్రయాణ సమయంలో ఇదే భాషను ఉపయోగిస్తుంది.';

  @override
  String get selectLanguageContinue => 'కొనసాగించండి';

  @override
  String get selectLanguageChangeHint =>
      'దీన్ని తర్వాత సెట్టింగ్‌లలో మార్చుకోవచ్చు.';

  @override
  String get languageTitle => 'భాష';

  @override
  String languageSetTo(String language) {
    return 'భాష $languageకి సెట్ చేయబడింది';
  }

  @override
  String get settingsTitle => 'సెట్టింగ్‌లు';

  @override
  String get settingsNotifications => 'నోటిఫికేషన్ సెట్టింగ్‌లు';

  @override
  String get settingsAppTheme => 'యాప్ థీమ్';

  @override
  String get settingsPrivacyPolicy => 'గోప్యతా విధానం';

  @override
  String get settingsSecurity => 'భద్రత';

  @override
  String get settingsTerms => 'సేవా నిబంధనలు';

  @override
  String get settingsAbout => 'మా గురించి';

  @override
  String get rideVoiceTitle => 'ప్రయాణ వాయిస్ ప్రకటనలు';

  @override
  String get rideVoiceSubtitle => 'ప్రయాణ సమాచారాన్ని మీ భాషలో వినండి';

  @override
  String get rideVoiceUnavailable => 'ఈ పరికరంలో వాయిస్ అందుబాటులో లేదు';
}

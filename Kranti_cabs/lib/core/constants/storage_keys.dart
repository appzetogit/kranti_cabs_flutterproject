class StorageKeys {
  StorageKeys._();

  static const String authToken = 'auth_token';
  static const String userJson = 'user_json';
  static const String themeMode = 'theme_mode';
  static const String localeCode = 'locale_code';
  static const String onboardingSeen = 'onboarding_seen';

  /// Set once the rider has answered the first-run language prompt. Distinct
  /// from [localeCode], which has a default even before anything was picked.
  static const String languageChosen = 'language_chosen';

  /// Rider's on/off switch for in-ride voice announcements.
  static const String rideVoiceEnabled = 'ride_voice_enabled';

  /// Last voice configuration fetched from the backend, replayed when the
  /// config call fails so a trip still gets its announcements offline.
  static const String rideVoiceConfig = 'ride_voice_config';

  /// Per-ride record of which announcements have already been spoken. Survives
  /// the app being killed mid-trip, which is what stops a repeat on relaunch.
  static const String rideVoiceProgress = 'ride_voice_progress';
  static const String recentSearchesBox = 'recent_searches_box';
  static const String savedAddressesBox = 'saved_addresses_box';
  static const String emergencyContactsBox = 'emergency_contacts_box';
  static const String favoriteDriversBox = 'favorite_drivers_box';
  static const String settingsBox = 'settings_box';

  /// Short-lived catalog responses — see `ResponseCache`.
  static const String apiCacheBox = 'api_cache_box';
}

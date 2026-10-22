import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/storage_keys.dart';
import '../../../core/providers/core_providers.dart';

class DriverPreferences {
  final String languageCode;
  final String languageName;
  final bool soundAlerts;
  final bool voiceAnnounce;
  final bool vibration;
  final bool notifyRideRequests;
  final bool notifyEarnings;
  final bool notifyPromotions;
  final bool notifyNews;

  const DriverPreferences({
    this.languageCode = 'en',
    this.languageName = 'English',
    this.soundAlerts = true,
    this.voiceAnnounce = true,
    this.vibration = true,
    this.notifyRideRequests = true,
    this.notifyEarnings = true,
    this.notifyPromotions = true,
    this.notifyNews = false,
  });

  DriverPreferences copyWith({
    String? languageCode,
    String? languageName,
    bool? soundAlerts,
    bool? voiceAnnounce,
    bool? vibration,
    bool? notifyRideRequests,
    bool? notifyEarnings,
    bool? notifyPromotions,
    bool? notifyNews,
  }) {
    return DriverPreferences(
      languageCode: languageCode ?? this.languageCode,
      languageName: languageName ?? this.languageName,
      soundAlerts: soundAlerts ?? this.soundAlerts,
      voiceAnnounce: voiceAnnounce ?? this.voiceAnnounce,
      vibration: vibration ?? this.vibration,
      notifyRideRequests: notifyRideRequests ?? this.notifyRideRequests,
      notifyEarnings: notifyEarnings ?? this.notifyEarnings,
      notifyPromotions: notifyPromotions ?? this.notifyPromotions,
      notifyNews: notifyNews ?? this.notifyNews,
    );
  }
}

class SettingsNotifier extends StateNotifier<DriverPreferences> {
  final Ref ref;

  SettingsNotifier(this.ref) : super(const DriverPreferences()) {
    _restore();
  }

  void _restore() {
    final box = ref.read(localStorageServiceProvider).settings;
    state = DriverPreferences(
      languageCode: (box.get(StorageKeys.localeCode) as String?) ?? 'en',
      languageName: (box.get(StorageKeys.languageName) as String?) ?? 'English',
      soundAlerts: (box.get(StorageKeys.soundAlerts) as bool?) ?? true,
      voiceAnnounce: (box.get(StorageKeys.voiceAnnounce) as bool?) ?? true,
      vibration: (box.get(StorageKeys.vibration) as bool?) ?? true,
      notifyRideRequests: (box.get(StorageKeys.notifyRideRequests) as bool?) ?? true,
      notifyEarnings: (box.get(StorageKeys.notifyEarnings) as bool?) ?? true,
      notifyPromotions: (box.get(StorageKeys.notifyPromotions) as bool?) ?? true,
      notifyNews: (box.get(StorageKeys.notifyNews) as bool?) ?? false,
    );
  }

  void setLanguage(String code, String name) {
    state = state.copyWith(languageCode: code, languageName: name);
    final box = ref.read(localStorageServiceProvider).settings;
    box.put(StorageKeys.localeCode, code);
    box.put(StorageKeys.languageName, name);
  }

  void setSoundAlerts(bool value) {
    state = state.copyWith(soundAlerts: value);
    ref.read(localStorageServiceProvider).settings.put(StorageKeys.soundAlerts, value);
  }

  void setVoiceAnnounce(bool value) {
    state = state.copyWith(voiceAnnounce: value);
    ref.read(localStorageServiceProvider).settings.put(StorageKeys.voiceAnnounce, value);
  }

  void setVibration(bool value) {
    state = state.copyWith(vibration: value);
    ref.read(localStorageServiceProvider).settings.put(StorageKeys.vibration, value);
  }

  void setNotifyRideRequests(bool value) {
    state = state.copyWith(notifyRideRequests: value);
    ref.read(localStorageServiceProvider).settings.put(StorageKeys.notifyRideRequests, value);
  }

  void setNotifyEarnings(bool value) {
    state = state.copyWith(notifyEarnings: value);
    ref.read(localStorageServiceProvider).settings.put(StorageKeys.notifyEarnings, value);
  }

  void setNotifyPromotions(bool value) {
    state = state.copyWith(notifyPromotions: value);
    ref.read(localStorageServiceProvider).settings.put(StorageKeys.notifyPromotions, value);
  }

  void setNotifyNews(bool value) {
    state = state.copyWith(notifyNews: value);
    ref.read(localStorageServiceProvider).settings.put(StorageKeys.notifyNews, value);
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, DriverPreferences>((ref) {
  return SettingsNotifier(ref);
});

const supportedLanguages = [
  {'code': 'en', 'name': 'English'},
  {'code': 'hi', 'name': 'हिन्दी (Hindi)'},
  {'code': 'ta', 'name': 'தமிழ் (Tamil)'},
  {'code': 'te', 'name': 'తెలుగు (Telugu)'},
  {'code': 'kn', 'name': 'ಕನ್ನಡ (Kannada)'},
  {'code': 'ml', 'name': 'മലയാളം (Malayalam)'},
];

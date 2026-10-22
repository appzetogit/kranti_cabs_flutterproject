import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/storage_keys.dart';
import '../../../core/providers/core_providers.dart';

/// The single source of truth for the language the rider picked.
///
/// Everything that has to follow that choice reads this: the `MaterialApp`
/// locale, the Language screen, and the in-ride voice announcements. There is
/// deliberately no second "voice language" preference — one choice, one answer.
class LocaleNotifier extends StateNotifier<String> {
  final Ref ref;

  LocaleNotifier(this.ref) : super('en') {
    final box = ref.read(localStorageServiceProvider).settings;
    state = _normalize(box.get(StorageKeys.localeCode) as String?);
  }

  /// Falls back to English for anything not on the offered list, so a value
  /// left over from an older build (or hand-edited storage) cannot leave the
  /// app asking for a locale it has no strings for.
  static String _normalize(String? code) {
    final trimmed = (code ?? '').trim().toLowerCase();
    if (trimmed.isEmpty) return 'en';
    final match = supportedLanguages.any((lang) => lang['code'] == trimmed);
    return match ? trimmed : 'en';
  }

  void setLocale(String code) {
    final normalized = _normalize(code);
    state = normalized;
    final box = ref.read(localStorageServiceProvider).settings;
    box.put(StorageKeys.localeCode, normalized);
    // Picking a language is itself the answer to the first-run prompt, so the
    // rider is never asked twice — including when they choose from Settings
    // before ever seeing the first-run screen.
    box.put(StorageKeys.languageChosen, true);
  }
}

final localeProvider = StateNotifierProvider<LocaleNotifier, String>((ref) {
  return LocaleNotifier(ref);
});

/// The [Locale] handed to `MaterialApp`, derived from [localeProvider].
final appLocaleProvider = Provider<Locale>((ref) {
  return Locale(ref.watch(localeProvider));
});

/// Whether the rider has already answered the first-run language prompt.
///
/// Kept separate from [localeProvider] because "not chosen yet" and "chose
/// English" are different states: the first has to show the picker, the second
/// must not.
final languageChosenProvider = Provider<bool>((ref) {
  final box = ref.watch(localStorageServiceProvider).settings;
  return box.get(StorageKeys.languageChosen) == true;
});

const supportedLanguages = [
  {'code': 'en', 'label': 'English', 'native': 'English'},
  {'code': 'hi', 'label': 'Hindi', 'native': 'हिन्दी'},
  {'code': 'kn', 'label': 'Kannada', 'native': 'ಕನ್ನಡ'},
  {'code': 'ta', 'label': 'Tamil', 'native': 'தமிழ்'},
  {'code': 'te', 'label': 'Telugu', 'native': 'తెలుగు'},
];

/// The label shown for [code], or the code itself when it is not on the list.
String languageLabelFor(String code) {
  for (final lang in supportedLanguages) {
    if (lang['code'] == code) return lang['label']!;
  }
  return code;
}

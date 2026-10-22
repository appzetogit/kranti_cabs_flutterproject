import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/storage_keys.dart';
import 'core_providers.dart';

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  final Ref ref;

  ThemeModeNotifier(this.ref) : super(ThemeMode.light) {
    _restore();
  }

  void _restore() {
    final box = ref.read(localStorageServiceProvider).settings;
    final saved = box.get(StorageKeys.themeMode) as String?;
    switch (saved) {
      case 'light':
        state = ThemeMode.light;
        break;
      case 'dark':
        state = ThemeMode.dark;
        break;
      case 'system':
        state = ThemeMode.system;
        break;
      default:
        state = ThemeMode.light;
    }
  }

  void setThemeMode(ThemeMode mode) {
    state = mode;
    final box = ref.read(localStorageServiceProvider).settings;
    box.put(StorageKeys.themeMode, mode.name);
  }
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier(ref);
});

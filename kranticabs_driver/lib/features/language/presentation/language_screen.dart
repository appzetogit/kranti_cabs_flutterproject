import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_locales.dart';
import '../../../core/services/ride_offer_channel.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/application/auth_state.dart';
import '../../profile/application/settings_providers.dart';

/// Preference flag marking that the driver has picked a language at least once,
/// so the first-run selection screen is shown only on the very first launch.
const String kLanguageSelectedPrefKey = 'language_selected';

/// Language picker. In [initial] mode it is the one-time first-run screen shown
/// after the splash; otherwise it is opened from Settings and simply pops back.
class LanguageScreen extends ConsumerStatefulWidget {
  final bool initial;
  const LanguageScreen({super.key, this.initial = false});

  @override
  ConsumerState<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends ConsumerState<LanguageScreen> {
  Locale? _selected;
  bool _applying = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _selected ??= context.locale;
  }

  Future<void> _apply() async {
    final locale = _selected ?? AppLocales.fallback;
    setState(() => _applying = true);

    await context.setLocale(locale);
    // Keep the legacy settings locale in sync so non-widget code (e.g. the AI
    // voice announcer in the ride provider) can read the chosen language code.
    final nameKey = AppLocales.nameKeys[locale.languageCode] ?? 'language.english';
    ref.read(settingsProvider.notifier).setLanguage(locale.languageCode, nameKey.tr());
    // Mirror to native so the background ride-offer voice uses this language.
    unawaited(RideOfferChannel.setLocale(locale.languageCode));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kLanguageSelectedPrefKey, true);

    if (!mounted) return;

    if (widget.initial) {
      _goToPostSplashDestination();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  /// Mirrors the splash's routing: the session was already restored before this
  /// screen was shown, so we just read it and continue to the right place.
  void _goToPostSplashDestination() {
    final auth = ref.read(authProvider);
    if (auth.status == AuthStatus.authenticated) {
      final driver = auth.driver;
      if (driver != null && !driver.isApproved) {
        context.go('/verification-pending');
      } else {
        context.go('/home');
      }
    } else {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: widget.initial
          ? null
          : AppBar(
              backgroundColor: AppColors.darkBackground,
              elevation: 0,
              title: Text('language.settings_title'.tr(),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              iconTheme: const IconThemeData(color: Colors.white),
            ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.initial) ...[
                const SizedBox(height: 8),
                Text('language.select_title'.tr(),
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Text('language.select_subtitle'.tr(),
                    style: const TextStyle(color: AppColors.darkTextSecondary, fontSize: 14)),
                const SizedBox(height: 24),
              ],
              Expanded(
                child: ListView(
                  children: AppLocales.supported.map((locale) {
                    final nameKey = AppLocales.nameKeys[locale.languageCode] ?? '';
                    final selected = _selected?.languageCode == locale.languageCode;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Material(
                        color: selected
                            ? AppColors.primary.withValues(alpha: 0.12)
                            : AppColors.darkSurface,
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => setState(() => _selected = locale),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: selected ? AppColors.primary : AppColors.darkBorder,
                                width: selected ? 1.6 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    nameKey.tr(),
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 17,
                                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                                    ),
                                  ),
                                ),
                                if (selected)
                                  const Icon(Icons.check_circle_rounded, color: AppColors.primary),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _applying ? null : _apply,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: const Color(0xFF042F2A),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _applying
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF042F2A)),
                        )
                      : Text(
                          widget.initial ? 'common.continue'.tr() : 'common.save'.tr(),
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

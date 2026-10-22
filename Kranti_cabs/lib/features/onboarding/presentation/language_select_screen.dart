import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../profile/application/locale_provider.dart';

/// First thing the rider sees after the splash screen.
///
/// Asked once, before anything else, because the answer decides both the
/// language of the app and the language the cab speaks during a trip. The
/// screen previews itself in the highlighted language as the rider taps
/// through, so the choice is confirmable before it is committed.
class LanguageSelectScreen extends ConsumerStatefulWidget {
  /// Where to continue to once a language is picked. The splash screen already
  /// knows whether the rider is signed in, so it passes the answer through
  /// rather than making this screen work it out again.
  final String next;

  const LanguageSelectScreen({super.key, this.next = '/onboarding'});

  @override
  ConsumerState<LanguageSelectScreen> createState() => _LanguageSelectScreenState();
}

class _LanguageSelectScreenState extends ConsumerState<LanguageSelectScreen> {
  late String _selected = ref.read(localeProvider);

  void _continue() {
    // Committed only here. Tapping a tile previews the language; leaving
    // without confirming should not silently change the app.
    ref.read(localeProvider.notifier).setLocale(_selected);
    context.go(widget.next);
  }

  @override
  Widget build(BuildContext context) {
    // Rendered under the highlighted language rather than the saved one, so the
    // rider reads the screen in the language they are about to pick.
    return Localizations.override(
      context: context,
      locale: Locale(_selected),
      child: Builder(
        builder: (context) {
          final l10n = AppLocalizations.of(context);
          final theme = Theme.of(context);
          final isDark = theme.brightness == Brightness.dark;
          final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
          final textSecondary =
              isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

          return Scaffold(
            backgroundColor: isDark ? const Color(0xFF11191D) : Colors.white,
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Image.asset(
                      'assets/logo.webp',
                      height: 44,
                      errorBuilder: (context, error, stackTrace) => const SizedBox(height: 44),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      l10n.selectLanguageTitle,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: textPrimary,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      l10n.selectLanguageSubtitle,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w500,
                        color: textSecondary,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Expanded(
                      child: ListView.separated(
                        padding: EdgeInsets.zero,
                        itemCount: supportedLanguages.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final lang = supportedLanguages[index];
                          final code = lang['code']!;
                          final isSelected = code == _selected;

                          return _LanguageTile(
                            native: lang['native']!,
                            label: lang['label']!,
                            isSelected: isSelected,
                            isDark: isDark,
                            onTap: () => setState(() => _selected = code),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _continue,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: const Color(0xFF0A0A0A),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(27),
                          ),
                        ),
                        child: Text(
                          l10n.selectLanguageContinue,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF0A0A0A)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: Text(
                        l10n.selectLanguageChangeHint,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12.5, color: textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LanguageTile extends StatelessWidget {
  final String native;
  final String label;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  const _LanguageTile({
    required this.native,
    required this.label,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final surface = isDark ? const Color(0xFF222222) : Colors.white;
    final border = isDark ? const Color(0xFF2E2E2E) : const Color(0xFFE2E8F0);

    return Material(
      color: isSelected
          ? (isDark ? AppColors.primary.withValues(alpha: 0.15) : AppColors.primaryLight)
          : surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? AppColors.primary : border,
              width: isSelected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      native,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                isSelected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: isSelected ? AppColors.primary : border,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

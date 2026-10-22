import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../application/locale_provider.dart';

class LanguageScreen extends ConsumerWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(localeProvider);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: CustomAppBar(title: l10n.languageTitle),
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: supportedLanguages.length,
        itemBuilder: (context, index) {
          final lang = supportedLanguages[index];
          final isSelected = lang['code'] == selected;
          return ListTile(
            title: Text(lang['label']!),
            subtitle: Text(lang['native']!),
            trailing: isSelected ? const Icon(Icons.check_circle_rounded, color: AppColors.primary) : null,
            onTap: () {
              ref.read(localeProvider.notifier).setLocale(lang['code']!);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.languageSetTo(lang['label']!))),
              );
            },
          );
        },
      ),
    );
  }
}

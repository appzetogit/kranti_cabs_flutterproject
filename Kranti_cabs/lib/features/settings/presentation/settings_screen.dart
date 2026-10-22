import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../../../shared/widgets/profile_tile.dart';
import '../../ride/voice/application/ride_voice_providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final voiceEnabled = ref.watch(rideVoiceEnabledProvider);

    return Scaffold(
      appBar: CustomAppBar(title: l10n.settingsTitle),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _Section(children: [
            ProfileTile(
              icon: Icons.notifications_outlined,
              title: l10n.settingsNotifications,
              onTap: () => context.push('/notifications/settings'),
            ),
            const Divider(height: 1),
            ProfileTile(
              icon: Icons.language_rounded,
              title: l10n.languageTitle,
              onTap: () => context.push('/profile/language'),
            ),
            const Divider(height: 1),
            // Reuses the language the rider already picked — there is
            // deliberately no separate voice-language setting.
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.campaign_outlined, color: AppColors.primary),
              title: Text(
                l10n.rideVoiceTitle,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
              subtitle: Text(
                l10n.rideVoiceSubtitle,
                style: const TextStyle(fontSize: 12.5),
              ),
              value: voiceEnabled,
              activeThumbColor: AppColors.primary,
              onChanged: (value) =>
                  ref.read(rideVoiceEnabledProvider.notifier).setEnabled(value),
            ),
            const Divider(height: 1),
            ProfileTile(
              icon: Icons.dark_mode_outlined,
              title: l10n.settingsAppTheme,
              onTap: () => context.push('/profile/theme'),
            ),
          ]),
          const SizedBox(height: 16),
          _Section(children: [
            ProfileTile(
              icon: Icons.privacy_tip_outlined,
              title: l10n.settingsPrivacyPolicy,
              onTap: () => context.push('/settings/privacy'),
            ),
            const Divider(height: 1),
            ProfileTile(
              icon: Icons.security_rounded,
              title: l10n.settingsSecurity,
              onTap: () => context.push('/settings/security'),
            ),
            const Divider(height: 1),
            ProfileTile(
              icon: Icons.description_outlined,
              title: l10n.settingsTerms,
              onTap: () => context.push('/settings/terms'),
            ),
            const Divider(height: 1),
            ProfileTile(
              icon: Icons.info_outline_rounded,
              title: l10n.settingsAbout,
              onTap: () => context.push('/settings/about'),
            ),
          ]),
          const SizedBox(height: 16),
          _Section(children: [
            ProfileTile(
              icon: Icons.delete_outline_rounded,
              title: 'Delete account',
              iconColor: AppColors.error,
              onTap: () => context.push('/profile/delete-account'),
            ),
          ]),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final List<Widget> children;
  const _Section({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.lightBorder),
      ),
      child: Column(children: children),
    );
  }
}

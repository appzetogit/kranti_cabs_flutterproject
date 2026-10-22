import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../../../shared/widgets/section_title.dart';
import '../application/settings_providers.dart';

class PreferencesScreen extends ConsumerWidget {
  const PreferencesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(settingsProvider);
    final themeMode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: const CustomAppBar(title: 'Preferences'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SectionTitle(title: 'Appearance'),
          const SizedBox(height: 10),
          _Card(
            children: [
              _ChoiceRow(
                label: 'Light (Default)',
                selected: themeMode == ThemeMode.light,
                onTap: () => ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.light),
              ),
              const Divider(height: 1),
              _ChoiceRow(
                label: 'Dark',
                selected: themeMode == ThemeMode.dark,
                onTap: () => ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.dark),
              ),
              const Divider(height: 1),
              _ChoiceRow(
                label: 'System default',
                selected: themeMode == ThemeMode.system,
                onTap: () => ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.system),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const SectionTitle(title: 'Ride alerts'),
          const SizedBox(height: 10),
          _Card(
            children: [
              _SwitchRow(
                label: 'Sound alerts',
                value: prefs.soundAlerts,
                onChanged: (v) => ref.read(settingsProvider.notifier).setSoundAlerts(v),
              ),
              const Divider(height: 1),
              _SwitchRow(
                label: 'AI voice announcements',
                value: prefs.voiceAnnounce,
                onChanged: (v) => ref.read(settingsProvider.notifier).setVoiceAnnounce(v),
              ),
              const Divider(height: 1),
              _SwitchRow(
                label: 'Vibration',
                value: prefs.vibration,
                onChanged: (v) => ref.read(settingsProvider.notifier).setVibration(v),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final List<Widget> children;

  const _Card({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF222222),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2E2E2E)),
      ),
      child: Column(children: children),
    );
  }
}

class _ChoiceRow extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ChoiceRow({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
            if (selected) const Icon(Icons.check_circle, color: AppColors.primary, size: 20),
          ],
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
          Switch(value: value, onChanged: onChanged, activeThumbColor: AppColors.primary),
        ],
      ),
    );
  }
}

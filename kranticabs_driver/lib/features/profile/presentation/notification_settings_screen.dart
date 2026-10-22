import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../../../shared/widgets/section_title.dart';
import '../application/settings_providers.dart';

class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: const CustomAppBar(title: 'Notification Settings'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SectionTitle(title: 'What you get notified about'),
          const SizedBox(height: 10),
          _Card(
            children: [
              _SwitchRow(
                label: 'Ride requests',
                subtitle: 'New ride requests nearby',
                value: prefs.notifyRideRequests,
                onChanged: notifier.setNotifyRideRequests,
              ),
              const Divider(height: 1),
              _SwitchRow(
                label: 'Earnings',
                subtitle: 'Payouts, incentives & wallet updates',
                value: prefs.notifyEarnings,
                onChanged: notifier.setNotifyEarnings,
              ),
              const Divider(height: 1),
              _SwitchRow(
                label: 'Promotions',
                subtitle: 'Offers and bonus campaigns',
                value: prefs.notifyPromotions,
                onChanged: notifier.setNotifyPromotions,
              ),
              const Divider(height: 1),
              _SwitchRow(
                label: 'News & updates',
                subtitle: 'App updates and announcements',
                value: prefs.notifyNews,
                onChanged: notifier.setNotifyNews,
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.lightBorder),
      ),
      child: Column(children: children),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({required this.label, required this.subtitle, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(color: AppColors.lightTextSecondary, fontSize: 12)),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged, activeThumbColor: AppColors.primary),
        ],
      ),
    );
  }
}

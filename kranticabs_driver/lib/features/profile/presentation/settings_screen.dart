import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/custom_app_bar.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: 'Settings'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SettingsTile(
            icon: Icons.language_outlined,
            title: 'Language',
            onTap: () => context.push('/language'),
          ),
          const SizedBox(height: 10),
          _SettingsTile(
            icon: Icons.tune_outlined,
            title: 'Preferences',
            onTap: () => context.push('/preferences'),
          ),
          const SizedBox(height: 10),
          _SettingsTile(
            icon: Icons.notifications_outlined,
            title: 'Notification Settings',
            onTap: () => context.push('/notification-settings'),
          ),
          const SizedBox(height: 10),
          _SettingsTile(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy Policy',
            onTap: () => context.push('/privacy'),
          ),
          const SizedBox(height: 24),
          _SettingsTile(
            icon: Icons.logout,
            title: 'Logout',
            color: AppColors.warning,
            onTap: () => context.push('/logout'),
          ),
          const SizedBox(height: 10),
          _SettingsTile(
            icon: Icons.delete_outline,
            title: 'Delete Account',
            color: AppColors.error,
            onTap: () => context.push('/delete-account'),
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final Color? color;

  const _SettingsTile({required this.icon, required this.title, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final tint = color ?? AppColors.primary;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.lightBorder),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: tint.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: Icon(icon, color: tint, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: color)),
            ),
            const Icon(Icons.chevron_right, color: AppColors.lightTextSecondary),
          ],
        ),
      ),
    );
  }
}

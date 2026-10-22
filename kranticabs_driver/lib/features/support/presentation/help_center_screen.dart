import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/custom_app_bar.dart';

class HelpCenterScreen extends StatelessWidget {
  const HelpCenterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: 'Help Center'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _HelpTile(
            icon: Icons.quiz_outlined,
            title: 'Frequently Asked Questions',
            subtitle: 'Quick answers to common questions',
            onTap: () => context.push('/faq'),
          ),
          const SizedBox(height: 10),
          _HelpTile(
            icon: Icons.chat_bubble_outline,
            title: 'Chat with Support',
            subtitle: 'View or continue your support tickets',
            onTap: () => context.push('/chat-support'),
          ),
          const SizedBox(height: 10),
          _HelpTile(
            icon: Icons.confirmation_num_outlined,
            title: 'Raise a Ticket',
            subtitle: 'Get help with a specific issue',
            onTap: () => context.push('/raise-ticket'),
          ),
          const SizedBox(height: 10),
          _HelpTile(
            icon: Icons.report_gmailerrorred_outlined,
            title: 'Report an Issue',
            subtitle: 'Report a problem with a trip or the app',
            onTap: () => context.push('/report-issue'),
          ),
          // Real contacts only, from AppConstants. This block used to show a
          // placeholder number and another company's email address.
          if (AppConstants.supportPhone.isNotEmpty || AppConstants.supportEmail.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Text('Contact us', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.lightBorder),
              ),
              child: Column(
                children: [
                  if (AppConstants.supportPhone.isNotEmpty)
                    const _ContactRow(icon: Icons.phone_outlined, label: AppConstants.supportPhone),
                  if (AppConstants.supportPhone.isNotEmpty && AppConstants.supportEmail.isNotEmpty)
                    const SizedBox(height: 12),
                  if (AppConstants.supportEmail.isNotEmpty)
                    const _ContactRow(icon: Icons.email_outlined, label: AppConstants.supportEmail),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HelpTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _HelpTile({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
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
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(color: AppColors.lightTextSecondary, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.lightTextSecondary),
          ],
        ),
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ContactRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 12),
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      ],
    );
  }
}

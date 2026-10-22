import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/custom_app_bar.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: 'Privacy Policy'),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: const [
          _Section(
            title: 'Information we collect',
            body:
                'We collect your name, phone number, email, vehicle and document details, and location '
                'data while you are online, to provide ride-matching, navigation and safety features.',
          ),
          _Section(
            title: 'How we use your data',
            body:
                'Your location is shared with riders during an active trip for tracking and safety. '
                'Your documents are used solely for verification and compliance with local regulations.',
          ),
          _Section(
            title: 'Data sharing',
            body:
                'We do not sell your personal data. Information may be shared with riders (limited trip '
                'details), payment processors, and law enforcement when legally required.',
          ),
          _Section(
            title: 'Data retention',
            body:
                'Trip and earnings history is retained as required for tax and legal compliance. You may '
                'request account and data deletion at any time from Settings > Delete Account.',
          ),
          _Section(
            title: 'Your rights',
            body:
                'You can review and update your profile, vehicle and documents at any time. Contact '
                'support if you have questions about how your data is handled.',
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String body;
  const _Section({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 8),
          Text(body, style: const TextStyle(color: AppColors.lightTextSecondary, fontSize: 13, height: 1.5)),
        ],
      ),
    );
  }
}

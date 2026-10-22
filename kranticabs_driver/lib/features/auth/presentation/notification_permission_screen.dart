import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/secondary_button.dart';

/// Pure consent step — the actual FCM init (permission prompt + token
/// registration) happens centrally once the driver session is authenticated,
/// see `AuthNotifier.onAuthenticated`. This keeps push notifications working
/// for every session, not just the first-time onboarding flow.
class NotificationPermissionScreen extends StatelessWidget {
  const NotificationPermissionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.notifications_active_outlined, size: 56, color: AppColors.primary),
              ),
              const SizedBox(height: 28),
              Text('Stay Updated', style: Theme.of(context).textTheme.headlineMedium, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text(
                'Turn on notifications so you never miss a ride request, earning update or important account alert.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              PrimaryButton(label: 'Allow Notifications', onPressed: () => context.push('/vehicle-info')),
              const SizedBox(height: 12),
              SecondaryButton(
                label: 'Not Now',
                onPressed: () => context.push('/vehicle-info'),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

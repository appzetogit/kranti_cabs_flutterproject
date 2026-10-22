import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/primary_button.dart';

class VerificationApprovedScreen extends StatelessWidget {
  const VerificationApprovedScreen({super.key});

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
                  color: AppColors.success.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_outline, size: 56, color: AppColors.success),
              ),
              const SizedBox(height: 28),
              Text("You're Approved!", style: Theme.of(context).textTheme.headlineMedium, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text(
                'Your account has been verified. You can now go online and start accepting ride requests.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              PrimaryButton(label: 'Go to Dashboard', onPressed: () => context.go('/home')),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

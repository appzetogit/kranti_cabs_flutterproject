import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/primary_button.dart';

class MaintenanceScreen extends StatelessWidget {
  const MaintenanceScreen({super.key});

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
                  color: AppColors.info.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.build_circle_outlined, size: 56, color: AppColors.info),
              ),
              const SizedBox(height: 28),
              Text("We'll Be Right Back", style: Theme.of(context).textTheme.headlineMedium, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text(
                '${AppConstants.title} is currently undergoing scheduled maintenance. Please check back shortly.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              PrimaryButton(
                label: 'Retry',
                onPressed: () => context.canPop() ? context.pop() : context.go('/splash'),
                icon: Icons.refresh,
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

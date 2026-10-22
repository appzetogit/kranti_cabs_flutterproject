import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/primary_button.dart';

class SystemStatusView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String primaryActionLabel;
  final VoidCallback? onPrimaryAction;
  final bool primaryActionLoading;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;
  final String? tertiaryActionLabel;
  final VoidCallback? onTertiaryAction;

  const SystemStatusView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.primaryActionLabel,
    required this.onPrimaryAction,
    this.primaryActionLoading = false,
    this.secondaryActionLabel,
    this.onSecondaryAction,
    this.tertiaryActionLabel,
    this.onTertiaryAction,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                height: 120,
                width: 120,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: AppColors.primaryGradient),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 54, color: Colors.white),
              ),
              const SizedBox(height: 28),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.lightTextSecondary),
              ),
              const SizedBox(height: 32),
              PrimaryButton(
                label: primaryActionLabel,
                isLoading: primaryActionLoading,
                onPressed: onPrimaryAction,
              ),
              if (secondaryActionLabel != null) ...[
                const SizedBox(height: 12),
                TextButton(onPressed: onSecondaryAction, child: Text(secondaryActionLabel!)),
              ],
              if (tertiaryActionLabel != null) ...[
                TextButton(onPressed: onTertiaryAction, child: Text(tertiaryActionLabel!)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

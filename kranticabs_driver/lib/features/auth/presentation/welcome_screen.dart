import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/secondary_button.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: AppColors.accentGradient,
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Spacer(),
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: const Icon(Icons.local_taxi, size: 50, color: AppColors.primary),
                ),
                const SizedBox(height: 24),
                Text(
                  AppConstants.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Drive. Earn. Grow with every ride.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 15),
                  textAlign: TextAlign.center,
                ),
                const Spacer(),
                PrimaryButton(
                  label: 'Login',
                  onPressed: () => context.push('/login'),
                ),
                const SizedBox(height: 14),
                SecondaryButton(
                  label: 'Create Account',
                  onPressed: () => context.push('/signup'),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

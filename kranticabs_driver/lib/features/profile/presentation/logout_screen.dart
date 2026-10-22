import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../auth/application/auth_providers.dart';

class LogoutScreen extends ConsumerStatefulWidget {
  const LogoutScreen({super.key});

  @override
  ConsumerState<LogoutScreen> createState() => _LogoutScreenState();
}

class _LogoutScreenState extends ConsumerState<LogoutScreen> {
  bool _loggingOut = false;

  Future<void> _confirmLogout() async {
    setState(() => _loggingOut = true);
    await ref.read(authProvider.notifier).logout();
    if (mounted) context.go('/welcome');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: 'Logout'),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.logout, size: 44, color: AppColors.warning),
            ),
            const SizedBox(height: 20),
            const Text(
              'Are you sure you want to logout?',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'You will need to verify your phone number again to sign back in.',
              style: TextStyle(color: AppColors.lightTextSecondary, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            PrimaryButton(
              label: 'Logout',
              onPressed: _confirmLogout,
              loading: _loggingOut,
              color: AppColors.error,
              icon: Icons.logout,
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _loggingOut ? null : () => context.pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../auth/application/auth_providers.dart';

class SessionExpiredScreen extends ConsumerStatefulWidget {
  const SessionExpiredScreen({super.key});

  @override
  ConsumerState<SessionExpiredScreen> createState() => _SessionExpiredScreenState();
}

class _SessionExpiredScreenState extends ConsumerState<SessionExpiredScreen> {
  bool _loggingIn = false;

  Future<void> _login() async {
    setState(() => _loggingIn = true);
    await ref.read(authProvider.notifier).logout();
    if (mounted) context.go('/welcome');
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
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
                    color: AppColors.error.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.lock_clock_outlined, size: 56, color: AppColors.error),
                ),
                const SizedBox(height: 28),
                Text('Session Expired', style: Theme.of(context).textTheme.headlineMedium, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                Text(
                  'Your session has expired for security reasons. Please log in again to continue.',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const Spacer(),
                PrimaryButton(label: 'Log In Again', onPressed: _login, loading: _loggingIn, icon: Icons.login),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

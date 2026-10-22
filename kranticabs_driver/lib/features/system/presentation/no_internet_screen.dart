import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/snackbar_utils.dart';
import '../../../shared/widgets/primary_button.dart';

class NoInternetScreen extends StatefulWidget {
  const NoInternetScreen({super.key});

  @override
  State<NoInternetScreen> createState() => _NoInternetScreenState();
}

class _NoInternetScreenState extends State<NoInternetScreen> {
  bool _checking = false;

  Future<void> _retry() async {
    setState(() => _checking = true);
    final results = await Connectivity().checkConnectivity();
    if (!mounted) return;
    setState(() => _checking = false);
    final online = results.any((r) => r != ConnectivityResult.none);
    if (online) {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/splash');
      }
    } else {
      SnackbarUtils.error('Still no internet connection');
    }
  }

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
                  color: AppColors.error.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.wifi_off_rounded, size: 56, color: AppColors.error),
              ),
              const SizedBox(height: 28),
              Text('No Internet Connection', style: Theme.of(context).textTheme.headlineMedium, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text(
                "You're offline. Please check your Wi-Fi or mobile data connection and try again.",
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              PrimaryButton(label: 'Retry', onPressed: _retry, loading: _checking, icon: Icons.refresh),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

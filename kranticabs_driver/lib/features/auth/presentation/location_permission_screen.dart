import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/snackbar_utils.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/secondary_button.dart';

class LocationPermissionScreen extends ConsumerStatefulWidget {
  const LocationPermissionScreen({super.key});

  @override
  ConsumerState<LocationPermissionScreen> createState() => _LocationPermissionScreenState();
}

class _LocationPermissionScreenState extends ConsumerState<LocationPermissionScreen> {
  bool _loading = false;

  Future<void> _requestPermission() async {
    setState(() => _loading = true);
    try {
      final result = await ref.read(locationServiceProvider).ensurePermission();
      if (!mounted) return;
      if (!result.granted) {
        SnackbarUtils.warning('Location access helps you receive nearby ride requests.');
      }
      context.push('/notification-permission');
    } finally {
      if (mounted) setState(() => _loading = false);
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
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.location_on_outlined, size: 56, color: AppColors.primary),
              ),
              const SizedBox(height: 28),
              Text('Enable Location Access', style: Theme.of(context).textTheme.headlineMedium, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text(
                'We use your location to match you with nearby ride requests and guide you to pickup and drop points.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              PrimaryButton(label: 'Allow Location Access', onPressed: _requestPermission, loading: _loading),
              const SizedBox(height: 12),
              SecondaryButton(
                label: 'Not Now',
                onPressed: () => context.push('/notification-permission'),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

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
  bool _requesting = false;

  Future<void> _allow() async {
    setState(() => _requesting = true);
    try {
      final result = await ref.read(locationServiceProvider).ensurePermission();
      if (!mounted) return;

      if (result.granted) {
        context.go('/auth/notification-permission');
        return;
      }

      // "Don't allow" (or GPS off) used to carry on to the next step as if
      // nothing had happened, leaving the rider with no way to fix it later.
      // Stay here and say what is needed; "Not now" below still lets them skip.
      if (!result.serviceEnabled) {
        await context.push('/system/gps-disabled');
      } else if (result.permanentlyDenied) {
        await context.push('/system/location-permission-denied');
      } else {
        SnackbarUtils.info(context, 'Location access is needed to find your pickup point.');
      }
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  children: [
                    const Spacer(),
                    Container(
                      height: 140,
                      width: 140,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.location_on_rounded, size: 64, color: AppColors.primary),
                    ),
                    const SizedBox(height: 32),
                    Text(
                      'Enable your location',
                      style: Theme.of(context).textTheme.headlineLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'We use your location to find nearby drivers and get you the fastest, most accurate pickup.',
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const Spacer(),
                    PrimaryButton(
                      label: 'Allow location access',
                      isLoading: _requesting,
                      onPressed: _allow,
                    ),
                    const SizedBox(height: 12),
                    SecondaryButton(
                      label: 'Not now',
                      onPressed: () => context.go('/auth/notification-permission'),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

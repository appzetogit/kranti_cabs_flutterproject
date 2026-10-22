import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/primary_button.dart';

class GpsDisabledScreen extends StatefulWidget {
  const GpsDisabledScreen({super.key});

  @override
  State<GpsDisabledScreen> createState() => _GpsDisabledScreenState();
}

class _GpsDisabledScreenState extends State<GpsDisabledScreen> {
  bool _opening = false;

  Future<void> _openSettings() async {
    setState(() => _opening = true);
    await Geolocator.openLocationSettings();
    if (!mounted) return;
    setState(() => _opening = false);
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!mounted) return;
    if (enabled && context.canPop()) {
      context.pop();
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
                  color: AppColors.warning.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.location_off_rounded, size: 56, color: AppColors.warning),
              ),
              const SizedBox(height: 28),
              Text('Location Services Disabled', style: Theme.of(context).textTheme.headlineMedium, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text(
                'Turn on location services so we can match you with nearby ride requests and track your trips.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              PrimaryButton(label: 'Enable Location', onPressed: _openSettings, loading: _opening, icon: Icons.location_on_outlined),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

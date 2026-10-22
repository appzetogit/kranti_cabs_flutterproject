import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/snackbar_utils.dart';
import '../../../shared/widgets/primary_button.dart';

class ForceUpdateScreen extends StatelessWidget {
  const ForceUpdateScreen({super.key});

  Future<void> _openStore() async {
    final uri = Uri.parse('https://play.google.com/store/apps/details?id=${AppConstants.packageName}');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      SnackbarUtils.error('Could not open the app store');
    }
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
                    color: AppColors.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.system_update_alt_rounded, size: 56, color: AppColors.primary),
                ),
                const SizedBox(height: 28),
                Text('Update Required', style: Theme.of(context).textTheme.headlineMedium, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                Text(
                  'A new version of ${AppConstants.title} is available. Please update to continue using the app.',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const Spacer(),
                PrimaryButton(label: 'Update Now', onPressed: _openStore, icon: Icons.download_rounded),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

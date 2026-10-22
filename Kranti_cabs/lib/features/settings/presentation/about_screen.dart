import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../../../shared/widgets/profile_tile.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: 'About'),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: Column(
              children: [
                Container(
                  height: 72,
                  width: 72,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: AppColors.primaryGradient),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.local_taxi_rounded, color: Colors.white, size: 36),
                ),
                const SizedBox(height: 16),
                FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (context, snapshot) {
                    final info = snapshot.data;
                    return Column(
                      children: [
                        Text(info?.appName ?? 'Kranti Cabs', style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 4),
                        Text(
                          info != null ? 'Version ${info.version} (${info.buildNumber})' : ' ',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.lightBorder),
            ),
            child: Column(
              children: [
                ProfileTile(
                  icon: Icons.description_outlined,
                  title: 'Terms of service',
                  onTap: () => context.push('/settings/terms'),
                ),
                const Divider(height: 1),
                ProfileTile(
                  icon: Icons.privacy_tip_outlined,
                  title: 'Privacy policy',
                  onTap: () => context.push('/settings/privacy'),
                ),
                const Divider(height: 1),
                ProfileTile(
                  icon: Icons.mail_outline_rounded,
                  title: 'Contact support',
                  onTap: () => launchUrl(Uri.parse('mailto:support@taxiapp.com')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

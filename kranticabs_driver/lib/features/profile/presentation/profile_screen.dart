import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/constants/app_locales.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/image_utils.dart';
import '../../../core/utils/snackbar_utils.dart';
import 'package:intl/intl.dart';
import '../../auth/application/auth_providers.dart';
import '../../earnings/application/earnings_providers.dart';
import '../../subscription/application/subscription_providers.dart';
import '../../subscription/data/subscription_model.dart';
import '../../../core/utils/ist_time.dart';
import '../application/profile_providers.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final driver = ref.watch(authProvider).driver;
    final walletAsync = ref.watch(walletSnapshotProvider);
    final realWalletBalance = walletAsync.whenOrNull(
          data: (snapshot) => snapshot.wallet.balance,
        ) ??
        driver?.walletBalance ??
        0.0;
    // Real values only. These previously fell back to one specific person's
    // name and phone number, a 2.7 rating and 128 trips, so any driver whose
    // profile had not loaded saw someone else's identity on their own page.
    final name = driver?.name.isNotEmpty == true ? driver!.name.toUpperCase() : '';
    final phone = driver?.phone ?? '';
    final rating = (driver?.rating ?? 0) > 0 ? driver!.rating.toStringAsFixed(1) : 'New';
    // Labelled "Total Trips", so it has to be the lifetime figure. It was
    // reading today's ride count, which showed 0 to a driver with hundreds of
    // completed trips behind them.
    final totalTrips = ref.watch(lifetimeRideCountProvider).maybeWhen(
          data: (count) => '$count',
          orElse: () => '${driver?.todaySummary.rides ?? 0}',
        );
    final subscriptionAsync = ref.watch(subscriptionStatusProvider);
    final subscriptionStatus = subscriptionAsync.valueOrNull;

    return Scaffold(
      backgroundColor: const Color(0xFF11191D),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            // Top Navigation & Control Header Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text(
                  'Profile',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                Row(
                  children: [
                    // Notification Button with Orange Dot Badge
                    GestureDetector(
                      onTap: () => context.push('/notifications'),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFF222222),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFF2E2E2E)),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            const Icon(
                              Icons.notifications_none_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                            Positioned(
                              top: 9,
                              right: 9,
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFF97316),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Wallet Card Pill
                    GestureDetector(
                      onTap: () => context.push('/wallet'),
                      child: Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF222222),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFF2E2E2E)),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.account_balance_wallet_outlined,
                              color: AppColors.primary,
                              size: 16,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              '₹${realWalletBalance.toStringAsFixed(0)}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 3),
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: Color(0xFF94A3B8),
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Hero Card
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF222222),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF2E2E2E)),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      // Profile Avatar with Camera Icon Overlay.
                      // The whole avatar is the tap target, not just the small
                      // badge — a 20px circle is far too small to hit reliably.
                      GestureDetector(
                        onTap: () => _changeProfilePhoto(context, ref),
                        behavior: HitTestBehavior.opaque,
                        child: Stack(
                        children: [
                          Container(
                            width: 62,
                            height: 62,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF11191D),
                              border: Border.all(color: AppColors.primary, width: 2),
                              image: buildSafeDecorationImage(driver?.profileImage),
                            ),
                            child: buildSafeImageProvider(driver?.profileImage) == null
                                ? const Icon(
                                    Icons.person_rounded,
                                    color: Colors.white70,
                                    size: 36,
                                  )
                                : null,
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0xFF11191D), width: 1.5),
                              ),
                              child: const Icon(
                                Icons.camera_alt_rounded,
                                color: Color(0xFF11191D),
                                size: 10,
                              ),
                            ),
                          ),
                        ],
                        ),
                      ),

                      const SizedBox(width: 14),

                      // Driver Name, Phone & Status Badges
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              phone,
                              style: const TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                // Rating Pill
                                const Icon(Icons.star_rounded, color: Color(0xFFFFC107), size: 16),
                                const SizedBox(width: 4),
                                Text(
                                  rating,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(width: 10),

                                // Verified Pill Badge
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                                  ),
                                  child: const Row(
                                    children: [
                                      Icon(
                                        Icons.check_circle_rounded,
                                        color: AppColors.primary,
                                        size: 12,
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        'Verified',
                                        style: TextStyle(
                                          color: AppColors.primary,
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Dark Navy Blue Bottom Pill Capsule
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF11191D),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF2E2E2E)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Member Since
                        Row(
                          children: [
                            const Icon(
                              Icons.calendar_today_rounded,
                              color: Color(0xFF94A3B8),
                              size: 14,
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Member since',
                                  style: TextStyle(
                                    color: Color(0xFF94A3B8),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  driver?.createdAt == null
                                      ? '—'
                                      : DateFormat('MMM yyyy').format(toIst(driver!.createdAt!)),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),

                        // Total Trips
                        Row(
                          children: [
                            const Icon(
                              Icons.show_chart_rounded,
                              color: Color(0xFF94A3B8),
                              size: 15,
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Total trips',
                                  style: TextStyle(
                                    color: Color(0xFF94A3B8),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  totalTrips,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Section 1: Account
            const _SectionHeader(title: 'Account'),
            const SizedBox(height: 8),
            _MenuTile(
              iconBgColor: const Color(0xFF0F172A),
              iconColor: AppColors.primary,
              icon: Icons.person_outline_rounded,
              title: 'Edit Profile',
              subtitle: 'Name, email, photo',
              onTap: () => context.push('/edit-profile'),
            ),
            _MenuTile(
              iconBgColor: const Color(0xFF0F3854),
              iconColor: const Color(0xFF38BDF8),
              icon: Icons.directions_car_outlined,
              title: 'Vehicle Details',
              subtitle: driver?.vehicleNumber ?? 'DL01AD1234',
              onTap: () => context.push('/vehicle-details'),
            ),
            _MenuTile(
              iconBgColor: const Color(0xFF3B1D54),
              iconColor: const Color(0xFFC084FC),
              icon: Icons.assignment_outlined,
              title: 'Documents',
              subtitle: 'License, RC, insurance & more',
              onTap: () => context.push('/documents'),
            ),
            _MenuTile(
              iconBgColor: const Color(0xFF3D2E0A),
              iconColor: AppColors.primary,
              icon: Icons.home_outlined,
              title: 'Home Location',
              subtitle: 'For Go Home - rides on your way home',
              onTap: () => context.push('/home-location'),
            ),
            _MenuTile(
              iconBgColor: const Color(0xFF0C2E44),
              iconColor: const Color(0xFF38BDF8),
              icon: Icons.event_outlined,
              title: 'Scheduled Rides',
              subtitle: 'Your rides booked for later, and open ones',
              onTap: () => context.push('/scheduled-rides'),
            ),
            _MenuTile(
              iconBgColor: const Color(0xFF123A2E),
              iconColor: AppColors.primary,
              icon: Icons.language_rounded,
              title: 'profile.language'.tr(),
              subtitle: (AppLocales.nameKeys[context.locale.languageCode] ?? 'language.english').tr(),
              onTap: () => context.push('/language'),
            ),
            _MenuTile(
              iconBgColor: const Color(0xFF0F3854),
              iconColor: const Color(0xFF38BDF8),
              icon: Icons.verified_user_outlined,
              title: 'Insurance',
              subtitle: 'Vehicle & driver insurance policy',
              onTap: () => SnackbarUtils.info('Upcoming'),
            ),
            _MenuTile(
              iconBgColor: const Color(0xFF432808),
              iconColor: const Color(0xFFF59E0B),
              icon: Icons.build_circle_outlined,
              title: 'Vehicle on Maintenance',
              subtitle: 'Mark vehicle for service or repair',
              onTap: () => SnackbarUtils.info('Upcoming'),
            ),
            _MenuTile(
              iconBgColor: const Color(0xFF431D08),
              iconColor: const Color(0xFFFB923C),
              icon: Icons.account_balance_outlined,
              title: 'Bank Account',
              subtitle: 'Payout details',
              onTap: () => context.push('/bank-account'),
            ),
            if (subscriptionStatus?.enabled == true)
              _MenuTile(
                iconBgColor: subscriptionStatus!.isActive
                    ? const Color(0xFF0F172A)
                    : const Color(0xFF450A0A),
                iconColor: subscriptionStatus.isActive
                    ? AppColors.primary
                    : const Color(0xFFFCA5A5),
                icon: Icons.event_repeat_rounded,
                title: 'Daily Subscription',
                subtitle: _subscriptionSubtitle(subscriptionStatus),
                onTap: () => context.push('/subscription'),
              ),

            const SizedBox(height: 16),

            // Section 2: Safety & Support
            const _SectionHeader(title: 'Safety & Support'),
            const SizedBox(height: 8),
            _MenuTile(
              iconBgColor: const Color(0xFF450A0A),
              iconColor: const Color(0xFFFCA5A5),
              icon: Icons.shield_outlined,
              title: 'Safety Center',
              subtitle: 'Emergency contacts & SOS',
              onTap: () => context.push('/safety-center'),
            ),
            _MenuTile(
              iconBgColor: const Color(0xFF172554),
              iconColor: const Color(0xFF93C5FD),
              icon: Icons.headset_mic_outlined,
              title: 'Help & Support',
              subtitle: 'FAQs, chat with us',
              onTap: () => context.push('/help-center'),
            ),

            const SizedBox(height: 16),

            // Section 3: Preferences
            const _SectionHeader(title: 'Preferences'),
            const SizedBox(height: 8),
            _MenuTile(
              iconBgColor: const Color(0xFF1E293B),
              iconColor: const Color(0xFFCBD5E1),
              icon: Icons.settings_outlined,
              title: 'Settings',
              subtitle: 'Language, notifications, privacy',
              onTap: () => context.push('/settings'),
            ),

            const SizedBox(height: 16),

            // Logout Tile
            _MenuTile(
              iconBgColor: const Color(0xFF450A0A),
              iconColor: const Color(0xFFEF4444),
              icon: Icons.logout_rounded,
              title: 'Logout',
              subtitle: 'Sign out of your account',
              onTap: () async {
                await ref.read(authProvider.notifier).logout();
                if (context.mounted) context.go('/welcome');
              },
            ),
          ],
        ),
      ),
    );
  }
}

String _subscriptionSubtitle(SubscriptionStatus status) {
  if (status.isActive && status.expiresAt != null) {
    return 'Active - valid until ${DateFormat('h:mm a, d MMM').format(toIst(status.expiresAt!))}';
  }
  if (status.isActive) return 'Active';
  return 'Not subscribed - buy your daily pass';
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: Color(0xFF94A3B8),
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final Color iconBgColor;
  final Color iconColor;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuTile({
    required this.iconBgColor,
    required this.iconColor,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF222222),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2E2E2E)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: iconBgColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF94A3B8),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Replaces the driver's profile photo.
///
/// The camera badge on the avatar was decoration only — a Container with no
/// gesture handler — so tapping it did nothing at all. This does the pick,
/// upload and refresh in one step, rather than sending the driver off to the
/// edit screen to find the same control again.
Future<void> _changeProfilePhoto(BuildContext context, WidgetRef ref) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    backgroundColor: const Color(0xFF222222),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          const Text(
            'Profile photo',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 4),
          ListTile(
            leading: const Icon(Icons.camera_alt_rounded, color: AppColors.primary),
            title: const Text('Take a photo', style: TextStyle(color: Colors.white)),
            onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_rounded, color: AppColors.primary),
            title: const Text('Choose from gallery', style: TextStyle(color: Colors.white)),
            onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );

  if (source == null) return;

  try {
    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 800,
      preferredCameraDevice: CameraDevice.front,
    );
    if (picked == null) return;

    final bytes = await File(picked.path).readAsBytes();
    SnackbarUtils.info('Uploading photo…');

    await ref.read(profileRepositoryProvider).updateProfile(
          profileImage: 'data:image/jpeg;base64,${base64Encode(bytes)}',
        );
    // Re-reads the driver so the new photo shows immediately.
    await ref.read(authProvider.notifier).refresh();
    SnackbarUtils.success('Profile photo updated');
  } on ApiException catch (e) {
    SnackbarUtils.error(e.message);
  } catch (_) {
    SnackbarUtils.error('Could not update the photo. Please try again.');
  }
}

import '../../../core/constants/app_constants.dart';
import '../../kyc/application/kyc_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/utils/image_utils.dart';
import '../../../features/auth/application/auth_providers.dart';
import '../../../shared/widgets/app_bottom_navigation_bar.dart';
import '../../../shared/widgets/profile_tile.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  /// Shown only when KYC is on or the rider is already verified.
  List<Widget> _kycRow(BuildContext context, WidgetRef ref, Color dividerColor) {
    final kyc = ref.watch(kycStatusProvider).valueOrNull;
    if (kyc == null || !(kyc.config?.enabled == true || kyc.isVerified)) return const [];
    final subtitle = kyc.isVerified
        ? 'Verified · ${kyc.documentLabel} ${kyc.maskedNumber}'
        : kyc.underReview
            ? 'Under review'
            : 'Not verified yet';
    return [
      Divider(height: 1, color: dividerColor),
      ProfileTile(
        icon: Icons.verified_user_outlined,
        iconColor: const Color(0xFF10B981),
        title: 'Verify Identity',
        subtitle: subtitle,
        onTap: () async {
          await context.push('/profile/verify-identity');
          ref.invalidate(kycStatusProvider);
        },
      ),
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF11191D) : const Color(0xFFF8FAFC);
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final dividerColor = isDark ? const Color(0xFF2E2E2E) : const Color(0xFFF1F5F9);

    final user = ref.watch(authControllerProvider).user;
    final userName = (user?.name != null && user!.name.isNotEmpty) ? user.name : 'Add your name';
    final userPhone = (user?.phone != null && user!.phone.isNotEmpty) ? user.phone : '';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        context.go('/home');
      },
      child: Scaffold(
        backgroundColor: bgColor,
        bottomNavigationBar: const AppBottomNavigationBar(currentIndex: 3),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              // Screen Title Header
              Padding(
                padding: const EdgeInsets.only(left: 2, bottom: 16, top: 4),
                child: Text(
                  'Profile',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: textPrimary,
                    letterSpacing: -0.4,
                  ),
                ),
              ),

              // User Profile Header Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF222222) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark ? const Color(0xFF2E2E2E) : const Color(0xFFF1F5F9),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Stack(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFFF5B400),
                              width: 2.2,
                            ),
                          ),
                          child: CircleAvatar(
                            radius: 34,
                            backgroundColor: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFFFF4CC),
                            backgroundImage: buildSafeImageProvider(resolveMediaUrl(user?.profileImage)),
                            child: buildSafeImageProvider(resolveMediaUrl(user?.profileImage)) == null
                                ? const Icon(Icons.person_rounded, size: 38, color: Color(0xFFF5B400))
                                : null,
                          ),
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: GestureDetector(
                            onTap: () => context.push('/profile/edit'),
                            child: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF5B400),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isDark ? const Color(0xFF222222) : Colors.white,
                                  width: 2,
                                ),
                              ),
                              child: const Icon(
                                Icons.camera_alt_rounded,
                                size: 12,
                                color: Color(0xFF0A0A0A),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            userName,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: textPrimary,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            userPhone,
                            style: TextStyle(
                              fontSize: 13,
                              color: textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFF10B981).withValues(alpha: 0.25),
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.verified_user_rounded, size: 12, color: Color(0xFF10B981)),
                                SizedBox(width: 4),
                                Text(
                                  'Verified Profile',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF10B981),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => context.push('/profile/edit'),
                      child: Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF1F5F9),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isDark ? const Color(0xFF333333) : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: const Icon(Icons.edit_rounded, size: 17, color: Color(0xFFF5B400)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ACCOUNT & REWARDS
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 10),
                child: Text(
                  'ACCOUNT & REWARDS',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: textSecondary,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              _SectionCard(
                isDark: isDark,
                children: [
                  ProfileTile(
                    icon: Icons.bookmark_border_rounded,
                    iconColor: const Color(0xFFF5B400),
                    title: 'Saved Places',
                    subtitle: 'Home, work and favourite locations',
                    onTap: () => context.push('/profile/saved-places'),
                  ),
                  Divider(height: 1, color: dividerColor),
                  ProfileTile(
                    icon: Icons.card_giftcard_rounded,
                    iconColor: const Color(0xFFF5B400),
                    title: 'Rewards & Offers',
                    subtitle: 'Claim coupons and referral bonuses',
                    onTap: () => context.push('/rewards'),
                  ),
                  if (AppConstants.onlinePaymentsEnabled) ...[
                  Divider(height: 1, color: dividerColor),
                  ProfileTile(
                    icon: Icons.account_balance_wallet_outlined,
                    iconColor: const Color(0xFF10B981),
                    title: 'Payment & Wallet',
                    subtitle: 'Manage cards, UPI and transaction history',
                    onTap: () => context.push('/wallet'),
                  ),
                  ],
                  ..._kycRow(context, ref, dividerColor),
                ],
              ),
              const SizedBox(height: 20),

              // PREFERENCES & HELP
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 10),
                child: Text(
                  'PREFERENCES & HELP',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: textSecondary,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              _SectionCard(
                isDark: isDark,
                children: [
                  ProfileTile(
                    icon: Icons.notifications_none_rounded,
                    iconColor: const Color(0xFFF5B400),
                    title: 'Notifications',
                    subtitle: 'Trip alerts, offers and news',
                    onTap: () => context.push('/notifications'),
                  ),
                  Divider(height: 1, color: dividerColor),
                  ProfileTile(
                    icon: Icons.headset_mic_outlined,
                    iconColor: const Color(0xFF38BDF8),
                    title: 'Help & Support',
                    subtitle: 'FAQs, contact support and live chat',
                    onTap: () => context.push('/support'),
                  ),
                  Divider(height: 1, color: dividerColor),
                  ProfileTile(
                    icon: Icons.language_rounded,
                    iconColor: const Color(0xFFF5B400),
                    title: 'Language',
                    subtitle: 'Choose your preferred language',
                    onTap: () => context.push('/profile/language'),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ACCOUNT MANAGEMENT
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 10),
                child: Text(
                  'ACCOUNT MANAGEMENT',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: textSecondary,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              _SectionCard(
                isDark: isDark,
                children: [
                  ProfileTile(
                    icon: Icons.delete_outline_rounded,
                    iconColor: const Color(0xFFEF4444),
                    title: 'Delete Account',
                    subtitle: 'Request permanent removal of your account & data',
                    onTap: () => context.push('/profile/delete-account'),
                  ),
                  Divider(height: 1, color: dividerColor),
                  ProfileTile(
                    icon: Icons.logout_rounded,
                    iconColor: const Color(0xFFF5B400),
                    title: 'Logout',
                    subtitle: 'Sign out of your account on this device',
                    onTap: () => _showLogoutDialog(context, ref, isDark),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Center(
                child: Text(
                  'Kranti Cabs v1.0.0',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: textSecondary.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLogoutDialog(BuildContext context, WidgetRef ref, bool isDark) {
    final bgColor = isDark ? const Color(0xFF222222) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final borderColor = isDark ? const Color(0xFF2E2E2E) : const Color(0xFFE2E8F0);
    const goldColor = Color(0xFFF5B400);

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: borderColor, width: 1.2),
        ),
        backgroundColor: bgColor,
        elevation: 16,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Kranti Gold Logout Icon Badge
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: goldColor.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: goldColor.withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: goldColor.withValues(alpha: 0.22),
                      blurRadius: 16,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.logout_rounded,
                  color: goldColor,
                  size: 28,
                ),
              ),
              const SizedBox(height: 18),

              // Title with Kranti Gold accent
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: 'Log out of ',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: textPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const TextSpan(
                      text: 'Kranti Cabs',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: goldColor,
                        letterSpacing: -0.3,
                      ),
                    ),
                    TextSpan(
                      text: '?',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Message
              Text(
                'Are you sure you want to log out of your account?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),

              // Actions Row (Cancel & Logout)
              Row(
                children: [
                  // Cancel Button
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: textPrimary,
                          backgroundColor: isDark ? const Color(0xFF11191D) : const Color(0xFFF1F5F9),
                          side: BorderSide(
                            color: borderColor,
                            width: 1.2,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Logout Button (Kranti Gold)
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: goldColor,
                          foregroundColor: const Color(0xFF0A0A0A),
                          elevation: 0,
                          shadowColor: goldColor.withValues(alpha: 0.35),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () async {
                          Navigator.of(dialogContext).pop();
                          await ref.read(authControllerProvider.notifier).logout();
                          if (context.mounted) {
                            context.go('/auth/phone');
                          }
                        },
                        child: const Text(
                          'Logout',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF0A0A0A),
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final List<Widget> children;
  final bool isDark;

  const _SectionCard({
    required this.children,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final cardBgColor = isDark ? const Color(0xFF222222) : Colors.white;
    final borderColor = isDark ? const Color(0xFF2E2E2E) : const Color(0xFFF1F5F9);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }
}

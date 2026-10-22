import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../home/application/booking_state.dart';
import '../../home/application/home_providers.dart';
import '../application/delivery_booking_controller.dart';
import '../application/delivery_categories.dart';

/// Step 1 of the delivery flow: select vehicle category.
/// Matches reference UI with dynamic light & dark theme support,
/// 2x2 category tiles with plus buttons, Explore Rewards banner, and bottom trust badges.
class DeliveryVehicleScreen extends ConsumerStatefulWidget {
  /// The app module the rider tapped to get here (Zi Parcel, or any other
  /// module an admin has marked `delivery`) — narrows the vehicle list to
  /// what that module actually offers. Null means "no module context",
  /// which shows every delivery vehicle, same as before this existed.
  final String? moduleId;

  const DeliveryVehicleScreen({super.key, this.moduleId});

  @override
  ConsumerState<DeliveryVehicleScreen> createState() =>
      _DeliveryVehicleScreenState();
}

class _DeliveryVehicleScreenState extends ConsumerState<DeliveryVehicleScreen> {
  @override
  void initState() {
    super.initState();
    // Deferred to after the first frame: modifying a provider straight from
    // initState throws ("Tried to modify a provider while the widget tree
    // was building"), since the tree above this screen — including whatever
    // is listening to deliveryBookingProvider — is still being built out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(deliveryBookingProvider.notifier).setModule(widget.moduleId);
      _seedPickup();
    });
  }

  /// Seeds the pickup from the rider's current location so the flow opens with
  /// a usable address instead of an empty field.
  Future<void> _seedPickup() async {
    if (ref.read(deliveryBookingProvider).pickup != null) return;
    final position = await ref.read(currentPositionProvider.future);
    final address = await ref.read(currentAddressProvider.future);
    if (position == null || !mounted) return;

    ref
        .read(deliveryBookingProvider.notifier)
        .setPickup(
          BookingLocation(
            lat: position.latitude,
            lng: position.longitude,
            address: address.isNotEmpty ? address : 'Current location',
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pickup = ref.watch(deliveryBookingProvider).pickup;
    final addressAsync = ref.watch(currentAddressProvider);
    // '' means location is off; say so rather than "Fetching" forever.
    final currentAddr = addressAsync.isLoading
        ? 'Finding your location...'
        : ((addressAsync.valueOrNull ?? '').isNotEmpty
            ? addressAsync.valueOrNull!
            : 'Location off - enter pickup');
    final addressToDisplay =
        (pickup?.address != null && pickup!.address.isNotEmpty)
        ? pickup.address
        : currentAddr;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0F172A)
          : const Color(0xFFF8FAFC),
      body: SingleChildScrollView(
       // physics: const BouncingScrollPhysics(),
        child: Column(
          children: [
            // Top Extended Header Section
            _HeaderSection(
              address: addressToDisplay,
              onBack: () => Navigator.of(context).maybePop(),
              onAddressTap: () {
                context.push('/delivery/address');
              },
            ),

            // Content Area under Header
            Transform.translate(
              offset: const Offset(0, 0),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Column(
                  children: [
                    // Subheader Section: "Choose a Service"
                    Row(
                      children: [
                        Expanded(
                          child: Divider(
                            color: isDark
                                ? const Color(0xFF334155)
                                : const Color(0xFFE2E8F0),
                            thickness: 1,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            16.0,
                            18.0,
                            16.0,
                            0.0,
                          ),
                          child: Text(
                            'Choose a Service',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF0F172A),
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Divider(
                            color: isDark
                                ? const Color(0xFF334155)
                                : const Color(0xFFE2E8F0),
                            thickness: 1,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Select a vehicle for delivery service',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // 2x2 Category Cards Grid
                    GridView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.94,
                          ),
                      itemCount: kDeliveryCategories.length,
                      itemBuilder: (context, index) {
                        final category = kDeliveryCategories[index];
                        return _CategoryCardTile(
                          category: category,
                          index: index,
                          onTap: () {
                            ref
                                .read(deliveryBookingProvider.notifier)
                                .selectDeliveryCategory(category.id);
                            context.push('/delivery/address');
                          },
                        );
                      },
                    ),

                    const SizedBox(height: 16),

                    // Explore Rewards Banner
                    const _ExploreRewardsBanner(),

                    const SizedBox(height: 20),

                    // Bottom Trust Badges Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: const [
                        _TrustBadge(
                          icon: Icons.verified_user_rounded,
                          iconColor: Color(0xFF10B981),
                          title: 'Safety Assured',
                          subtitle: 'Verified Drivers',
                        ),
                        _TrustBadge(
                          icon: Icons.timer_rounded,
                          iconColor: Color(0xFFFF5C2B),
                          title: 'On-Time',
                          subtitle: 'Fast & Reliable',
                        ),
                        _TrustBadge(
                          icon: Icons.headset_mic_rounded,
                          iconColor: Color(0xFF3B82F6),
                          title: '24/7 Support',
                          subtitle: 'Always Active',
                        ),
                        _TrustBadge(
                          icon: Icons.account_balance_wallet_rounded,
                          iconColor: Color(0xFF8B5CF6),
                          title: 'Affordable',
                          subtitle: 'Best Rates',
                        ),
                      ],
                    ),

                    const SizedBox(height: 18),

                    // Bottom Ghosted Logistics Illustration
                    Center(
                      child: Opacity(
                        opacity: isDark ? 0.10 : 0.20,
                        child: Image.asset(
                          'assets/bottom_truck_bg.webp',
                          height: 95,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Top Extended Header containing Back Button & Pickup Address Card
class _HeaderSection extends StatelessWidget {
  final String address;
  final VoidCallback onBack;
  final VoidCallback onAddressTap;

  const _HeaderSection({
    required this.address,
    required this.onBack,
    required this.onAddressTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final topPadding = MediaQuery.of(context).padding.top;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
              : [const Color(0xFFFF8550), const Color(0xFFFF6933)],
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(26),
          bottomRight: Radius.circular(26),
        ),
        border: isDark
            ? const Border(
                bottom: BorderSide(color: Color(0xFF334155), width: 1),
              )
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: topPadding + 6),

          // Top Left Back Button (Translucent rounded button)
          Padding(
            padding: const EdgeInsets.only(left: 14.0, bottom: 10.0),
            child: Material(
              color: Colors.white.withValues(alpha: isDark ? 0.12 : 0.25),
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: IconButton(
                onPressed: onBack,
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: Colors.white,
                  size: 22,
                ),
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                padding: EdgeInsets.zero,
              ),
            ),
          ),

          // Pickup Card inside Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: InkWell(
              onTap: onAddressTap,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: isDark
                      ? Border.all(color: const Color(0xFF334155))
                      : null,
                  boxShadow: [
                    BoxShadow(
                      color: isDark ? Colors.black38 : const Color(0x1A000000),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Green Pin Location Badge
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF064E3B)
                            : const Color(0xFFE6F8F0),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Icon(
                          Icons.location_on_outlined,
                          color: isDark
                              ? const Color(0xFF34D399)
                              : const Color(0xFF10B981),
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Pickup Address Label & Text
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'PICK UP FROM',
                            style: TextStyle(
                              fontSize: 9.5,
                              letterSpacing: 0.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            address,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Right Chevron Arrow
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
        ],
      ),
    );
  }
}

/// Category Card Widget with 3D image asset, category badge, description, and accent plus button
class _CategoryCardTile extends StatelessWidget {
  final DeliveryCategory category;
  final int index;
  final VoidCallback onTap;

  const _CategoryCardTile({
    required this.category,
    required this.index,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final tagBgColorsLight = [
      const Color(0xFFFFF7ED), // Trucks
      const Color(0xFFEFF6FF), // 2 Wheeler
      const Color(0xFFF0FDF4), // Auto
      const Color(0xFFFAF5FF), // Movers
    ];

    final tagBgColorsDark = [
      const Color(0xFF451A03), // Trucks
      const Color(0xFF1E3A8A), // 2 Wheeler
      const Color(0xFF064E3B), // Auto
      const Color(0xFF4C1D95), // Movers
    ];

    final tagTextColorsLight = [
      AppColors.primaryOrange,
      const Color(0xFF3B82F6),
      const Color(0xFF10B981),
      const Color(0xFF8B5CF6),
    ];

    final tagTextColorsDark = [
      const Color(0xFFFF8550),
      const Color(0xFF60A5FA),
      const Color(0xFF34D399),
      const Color(0xFFA78BFA),
    ];

    final plusBtnColors = [
      AppColors.primaryOrange,
      const Color(0xFF3B82F6),
      const Color(0xFF10B981),
      const Color(0xFF8B5CF6),
    ];

    final tagBg = isDark
        ? tagBgColorsDark[index % tagBgColorsDark.length]
        : tagBgColorsLight[index % tagBgColorsLight.length];

    final tagText = isDark
        ? tagTextColorsDark[index % tagTextColorsDark.length]
        : tagTextColorsLight[index % tagTextColorsLight.length];

    final plusColor = plusBtnColors[index % plusBtnColors.length];

    String assetToUse = category.assetImage;
    if (assetToUse.isEmpty) {
      if (category.id == 'trucks') assetToUse = 'assets/truck_cat.webp';
      if (category.id == '2wheeler') assetToUse = 'assets/scooter_cat.webp';
      if (category.id == 'auto') assetToUse = 'assets/auto_cat.webp';
      if (category.id == 'movers') assetToUse = 'assets/movers_cat.png';
    }

    return Material(
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      borderRadius: BorderRadius.circular(20),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
            ),
            boxShadow: [
              BoxShadow(
                color: isDark ? Colors.black26 : const Color(0x0A000000),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          padding: const EdgeInsets.all(12),
          child: Stack(
            children: [
              // Top Right Category Tag
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2.5,
                  ),
                  decoration: BoxDecoration(
                    color: tagBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    category.title,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: tagText,
                    ),
                  ),
                ),
              ),

              // Main Content
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 10),
                  // Vehicle 3D Image
                  Expanded(
                    child: Center(
                      child: assetToUse.isNotEmpty
                          ? Image.asset(
                              assetToUse,
                              height: 74,
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) => Icon(
                                category.icon,
                                size: 44,
                                color: plusColor,
                              ),
                            )
                          : Icon(category.icon, size: 44, color: plusColor),
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Title Text
                  Text(
                    category.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13.5,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 1),

                  // Bottom Row: Description & Plus Action Button
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _getShortDesc(category.id),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF64748B),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: plusColor,
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.add_rounded,
                            color: Colors.white,
                            size: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getShortDesc(String id) {
    switch (id) {
      case 'trucks':
        return 'Mini trucks & pickups';
      case '2wheeler':
        return 'Fast small parcels';
      case 'auto':
        return 'Luggage & medium loads';
      case 'movers':
        return 'Van parcel delivery';
      default:
        return 'Quick delivery';
    }
  }
}

/// "Explore Rewards" Banner widget
class _ExploreRewardsBanner extends StatelessWidget {
  const _ExploreRewardsBanner();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: isDark
              ? [const Color(0xFFC2410C), const Color(0xFF9A3412)]
              : [const Color(0xFFFF7A45), AppColors.primaryOrange],
        ),
        boxShadow: [
          BoxShadow(
            color: isDark ? const Color(0x40000000) : const Color(0x2BFF5C2B),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Gold Coin Icon Badge
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFFDF00), Color(0xFFD4AF37)],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Center(
              child: Text(
                '\$',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                  shadows: [
                    Shadow(
                      color: Color(0x66000000),
                      blurRadius: 2,
                      offset: Offset(1, 1),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Title & Description
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Explore Rewards',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.2,
                  ),
                ),
                SizedBox(height: 1),
                Text(
                  'Earn 2 coins for every 100 spent',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFFFFEAE2),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),

          // Right Arrow Button
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.25),
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Icon(
                Icons.arrow_forward_rounded,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Trust Badge Item for bottom bar
class _TrustBadge extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;

  const _TrustBadge({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: isDark ? 0.20 : 0.10),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: iconColor, size: 17),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
        ),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 8.5,
            fontWeight: FontWeight.w500,
            color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
          ),
        ),
      ],
    );
  }
}

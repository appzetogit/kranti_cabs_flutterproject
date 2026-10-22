import '../../kyc/application/kyc_providers.dart';
import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/utils/image_utils.dart';
import '../../../core/utils/snackbar_utils.dart';
import '../../../shared/widgets/app_bottom_navigation_bar.dart';
import '../../../shared/widgets/exit_confirmation_dialog.dart';
import '../../auth/application/auth_providers.dart';
import '../../notifications/application/notifications_providers.dart';
import '../../ride/application/ride_providers.dart';
import '../application/booking_controller.dart';
import '../application/booking_state.dart';
import '../application/home_providers.dart';
import '../application/saved_places_provider.dart';
import 'location_access.dart';
import '../data/models/app_module_model.dart';
import '../data/models/saved_address_model.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late PageController _pageController;
  final _scroll = ScrollController();
  final _pinned = ValueNotifier<bool>(false);
  Timer? _bannerTimer;
  Timer? _bannerRefreshTimer;
  int _currentBannerIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    _startBannerAutoSlide();
    _bannerRefreshTimer = Timer.periodic(
      const Duration(minutes: 10),
      (_) => ref.invalidate(bannersProvider),
    );
    _scroll.addListener(() => _pinned.value = _scroll.offset > 164);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(bookingControllerProvider.notifier).loadCatalog();
      _maybePromptKyc();
    });
  }

  /// Once per app session: bookings are blocked server-side regardless, so the
  /// rider may simply go back.
  static bool _kycPrompted = false;

  Future<void> _maybePromptKyc() async {
    if (_kycPrompted) return;
    _kycPrompted = true;
    try {
      final s = await ref.read(kycRepositoryProvider).status();
      final c = s.config;
      if (!mounted || c == null || !c.enabled || c.requiredFor != 'after_signup') return;
      if (s.isVerified || s.underReview) return;
      context.push('/profile/verify-identity');
    } catch (_) {
      // Best-effort prompt; a failed lookup just skips it.
    }
  }

  void _startBannerAutoSlide() {
    _bannerTimer?.cancel();
    _bannerTimer = Timer.periodic(
      const Duration(seconds: 3, milliseconds: 500),
      (timer) {
        if (!mounted) return;
        final count = _bannerCount;
        if (count <= 1) return;

        final nextIndex = (_currentBannerIndex + 1) % count;
        if (_pageController.hasClients) {
          if (nextIndex == 0) {
            _pageController.animateToPage(
              0,
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeInOut,
            );
          } else {
            _pageController.nextPage(
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeInOut,
            );
          }
        }
      },
    );
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _bannerRefreshTimer?.cancel();
    _pageController.dispose();
    _scroll.dispose();
    _pinned.dispose();
    super.dispose();
  }

  List<Map<String, String>> _getBannerList() {
    final banners = ref.watch(bannersProvider).valueOrNull ?? const [];
    if (banners.isNotEmpty) {
      return banners
          .map(
            (b) => {
              'image': (b['image'] ?? '').toString(),
              'link':
                  (b['redirect_url'] ??
                          b['external_link'] ??
                          b['deep_link'] ??
                          b['link'] ??
                          '')
                      .toString(),
            },
          )
          .toList();
    }
    return const [
      {'image': 'assets/banner.webp', 'link': ''},
      {'image': 'assets/banner.webp', 'link': ''},
    ];
  }

  int get _bannerCount => _getBannerList().length;

  Widget _buildPromoBanner() {
    final banners = _getBannerList();

    return SizedBox(
      height: 130,
      width: double.infinity,
      child: PageView.builder(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() {
            _currentBannerIndex = index;
          });
        },
        itemCount: banners.length,
        itemBuilder: (context, index) {
          final item = banners[index];
          final img = item['image'] ?? '';
          final link = item['link'] ?? '';

          Widget imageWidget;
          // The CMS stores banner images as server-relative paths, so testing
          // for `http` alone always fell through to the bundled placeholder —
          // the same bug the module icons had.
          final resolvedImg = resolveMediaUrl(img);
          if (resolvedImg.startsWith('http')) {
            imageWidget = CachedNetworkImage(
              imageUrl: resolvedImg,
              fit: BoxFit.cover,
              width: double.infinity,
              height: 130,
              placeholder: (context, url) =>
                  Image.asset('assets/banner.webp', fit: BoxFit.cover),
              errorWidget: (context, url, error) =>
                  Image.asset('assets/banner.webp', fit: BoxFit.cover),
            );
          } else {
            imageWidget = Image.asset(
              resolvedImg.startsWith('assets/')
                  ? resolvedImg
                  : 'assets/banner.webp',
              fit: BoxFit.cover,
              width: double.infinity,
              height: 130,
              errorBuilder: (context, error, stackTrace) =>
                  Image.asset('assets/banner.webp', fit: BoxFit.cover),
            );
          }

          return GestureDetector(
            onTap: link.isEmpty ? null : () => _openBannerLink(link),
            child: imageWidget,
          );
        },
      ),
    );
  }

  Future<void> _openBannerLink(String link) async {
    if (link.startsWith('/')) {
      if (mounted) context.push(link);
      return;
    }
    final uri = Uri.tryParse(link);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// The pickup for a Home/Work shortcut: the rider's location, or - when
  /// that is off and stays off - a point they choose on the map. Null when
  /// they back out of both.
  Future<BookingLocation?> _resolvePickupForShortcut() async {
    var position = await ref.read(currentPositionProvider.future);
    if (position == null && mounted) {
      final ok = await requestLocationAccess(context, ref);
      if (ok) position = await ref.read(currentPositionProvider.future);
    }

    if (position != null) {
      final address = await ref.read(currentAddressProvider.future);
      return BookingLocation(
        lat: position.latitude,
        lng: position.longitude,
        address: address.isNotEmpty ? address : 'Current location',
      );
    }

    if (!mounted) return null;
    final picked = await context.push<Map<String, dynamic>>(
      '/home/map-picker?type=pickup',
    );
    final address = (picked?['address'] ?? '').toString();
    final lat = (picked?['lat'] as num?)?.toDouble() ?? 0;
    final lng = (picked?['lng'] as num?)?.toDouble() ?? 0;
    if (address.isEmpty || (lat == 0 && lng == 0)) return null;
    return BookingLocation(lat: lat, lng: lng, address: address);
  }

  Future<void> _handleHomeWorkTap(
    String slotType,
    SavedAddressModel? saved,
  ) async {
    if (saved == null) {
      final result = await context.push<Map<String, dynamic>>(
        '/home/map-picker?type=drop',
      );
      if (result != null && mounted) {
        final String addr = result['address'] ?? '';
        final double lat = (result['lat'] as num?)?.toDouble() ?? 0;
        final double lng = (result['lng'] as num?)?.toDouble() ?? 0;
        if (addr.isNotEmpty && lat != 0 && lng != 0) {
          await ref
              .read(savedPlacesProvider.notifier)
              .saveHomeOrWork(
                type: slotType,
                address: addr,
                lat: lat,
                lng: lng,
              );
          if (mounted) {
            SnackbarUtils.info(
              context,
              '${slotType.toLowerCase() == 'home' ? 'Home' : 'Work'} location saved!',
            );
          }
        }
      }
    } else {
      // Pickup is where the rider is. When that is unknown it used to be
      // set to Indore, so a Home/Work tap from Bengaluru with location off
      // booked from Indore. Ask for location, and failing that let the rider
      // point at their pickup on the map.
      final pickupLoc = await _resolvePickupForShortcut();
      if (pickupLoc == null || !mounted) return;

      final dropLoc = BookingLocation(
        lat: saved.lat,
        lng: saved.lng,
        address: saved.address,
      );

      ref.read(bookingControllerProvider.notifier)
        ..setPickup(pickupLoc)
        ..setDrop(dropLoc);

      if (mounted) {
        context.push('/home/ride-types');
      }
    }
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) return 'Good morning,';
    if (hour >= 12 && hour < 17) return 'Good afternoon,';
    if (hour >= 17 && hour < 22) return 'Good evening,';
    return 'Good night,';
  }

  Widget _buildOngoingRideCard(BuildContext context) {
    final ride = ref.watch(myActiveRideProvider).valueOrNull;
    if (ride == null) return const SizedBox.shrink();

    const finished = {'completed', 'cancelled', 'canceled'};
    if (finished.contains(ride.liveStatus) || finished.contains(ride.status)) {
      return const SizedBox.shrink();
    }

    final isScheduled =
        ride.scheduledAt != null && ride.scheduledAt!.isAfter(DateTime.now());

    String statusTitle = 'ONGOING RIDE';
    IconData statusIcon = Icons.local_taxi_rounded;
    Color statusBadgeBg = const Color(0xFFF5B400);
    Color statusTextColor = const Color(0xFF0A0A0A);

    if (isScheduled || ride.status == 'scheduled') {
      statusTitle = 'SCHEDULED RIDE';
      statusIcon = Icons.access_time_filled_rounded;
      statusBadgeBg = const Color(0xFF1E88E5);
      statusTextColor = Colors.white;
    } else if (ride.liveStatus == 'accepted' || ride.liveStatus == 'arriving') {
      statusTitle = 'DRIVER ON THE WAY';
      statusIcon = Icons.directions_car_filled_rounded;
    } else if (ride.liveStatus == 'arrived') {
      statusTitle = 'DRIVER ARRIVED';
      statusIcon = Icons.where_to_vote_rounded;
      statusBadgeBg = const Color(0xFF10B981);
      statusTextColor = Colors.white;
    } else if (ride.liveStatus == 'started' || ride.liveStatus == 'ongoing') {
      statusTitle = 'TRIP IN PROGRESS';
      statusIcon = Icons.navigation_rounded;
    }

    final fareText = ride.fare > 0
        ? '₹${ride.fare.toStringAsFixed(ride.fare.truncateToDouble() == ride.fare ? 0 : 2)}'
        : '';

    final pickupText = ride.pickupAddress.isNotEmpty
        ? ride.pickupAddress
        : 'Pickup location';
    final dropText = ride.dropAddress.isNotEmpty
        ? ride.dropAddress
        : 'Drop location';

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: GestureDetector(
        onTap: () async {
          await context.push('/ride/tracking/${ride.rideId}');
          if (context.mounted) ref.invalidate(myActiveRideProvider);
        },
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF222222),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFF5B400), width: 1.5),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33F5B400),
                blurRadius: 16,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: statusBadgeBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(statusIcon, size: 14, color: statusTextColor),
                          const SizedBox(width: 5),
                          Text(
                            statusTitle,
                            style: TextStyle(
                              color: statusTextColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        if (fareText.isNotEmpty) ...[
                          Text(
                            fareText,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.arrow_forward_ios_rounded,
                            color: Colors.white,
                            size: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFF2A2A2A)),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Row(
                  children: [
                    Column(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFFF5B400),
                            shape: BoxShape.circle,
                          ),
                        ),
                        Container(
                          width: 2,
                          height: 18,
                          color: const Color(0xFF2A2A2A),
                        ),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFFEF4444),
                            borderRadius: BorderRadius.all(Radius.circular(2)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pickupText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            dropText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFB0BEC5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final displayName = (user?.name != null && user!.name.isNotEmpty)
        ? user.name.split(' ').first
        : 'there';

    // Shown under "Pickup location". This used to fall back to a fixed
    // "415, Gandhi Nagar, Bengaluru" while loading, on error and with location
    // off - so every rider without a fix was told they were in Gandhi Nagar.
    final addressAsync = ref.watch(currentAddressProvider);
    final locationOff = addressAsync.hasValue && addressAsync.value!.isEmpty;
    final pickupAddress = addressAsync.when(
      data: (addr) => addr.isNotEmpty ? addr : 'Location off - tap to turn on',
      loading: () => 'Finding your location...',
      error: (e, st) => 'Location unavailable - tap to retry',
    );

    final unreadCount = ref.watch(unreadNotificationsCountProvider);
    const bgColor = Color(0xFF11191D); // Dark Grey Theme
    const cardBgColor = Color(0xFF222222); // Dark Grey Card

    // Admin-configured transparent decorations for the very top of the home
    // screen (festival garland, lights, ...). Empty when none is set.
    final topBanners = ref.watch(homeTopBannersProvider).valueOrNull ?? const [];
    final hasTopImage = topBanners.isNotEmpty;

    final searchCard =                           Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: cardBgColor,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: const Color(0xFF2E2E2E),
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 12,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Stack(
                              children: [
                                Positioned(
                                  right: 0,
                                  top: 0,
                                  width: 170,
                                  height: 100,
                                  child: Opacity(
                                    opacity: 0.85,
                                    child: Image.asset(
                                      'assets/search.webp',
                                      fit: BoxFit.cover,
                                      alignment: Alignment.topRight,
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              const SizedBox.shrink(),
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(15.0),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            width: 8,
                                            height: 8,
                                            decoration: const BoxDecoration(
                                              color: Color(0xFFF5B400),
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          const Text(
                                            'Pickup location',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFFB0BEC5),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 3),
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          left: 16.0,
                                        ),
                                        child: ConstrainedBox(
                                          constraints: BoxConstraints(
                                            maxWidth:
                                                MediaQuery.of(
                                                  context,
                                                ).size.width *
                                                0.52,
                                          ),
                                          child: GestureDetector(
                                            // Only does anything when there is
                                            // no location to show.
                                            onTap: locationOff || addressAsync.hasError
                                                ? () => requestLocationAccess(context, ref)
                                                : null,
                                            child: Text(
                                              pickupAddress,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 13.5,
                                                fontWeight: FontWeight.w700,
                                                color: locationOff || addressAsync.hasError
                                                    ? const Color(0xFFFFB020)
                                                    : Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),

                                      const SizedBox(height: 12),

                                      // Search Bar Box (1:1 Matching Reference Screenshot)
                                      InkWell(
                                        onTap: () => context.push(
                                          '/search',
                                          // Same as tapping the "Kranti City Ride"
                                          // tile below — a bare "Where are you
                                          // going?" tap is a city ride, so it
                                          // should scope the vehicle list to
                                          // that module the same way.
                                          extra: 'Kranti City Ride',
                                        ),
                                        borderRadius: BorderRadius.circular(26),
                                        child: Container(
                                          padding: const EdgeInsets.fromLTRB(
                                            14,
                                            5,
                                            5,
                                            5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF11191D),
                                            borderRadius: BorderRadius.circular(
                                              26,
                                            ),
                                            border: Border.all(
                                              color: const Color(0xFF2E2E2E),
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              const Icon(
                                                Icons.location_on_outlined,
                                                color: Color(0xFFF5B400),
                                                size: 20,
                                              ),
                                              const SizedBox(width: 10),
                                              const Expanded(
                                                child: Text(
                                                  'Where are you going?',
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w500,
                                                    color: Color(0xFF94A3B8),
                                                  ),
                                                ),
                                              ),
                                              Container(
                                                width: 38,
                                                height: 38,
                                                decoration: const BoxDecoration(
                                                  color: Color(0xFFF5B400),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(
                                                  Icons.search_rounded,
                                                  color: Color(0xFF0A0A0A),
                                                  size: 20,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldExit = await showExitConfirmationDialog(context);
        if (shouldExit == true) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: bgColor,
        body: Stack(
          children: [
            SafeArea(
          top: false,
          bottom: false,
          child: Stack(
            children: [
              SingleChildScrollView(
                controller: _scroll,
               // physics: const BouncingScrollPhysics(),
                // A top decoration overlays the header, so push the content down
                // a little to give it room when one is set.
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 12,
                  bottom: MediaQuery.of(context).padding.bottom + 90,
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Hero banner behind the header; fades into the page background.
            Positioned(
              // Scroll padding sits above this Stack, so reach back over it
              // (status bar + 12) to start at the very top of the screen.
              top: -(MediaQuery.of(context).padding.top + 12),
              left: 0,
              right: 0,
              height: MediaQuery.of(context).padding.top + 252,
              child: IgnorePointer(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if ((ref.watch(bannersProvider).valueOrNull ?? const []).isNotEmpty)
                      _buildPromoBanner()
                    else if (hasTopImage)
                      _TopBannerStrip(images: topBanners),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xCC000000), Color(0x22000000), bgColor],
                          stops: [0, 0.6, 1],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
                    Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // --- 1. TOP HEADER BAR ---
                          Row(
                            children: [
                              // Hamburger Menu Icon
                              IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                icon: const Icon(
                                  Icons.menu_rounded,
                                  color: Colors.white,
                                  size: 24,
                                ),
                                onPressed: () {
                                  context.push('/profile');
                                },
                              ),
                              const SizedBox(width: 12),

                              // Greeting Text Column
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _getGreeting(),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: Color(0xFFB0BEC5),
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        Text(
                                          displayName,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.white,
                                            letterSpacing: -0.3,
                                          ),
                                        ),
                                        const SizedBox(width: 5),
                                        const Text(
                                          '👋',
                                          style: TextStyle(fontSize: 16),
                                        ),
                                      ],
                                    ),
                                    const Text(
                                      "Let's move with Kranti Cabs!",
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        color: Color(0xFF94A3B8),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Notification Bell with Badge
                              Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: cardBgColor,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: const Color(0xFF2E2E2E),
                                      ),
                                    ),
                                    child: IconButton(
                                      padding: EdgeInsets.zero,
                                      icon: const Icon(
                                        Icons.notifications_outlined,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                      onPressed: () {
                                        context.push('/notifications');
                                      },
                                    ),
                                  ),
                                  if (unreadCount > 0)
                                    Positioned(
                                      top: 2,
                                      right: 2,
                                      child: Container(
                                        padding: const EdgeInsets.all(3.5),
                                        decoration: const BoxDecoration(
                                          color: Color(0xFFF5B400),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Text(
                                          '$unreadCount',
                                          style: const TextStyle(
                                            color: Color(0xFF0A0A0A),
                                            fontSize: 9,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(width: 8),

                              // Profile Avatar Icon
                              GestureDetector(
                                onTap: () => context.push('/profile'),
                                child: Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: cardBgColor,
                                    border: Border.all(
                                      color: const Color(0xFF2E2E2E),
                                    ),
                                    image: buildSafeDecorationImage(
                                      resolveMediaUrl(user?.profileImage),
                                    ),
                                  ),
                                  child:
                                      buildSafeImageProvider(
                                            resolveMediaUrl(user?.profileImage),
                                          ) ==
                                          null
                                      ? const Icon(
                                          Icons.person_outline_rounded,
                                          color: Colors.white,
                                          size: 20,
                                        )
                                      : null,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),

                          // --- 2. PICKUP & SEARCH CARD ---
                          // Leaves the banner visible between header and card
                          const SizedBox(height: 120),
                          searchCard,

                          const SizedBox(height: 14),

                          // --- 3. QUICK SHORTCUT CARDS ROW (Work, Home, Saved 1:1 Matching Reference Design) ---
                          Builder(
                            builder: (context) {
                              final savedPlaces = ref.watch(
                                savedPlacesProvider,
                              );
                              final workPlace = savedPlaces.firstWhere(
                                (e) =>
                                    e.type.toLowerCase() == 'work' ||
                                    e.label.toLowerCase() == 'work',
                                orElse: () => const SavedAddressModel(
                                  id: '',
                                  label: 'Work',
                                  address: '',
                                  lat: 0,
                                  lng: 0,
                                  type: 'work',
                                ),
                              );
                              final homePlace = savedPlaces.firstWhere(
                                (e) =>
                                    e.type.toLowerCase() == 'home' ||
                                    e.label.toLowerCase() == 'home',
                                orElse: () => const SavedAddressModel(
                                  id: '',
                                  label: 'Home',
                                  address: '',
                                  lat: 0,
                                  lng: 0,
                                  type: 'home',
                                ),
                              );

                              return Row(
                                children: [
                                  // 1. Work Card
                                  _QuickShortcutCard(
                                    icon: Icons.work_rounded,
                                    iconColor: const Color(0xFF1E88E5),
                                    title: 'Work',
                                    subtitle: workPlace.address.isNotEmpty
                                        ? workPlace.address
                                        : 'Set location',
                                    // Unset -> drop a pin on the map and save it.
                                    // Set -> straight to picking a vehicle, with
                                    // pickup and drop already filled in.
                                    onTap: () => _handleHomeWorkTap(
                                      'work',
                                      workPlace.address.isEmpty
                                          ? null
                                          : workPlace,
                                    ),
                                  ),
                                  const SizedBox(width: 8),

                                  // 2. Home Card
                                  _QuickShortcutCard(
                                    icon: Icons.home_rounded,
                                    iconColor: const Color(0xFFEF4444),
                                    title: 'Home',
                                    subtitle: homePlace.address.isNotEmpty
                                        ? homePlace.address
                                        : 'Set location',
                                    onTap: () => _handleHomeWorkTap(
                                      'home',
                                      homePlace.address.isEmpty
                                          ? null
                                          : homePlace,
                                    ),
                                  ),
                                  const SizedBox(width: 8),

                                  // 3. Saved Card
                                  _QuickShortcutCard(
                                    icon: Icons.star_rounded,
                                    iconColor: const Color(0xFFFFB800),
                                    title: 'Saved',
                                    subtitle: 'Your places',
                                    onTap: () =>
                                        context.push('/home/saved-places'),
                                  ),
                                ],
                              );
                            },
                          ),

                          const SizedBox(height: 14),

                          // --- 4b. ONGOING/SCHEDULED RIDE CARD ---
                          // Shrinks to nothing when there's no active ride —
                          // always in the tree so it appears the instant one
                          // starts, without a rebuild to insert it.
                          _buildOngoingRideCard(context),

                          const SizedBox(height: 8),

                          // --- 5. SERVICES / MODULES SECTION HEADER ---
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Kranti Services',
                                style: TextStyle(
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              GestureDetector(
                                onTap: () => context.push('/home/all-services'),
                                child: const Row(
                                  children: [
                                    Text(
                                      'View All',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                    SizedBox(width: 2),
                                    Icon(
                                      Icons.chevron_right_rounded,
                                      color: Color(0xFFF5B400),
                                      size: 16,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 10),

                          // Dynamic Backend App Modules Grid (with fallbacks if empty)
                          _buildDynamicServicesGrid(),

                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // --- 7. BOTTOM BRAND BANNER ARTWORK (#KrantiCabs Made for India) ---
                    _buildBottomBanner(),
                  ],
                ),
                  ],
                ),
              ),

              // Search card pinned under the status bar once scrolled past.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: ValueListenableBuilder<bool>(
                  valueListenable: _pinned,
                  builder: (_, pinned, _) => pinned
                      ? Container(
                          color: bgColor,
                          padding: EdgeInsets.fromLTRB(
                            16,
                            MediaQuery.of(context).padding.top + 8,
                            16,
                            8,
                          ),
                          child: searchCard,
                        )
                      : const SizedBox.shrink(),
                ),
              ),

              // --- BOTTOM NAVIGATION BAR ---
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: AppBottomNavigationBar(currentIndex: 0),
              ),
            ],
          ),
        ),
            // Transparent decoration pinned to the very top of the screen,
            // over the status-bar area, so an admin's garland/lights image
            // hangs above the header. Ignores touches so the header stays tappable.
          ],
        ),
      ),
    );
  }

  /// Bottom brand artwork banner.
  Widget _buildBottomBanner() {
    return Image.asset(
      'assets/bottom_banner.png',
      width: double.infinity,
      fit: BoxFit.fitWidth,
      errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
    );
  }

  /// Dynamic Backend Modules grid renderer: 2 full-width cards on top, 3 cards below (Real Data)
  Widget _buildDynamicServicesGrid() {
    final modulesAsync = ref.watch(appModulesProvider);

    return modulesAsync.when(
      data: (modules) {
        final activeModules = modules.where((m) => m.active).toList();
        if (activeModules.isNotEmpty) {
          return _buildModulesGrid(activeModules);
        }
        return _buildFallbackServicesGrid();
      },
      loading: () => _buildShimmerServicesGrid(),
      error: (error, stack) => _buildFallbackServicesGrid(),
    );
  }

  Widget _buildModulesGrid(List<AppModuleModel> modules) {
    final sortedModules = List<AppModuleModel>.from(modules)
      ..sort((a, b) => _modulePriority(a).compareTo(_modulePriority(b)));

    const double spacing = 10.0;

    // Top row: first 2 modules taking full width (split 50-50)
    final topModules = sortedModules.take(2).toList();
    // Bottom row: remaining modules (3 cards below)
    final bottomModules = sortedModules.skip(2).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. TOP ROW: 2 Cards covering the full screen width
        Row(
          children: [
            for (int i = 0; i < topModules.length; i++) ...[
              if (i > 0) const SizedBox(width: spacing),
              Expanded(
                child: _KrantiServiceCard(
                  title: topModules[i].name,
                  subtitle: topModules[i].shortDescription.isNotEmpty
                      ? topModules[i].shortDescription
                      : _subtitleForModule(topModules[i]),
                  imageUrl: topModules[i].mobileMenuIcon,
                  fallbackAsset: _fallbackAssetForModule(topModules[i].name),
                  badgeIcon: _badgeIconForModule(topModules[i]),
                  isFeatured: true,
                  onTap: () => _onModuleTap(topModules[i]),
                ),
              ),
            ],
          ],
        ),

        if (bottomModules.isNotEmpty) ...[
          const SizedBox(height: spacing),

          // 2. BOTTOM ROW: 3 Cards dividing the full width
          Row(
            children: [
              for (int i = 0; i < bottomModules.length; i++) ...[
                if (i > 0) const SizedBox(width: spacing),
                Expanded(
                  child: _KrantiServiceCard(
                    title: bottomModules[i].name,
                    subtitle: bottomModules[i].shortDescription.isNotEmpty
                        ? bottomModules[i].shortDescription
                        : _subtitleForModule(bottomModules[i]),
                    imageUrl: bottomModules[i].mobileMenuIcon,
                    fallbackAsset: _fallbackAssetForModule(bottomModules[i].name),
                    badgeIcon: _badgeIconForModule(bottomModules[i]),
                    isFeatured: false,
                    onTap: () => _onModuleTap(bottomModules[i]),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }

  int _modulePriority(AppModuleModel m) {
    if (m.orderBy > 1) return m.orderBy;
    final lower = m.name.toLowerCase();
    if (lower.contains('instant') || lower.contains('city')) return 1;
    if (lower.contains('outstation')) return 2;
    if (lower.contains('rental')) return 3;
    if (lower.contains('airport')) return 4;
    if (lower.contains('railway')) return 5;
    return 10;
  }

  void _onModuleTap(AppModuleModel module) {
    if (module.name.toLowerCase().contains('bus') ||
        module.serviceType.toLowerCase().contains('bus') ||
        module.transportType.toLowerCase().contains('bus')) {
      SnackbarUtils.info(context, 'Feature is Upcoming...');
      return;
    }
    final route = _routeForModule(module);
    final targetRoute = route == '/search' ? '/home/search' : route;
    final finalRoute = targetRoute.contains('?')
        ? targetRoute
        : '$targetRoute?title=${Uri.encodeComponent(module.name)}';
    context.push(finalRoute, extra: module.name);
  }

  Widget _buildShimmerServicesGrid() {
    const double spacing = 10.0;

    return Column(
      children: [
        // Top 2 cards shimmer (covering full width)
        Row(
          children: [
            Expanded(
              child: Shimmer.fromColors(
                baseColor: const Color(0xFF222222),
                highlightColor: const Color(0xFF2E2E2E),
                child: Container(
                  height: 116,
                  decoration: BoxDecoration(
                    color: const Color(0xFF222222),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
            const SizedBox(width: spacing),
            Expanded(
              child: Shimmer.fromColors(
                baseColor: const Color(0xFF222222),
                highlightColor: const Color(0xFF2E2E2E),
                child: Container(
                  height: 116,
                  decoration: BoxDecoration(
                    color: const Color(0xFF222222),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: spacing),
        // Bottom 3 cards shimmer
        Row(
          children: [
            for (int i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: spacing),
              Expanded(
                child: Shimmer.fromColors(
                  baseColor: const Color(0xFF222222),
                  highlightColor: const Color(0xFF2E2E2E),
                  child: Container(
                    height: 104,
                    decoration: BoxDecoration(
                      color: const Color(0xFF222222),
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  IconData _badgeIconForModule(AppModuleModel module) {
    final lower =
        '${module.name} ${module.serviceType} ${module.transportType}'
            .toLowerCase();
    if (lower.contains('instant') ||
        lower.contains('city') ||
        lower.contains('time')) {
      return Icons.access_time_filled_rounded;
    }
    if (lower.contains('airport') ||
        lower.contains('railway') ||
        lower.contains('parking')) {
      return Icons.local_parking_rounded;
    }
    if (lower.contains('rental') || lower.contains('key')) {
      return Icons.vpn_key_rounded;
    }
    if (lower.contains('subscription') ||
        lower.contains('vip') ||
        lower.contains('crown')) {
      return Icons.workspace_premium_rounded;
    }
    if (lower.contains('outstation')) {
      return Icons.add_road_rounded;
    }
    if (lower.contains('parcel') || lower.contains('delivery')) {
      return Icons.inventory_2_rounded;
    }
    if (lower.contains('bus')) {
      return Icons.directions_bus_rounded;
    }
    return Icons.local_taxi_rounded;
  }

  String _fallbackAssetForModule(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('instant') || lower.contains('city')) {
      return 'assets/service_instant.webp';
    }
    if (lower.contains('airport')) return 'assets/service_airport.webp';
    if (lower.contains('railway')) return 'assets/service_railway.webp';
    if (lower.contains('rental')) return 'assets/service_rental.webp';
    if (lower.contains('outstation')) return 'assets/service_outstation.webp';
    return 'assets/service_instant.webp';
  }

  static String _routeForModule(AppModuleModel module) {
    final tt = module.transportType.toLowerCase();
    final st = module.serviceType.toLowerCase();
    if (tt == 'delivery' || st == 'delivery') {
      return '/delivery/vehicle?moduleId=${Uri.encodeComponent(module.id)}';
    }
    if (st == 'rental') return '/rental';

    final query = <String>[
      'moduleId=${Uri.encodeComponent(module.id)}',
      'title=${Uri.encodeComponent(module.name)}',
      if (st == 'outstation') 'outstation=1',
    ].join('&');

    return '/home/search?$query';
  }

  static String _subtitleForModule(AppModuleModel module) {
    final nameLower = module.name.toLowerCase();
    if (nameLower.contains('airport')) return 'Airport Transfers';
    if (nameLower.contains('city')) return 'Ride in City';
    if (nameLower.contains('parcel') || nameLower.contains('delivery')) {
      return 'Parcel Delivery';
    }
    if (nameLower.contains('outstation')) return 'Outstation Trips';
    if (nameLower.contains('bus')) return 'Bus Tickets';
    return 'Ride & Delivery';
  }

  /// Builds Kranti Services Grid fallback (2 on top covering full width, 3 below)
  Widget _buildFallbackServicesGrid() {
    final topServices = [
      _FallbackServiceData(
        title: 'Instant Booking',
        subtitle: 'Book a ride instantly',
        assetImage: 'assets/service_instant.webp',
        badgeIcon: Icons.access_time_filled_rounded,
        onTap: () => context.push(
          '/home/search?title=Instant%20Booking',
          extra: 'Instant Booking',
        ),
      ),
      _FallbackServiceData(
        title: 'Outstation',
        subtitle: 'One Way & Round Trip',
        assetImage: 'assets/service_outstation.webp',
        badgeIcon: Icons.add_road_rounded,
        onTap: () => context.push(
          '/home/search?title=Outstation&outstation=1',
          extra: 'Outstation',
        ),
      ),
    ];

    final bottomServices = [
      _FallbackServiceData(
        title: 'Car rental',
        subtitle: 'Hourly, Daily & Long Term',
        assetImage: 'assets/service_rental.webp',
        badgeIcon: Icons.vpn_key_rounded,
        onTap: () => context.push('/rental'),
      ),
      _FallbackServiceData(
        title: 'Airport Parking',
        subtitle: 'Book Cab + Parking',
        assetImage: 'assets/service_airport.webp',
        badgeIcon: Icons.local_parking_rounded,
        onTap: () => context.push(
          '/home/search?title=Airport%20Parking',
          extra: 'Airport Parking',
        ),
      ),
      _FallbackServiceData(
        title: 'Railway Station',
        subtitle: 'Book Cab + Parking',
        assetImage: 'assets/service_railway.webp',
        badgeIcon: Icons.local_parking_rounded,
        onTap: () => context.push(
          '/home/search?title=Railway%20Station',
          extra: 'Railway Station',
        ),
      ),
    ];

    const double spacing = 10.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top 2 cards: Instant Booking & Outstation covering full width
        Row(
          children: [
            for (int i = 0; i < topServices.length; i++) ...[
              if (i > 0) const SizedBox(width: spacing),
              Expanded(
                child: _KrantiServiceCard(
                  title: topServices[i].title,
                  subtitle: topServices[i].subtitle,
                  imageUrl: '',
                  fallbackAsset: topServices[i].assetImage,
                  badgeIcon: topServices[i].badgeIcon,
                  isFeatured: true,
                  onTap: topServices[i].onTap,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: spacing),
        // Bottom 3 cards: Car rental, Airport Parking, Railway Station
        Row(
          children: [
            for (int i = 0; i < bottomServices.length; i++) ...[
              if (i > 0) const SizedBox(width: spacing),
              Expanded(
                child: _KrantiServiceCard(
                  title: bottomServices[i].title,
                  subtitle: bottomServices[i].subtitle,
                  imageUrl: '',
                  fallbackAsset: bottomServices[i].assetImage,
                  badgeIcon: bottomServices[i].badgeIcon,
                  isFeatured: false,
                  onTap: bottomServices[i].onTap,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _KrantiServiceCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String imageUrl;
  final String fallbackAsset;
  final IconData badgeIcon;
  final bool isFeatured;
  final VoidCallback onTap;

  const _KrantiServiceCard({
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.fallbackAsset,
    required this.badgeIcon,
    this.isFeatured = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final double cardHeight = isFeatured ? 122 : 104;
    final double bottomPanelHeight = isFeatured ? 45 : 42;
    final double titleSize = isFeatured ? 12.5 : 10;
    final double subtitleSize = isFeatured ? 9.2 : 7.5;
    final double arrowBtnSize = isFeatured ? 22 : 18;
    final double arrowIconSize = isFeatured ? 15 : 13;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF222222),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2E2E2E), width: 1),
        boxShadow: const [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            splashColor: const Color(0xFFF5B400).withValues(alpha: 0.15),
            child: SizedBox(
              height: cardHeight,
              child: Stack(
                children: [
                  // 1. Top Image / Photo
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    bottom: bottomPanelHeight - 2,
                    child: _buildCardImage(),
                  ),

                  // 3. Bottom Information Panel
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: bottomPanelHeight,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isFeatured ? 8 : 6,
                        vertical: 3,
                      ),
                      decoration: const BoxDecoration(
                        color: Color(0xFF222222),
                        borderRadius: BorderRadius.vertical(
                          bottom: Radius.circular(16),
                        ),
                        border: Border(
                          top: BorderSide(color: Color(0xFF2E2E2E), width: 0.8),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: titleSize,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    letterSpacing: -0.2,
                                    height: 1.1,
                                  ),
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  subtitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: subtitleSize,
                                    fontWeight: FontWeight.w500,
                                    color: const Color(0xFF94A3B8),
                                    height: 1.1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 3),
                          Container(
                            width: arrowBtnSize,
                            height: arrowBtnSize,
                            decoration: const BoxDecoration(
                              color: Color(0xFFF5B400),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Icon(
                                Icons.chevron_right_rounded,
                                color: const Color(0xFF0F172A),
                                size: arrowIconSize,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCardImage() {
    if (imageUrl.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: imageUrl,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        placeholder: (context, url) => Image.asset(
          fallbackAsset,
          fit: BoxFit.cover,
          alignment: Alignment.center,
        ),
        errorWidget: (context, url, error) => Image.asset(
          fallbackAsset,
          fit: BoxFit.cover,
          alignment: Alignment.center,
        ),
      );
    }
    return Image.asset(
      fallbackAsset,
      fit: BoxFit.cover,
      alignment: Alignment.center,
    );
  }
}

class _FallbackServiceData {
  final String title;
  final String subtitle;
  final String assetImage;
  final IconData badgeIcon;
  final VoidCallback onTap;

  const _FallbackServiceData({
    required this.title,
    required this.subtitle,
    required this.assetImage,
    required this.badgeIcon,
    required this.onTap,
  });
}

/// Quick Shortcut Card (Work, Home, Saved 1:1 Matching Reference Design)
class _QuickShortcutCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _QuickShortcutCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: const Color(0xFF222222),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 9),
            decoration: BoxDecoration(
              color: const Color(0xFF222222),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF2E2E2E)),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(icon, size: 21, color: iconColor),
                const SizedBox(width: 7),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The transparent decoration strip pinned to the top of the home screen.
///
/// Image providers are built once per URL and cached, so the widget never
/// re-decodes on a rebuild — that re-decode was what made a base64 image blink.
/// With more than one banner it cross-fades between them slowly; a single
/// banner is shown statically.
class _TopBannerStrip extends StatefulWidget {
  final List<String> images;

  const _TopBannerStrip({required this.images});

  @override
  State<_TopBannerStrip> createState() => _TopBannerStripState();
}

class _TopBannerStripState extends State<_TopBannerStrip> {
  final Map<String, ImageProvider> _providerCache = {};
  Timer? _rotateTimer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _warmProviders();
    _restartRotation();
  }

  @override
  void didUpdateWidget(_TopBannerStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.images != widget.images) {
      _warmProviders();
      if (_index >= widget.images.length) _index = 0;
      _restartRotation();
    }
  }

  /// Builds (and caches) the provider for every URL up front, so switching
  /// between banners never triggers a fresh decode.
  void _warmProviders() {
    for (final url in widget.images) {
      _providerFor(url);
    }
  }

  ImageProvider? _providerFor(String url) {
    return _providerCache.putIfAbsent(
      url,
      () => buildSafeImageProvider(resolveMediaUrl(url)) ?? const AssetImage('assets/bottombanner.webp'),
    );
  }

  void _restartRotation() {
    _rotateTimer?.cancel();
    if (widget.images.length < 2) return;
    _rotateTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      setState(() => _index = (_index + 1) % widget.images.length);
    });
  }

  @override
  void dispose() {
    _rotateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.images.isEmpty) return const SizedBox.shrink();
    final url = widget.images[_index.clamp(0, widget.images.length - 1)];
    final provider = _providerFor(url);
    if (provider == null) return const SizedBox.shrink();

    final image = Image(
      key: ValueKey(url),
      image: provider,
      width: double.infinity,
      height: double.infinity,
      fit: BoxFit.cover,
      alignment: Alignment.center,
      // Keeps the old frame on screen while the next banner decodes, so a
      // switch never flashes blank.
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
    );

    if (widget.images.length < 2) return image;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 600),
      child: image,
    );
  }
}

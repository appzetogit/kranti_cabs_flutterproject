import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/image_utils.dart';
import '../../../core/utils/ist_time.dart';
import '../../../core/utils/snackbar_utils.dart';
import '../../../shared/widgets/ride_offer_permission_banner.dart';
import '../../auth/application/auth_providers.dart';
import '../../earnings/application/earnings_providers.dart';
import '../../ride/application/ride_providers.dart';
import '../../subscription/application/subscription_providers.dart';
import '../../subscription/data/subscription_model.dart';
import '../../../shared/widgets/primary_button.dart';
import '../application/dashboard_providers.dart';
import 'driver_banner_strip.dart';
import '../../destination/presentation/go_home_card.dart';
import '../../scheduled/presentation/scheduled_rides_tile.dart';
import '../../scheduled/application/scheduled_rides_providers.dart';
import '../../heatmap/application/heatmap_controller.dart';
import '../../heatmap/data/opportunity_models.dart';
import '../../heatmap/presentation/surge_pill_icon.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with WidgetsBindingObserver {
  bool _activeRideRouteOpen = false;
  bool _offerRouteOpen = false;
  bool _subscriptionNudgeShown = false;
  bool _nudgeSheetOpen = false;
  bool _bonusPopupChecked = false;
  Timer? _subscriptionCountdownTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Drives the subscription ring card's "Xh Ym left" label — it reads
    // straight off `expiresAt` each tick, nothing is computed and cached.
    _subscriptionCountdownTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    Future.microtask(() {
      // Not awaited, so tracking below resumes without waiting on the network.
      unawaited(_resumeActiveRide());
      // A driver who force-closed the app mid-shift is still online
      // server-side on reopen, but a fresh DashboardNotifier has no location
      // subscription running for them until this resumes it.
      try {
        ref.read(dashboardProvider.notifier).resumeTrackingIfOnline();
      } catch (error, stackTrace) {
        developer.log(
          'Could not resume location tracking',
          name: 'home',
          error: error,
          stackTrace: stackTrace,
        );
      }
      _refreshDriverData();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscriptionCountdownTimer?.cancel();
    super.dispose();
  }

  /// Coming back to the app counts as opening it again: a driver without a
  /// pass is reminded every time, not once per cold start. The status is
  /// re-fetched first so a pass that lapsed (or was just bought) while the
  /// app sat in the background is judged on fresh data.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _subscriptionNudgeShown = false;
    ref.read(subscriptionStatusProvider.notifier).refresh();
    // Opened from a "head out now" reminder: the scheduled ride is the active
    // trip from 30 minutes before pickup, so pick it up if none is on screen.
    if (ref.read(rideProvider).activeRide == null) unawaited(_resumeActiveRide());
    ref.invalidate(scheduledRidesProvider);
  }

  /// Awaited inside its own try: `resumeActiveRide` is async, so the
  /// fire-and-forget call this replaces could never catch its failures.
  Future<void> _resumeActiveRide() async {
    try {
      await ref.read(rideProvider.notifier).resumeActiveRide();
    } catch (error, stackTrace) {
      developer.log(
        'Could not resume the active ride',
        name: 'home',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Re-reads the driver's profile, wallet, and trip-count stats from the
  /// server.
  ///
  /// `authProvider.refresh()` covers `todaySummary` (today's earnings/rides)
  /// and `walletBalance`, but the other home-screen stats live behind their
  /// own `FutureProvider`s and hold their last value until invalidated —
  /// every one of them has to be listed here explicitly or it goes stale
  /// silently after a ride.
  Future<void> _refreshDriverData() async {
    try {
      await ref.read(authProvider.notifier).refresh();
    } catch (error, stackTrace) {
      // The stats below still refresh; only the profile keeps its last value.
      developer.log(
        'Could not refresh the driver profile',
        name: 'home',
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (!mounted) return;
    ref.invalidate(walletSnapshotProvider);
    ref.invalidate(incentiveSnapshotProvider);
    ref.invalidate(lifetimeRideCountProvider);
    ref.invalidate(recentRidesProvider);
  }

  String _validText(String? input, String fallback) {
    if (input == null || input.trim().isEmpty) return fallback;
    return input.trim();
  }

  /// "Live Ride" — a persistent, tappable summary of the driver's active
  /// trip, if any.
  ///
  /// The `ref.listen` block below already auto-pushes `/active-ride` the
  /// moment one starts, but that only fires on the transition into having
  /// one — a driver who backs out of that screen (or reopens the app mid
  /// trip, before the auto-push has a chance to run) would otherwise see
  /// nothing on Home suggesting a trip is still open, unlike the rider app's
  /// own "Ongoing Ride" card. Shrinks to nothing when there is none.
  Widget _buildLiveRideCard(BuildContext context) {
    final ride = ref.watch(rideProvider).activeRide;
    if (ride == null) return const SizedBox.shrink();

    final isParcel = ride.serviceType == 'parcel';
    String statusTitle = 'DRIVER ON THE WAY';
    IconData statusIcon = Icons.directions_car_filled_rounded;
    switch (ride.liveStatus) {
      case 'arrived':
        statusTitle = 'ARRIVED AT PICKUP';
        statusIcon = Icons.where_to_vote_rounded;
        break;
      case 'started':
      case 'ongoing':
        statusTitle = 'TRIP IN PROGRESS';
        statusIcon = Icons.navigation_rounded;
        break;
    }

    final fareText = ride.fare > 0 ? '₹${ride.fare.toStringAsFixed(0)}' : '';
    final riderName = ride.riderName.isNotEmpty ? ride.riderName : 'Rider';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => context.push('/active-ride'),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF222222),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.primary, width: 1.5),
            boxShadow: const [
              BoxShadow(
                color: Colors.black38,
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isParcel ? Icons.inventory_2_rounded : statusIcon,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isParcel ? 'LIVE DELIVERY' : 'LIVE RIDE',
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primary,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      statusTitle,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      fareText.isNotEmpty
                          ? '$riderName • $fareText'
                          : riderName,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF94A3B8),
                        fontWeight: FontWeight.w600,
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
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleOnline(bool goingOnline) async {
    if (!goingOnline) {
      try {
        await ref.read(dashboardProvider.notifier).goOffline();
        if (mounted) SnackbarUtils.info('home.offline_toast'.tr());
      } on ApiException catch (e) {
        SnackbarUtils.error(e.message);
      } catch (_) {
        SnackbarUtils.error('home.toggle_offline_error'.tr());
      }
      return;
    }

    try {
      await ref.read(dashboardProvider.notifier).goOnline();
      if (mounted) SnackbarUtils.success('home.online_toast'.tr());
    } on SelfieRequiredException {
      await _captureSelfieAndGoOnline();
    } on LocationRequiredException catch (e) {
      if (!mounted) return;
      if (e.permanentlyDenied) {
        SnackbarUtils.error('home.loc_blocked'.tr());
      } else if (e.serviceDisabled) {
        SnackbarUtils.error('home.loc_gps_off'.tr());
      } else {
        SnackbarUtils.error('home.loc_required'.tr());
      }
    } on ApiException catch (e) {
      SnackbarUtils.error(e.message);
    } catch (_) {
      SnackbarUtils.error('home.toggle_online_error'.tr());
    }
  }

  Future<void> _captureSelfieAndGoOnline() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      imageQuality: 80,
      maxWidth: 1024,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final dataUrl = 'data:image/jpeg;base64,${base64Encode(bytes)}';
    try {
      await ref
          .read(dashboardProvider.notifier)
          .goOnline(selfieDataUrl: dataUrl);
      if (mounted) SnackbarUtils.success('home.online_toast'.tr());
    } on ApiException catch (e) {
      SnackbarUtils.error(e.message);
    } catch (_) {
      SnackbarUtils.error('home.toggle_online_error'.tr());
    }
  }

  /// Tells a newly-approved driver their first pass was already bought for
  /// them, using the joining bonus that just landed in their wallet — a
  /// plain wallet-history row wouldn't explain why a pass appeared without
  /// them buying one. Persisted (not just a session flag) so re-opening the
  /// app never shows it twice.
  Future<void> _maybeShowBonusPopup(SubscriptionStatus? status) async {
    if (_bonusPopupChecked) return;
    final sub = status?.subscription;
    if (sub == null || sub.paymentMethod != 'bonus') return;

    _bonusPopupChecked = true;
    final prefs = await SharedPreferences.getInstance();
    final seenKey = 'bonus_subscription_seen_${sub.id}';
    if (prefs.getBool(seenKey) == true) return;
    await prefs.setBool(seenKey, true);

    if (!mounted) return;
    final days = (sub.startsAt != null && sub.expiresAt != null)
        ? sub.expiresAt!.difference(sub.startsAt!).inHours ~/ 24
        : null;
    final daysText = days != null && days > 0 ? '$days-day ' : '';

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF222222),
        title: Text('home.sub_activated_title'.tr(), style: const TextStyle(color: Colors.white)),
        content: Text(
          'home.bonus_popup'.tr(namedArgs: {
            'plan': '$daysText${sub.planName.isEmpty ? 'home.daily_subscription'.tr() : sub.planName}',
            'amount': sub.amount.toStringAsFixed(0),
          }),
          style: const TextStyle(color: AppColors.lightTextSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('home.got_it'.tr()),
          ),
        ],
      ),
    );
  }

  /// Nudges a driver with no active pass, once per app session — not a
  /// blocker. Going online still works either way; the server is what
  /// actually withholds ride requests, this just explains why up front.
  void _maybeShowSubscriptionNudge(SubscriptionStatus? status) {
    if (status == null || _subscriptionNudgeShown || _nudgeSheetOpen) return;
    if (!status.enabled || status.isActive) return;

    _subscriptionNudgeShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _nudgeSheetOpen = true;
      showModalBottomSheet(
        context: context,
        backgroundColor: const Color(0xFF222222),
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (sheetContext) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.event_repeat_rounded, color: AppColors.warning),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'home.activate_pass_title'.tr(),
                        style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  status.blocksRidesWhenExpired
                      ? 'home.nudge_blocks'.tr()
                      : 'home.nudge_commission'.tr(),
                  style: const TextStyle(color: AppColors.lightTextSecondary, fontSize: 13.5, height: 1.4),
                ),
                const SizedBox(height: 20),
                PrimaryButton(
                  label: 'home.activate_subscription'.tr(),
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    context.push('/subscription');
                  },
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    child: Text('home.maybe_later'.tr(), style: const TextStyle(color: AppColors.lightTextSecondary)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ).whenComplete(() => _nudgeSheetOpen = false);
    });
  }

  String _distanceText(double? km) {
    if (km == null) return '';
    return km < 1 ? '${(km * 1000).round()} m away' : '${km.toStringAsFixed(1)} km away';
  }

  /// "1.3x fares at Majestic", or null to keep the card's usual title.
  String? _demandCardTitle(Hotspot? hotspot) {
    if (hotspot == null) return null;
    final place = hotspot.title.isNotEmpty ? ' at ${hotspot.title}' : '';
    return hotspot.isSurging
        ? '${SurgePillIcon.labelFor(hotspot.multiplier)} fares$place'
        : 'Riders waiting$place';
  }

  /// "₹45 more per 5 km trip · 2.1 km away", or null for the usual subtitle.
  String? _demandCardSubtitle(Hotspot? hotspot) {
    if (hotspot == null) return null;
    final fare = hotspot.exampleFare;
    final parts = [
      if (fare != null && fare.extra > 0) '₹${fare.extra} more per ${fare.km.toStringAsFixed(0)} km trip',
      _distanceText(hotspot.distanceKm),
      'tap to see the map',
    ].where((part) => part.isNotEmpty).toList();
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final driver = ref.watch(authProvider).driver;
    final dashboard = ref.watch(dashboardProvider);
    final walletAsync = ref.watch(walletSnapshotProvider);
    final subscriptionStatus = ref.watch(subscriptionStatusProvider).valueOrNull;
    // The best surge or busy area nearby, for the demand-map card. Only while
    // on duty: an offline driver is not choosing where to go, and should not
    // be polling for it.
    final Hotspot? nearbyHotspot =
        dashboard.isOnline ? ref.watch(nearbyHotspotProvider).valueOrNull : null;

    ref.listen<AsyncValue<SubscriptionStatus>>(subscriptionStatusProvider, (previous, next) {
      _maybeShowSubscriptionNudge(next.valueOrNull);
      unawaited(_maybeShowBonusPopup(next.valueOrNull));
    });
    // The provider may already hold data by the time this widget first
    // builds (e.g. re-entering Home after navigating away and back) —
    // `ref.listen` alone only fires on the *next* change, so it would miss
    // that. Read the current value directly to cover it too.
    _maybeShowSubscriptionNudge(subscriptionStatus);
    unawaited(_maybeShowBonusPopup(subscriptionStatus));

    final realWalletBalance =
        walletAsync.whenOrNull(data: (snapshot) => snapshot.wallet.balance) ??
        driver?.walletBalance ??
        0.0;

    final isOnline = dashboard.isOnline || (driver?.isOnline ?? false);
    final summary = driver?.todaySummary;

    // Real values only. These used to fall back to one specific person's name,
    // a made-up number plate, a 4.6 rating and 1,250 rupees across 12 trips, so
    // a driver whose profile had not loaded yet saw a stranger's identity and
    // earnings they had not made.
    final driverName = _validText(driver?.name ?? driver?.fullName, '');
    final vehicleNum = _validText(driver?.vehicleNumber, '');
    final vehicleMod = _validText(
      driver?.vehicleModel ?? driver?.vehicleType,
      '',
    );
    final ratingStr = (driver?.rating ?? 0) > 0
        ? driver!.rating.toStringAsFixed(1)
        : 'New';
    final earningsVal = summary?.earnings ?? 0;
    final ridesVal = summary?.rides ?? 0;
    // Labelled "Total Rides" below, so it has to be the lifetime figure, not
    // today's count — same fix already applied to profile_screen.dart's
    // "Total Trips" for the identical bug.
    final totalTripsStr = ref
        .watch(lifetimeRideCountProvider)
        .maybeWhen(data: (count) => '$count', orElse: () => '$ridesVal');

    final vehicleLine = [
      vehicleNum,
      vehicleMod,
    ].where((part) => part.isNotEmpty).join(' • ');

    ref.listen(rideProvider, (previous, next) {
      final prevReq = previous?.incomingRequest;
      final nextReq = next.incomingRequest;

      if (nextReq != null &&
          (prevReq == null ||
              prevReq.rideId != nextReq.rideId ||
              !_offerRouteOpen)) {
        _offerRouteOpen = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.push('/ride-request');
        });
      } else if (nextReq == null) {
        _offerRouteOpen = false;
      }

      final prevActive = previous?.activeRide;
      final nextActive = next.activeRide;

      if (nextActive != null &&
          (prevActive == null ||
              prevActive.id != nextActive.id ||
              !_activeRideRouteOpen)) {
        _activeRideRouteOpen = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.push('/active-ride');
        });
      } else if (nextActive == null) {
        _activeRideRouteOpen = false;
        if (prevActive != null) _refreshDriverData();
      }
    });

    final profileImgProvider = buildSafeImageProvider(
      driver?.profilePictureUrl ?? driver?.profileImage,
    );

    return Scaffold(
      backgroundColor: const Color(0xFF0E1318), // Pure Dark Theme
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E1318),
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu_rounded, color: Colors.white, size: 24),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: Text(
          'nav.home'.tr(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(
                  Icons.notifications_rounded,
                  color: Colors.white,
                  size: 24,
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFF3B30),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
            onPressed: () => context.push('/notifications'),
          ),
          const SizedBox(width: 6),
        ],
      ),
      drawer: Drawer(
        backgroundColor: const Color(0xFF11191D),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            children: [
              UserAccountsDrawerHeader(
                decoration: BoxDecoration(
                  color: const Color(0xFF222222),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF2E2E2E)),
                ),
                accountName: Text(
                  driverName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Colors.white,
                  ),
                ),
                accountEmail: Text(
                  vehicleLine,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 13,
                  ),
                ),
                currentAccountPicture: CircleAvatar(
                  backgroundColor: AppColors.primary,
                  child: Text(
                    driverName.isNotEmpty
                        ? driverName.substring(0, 1).toUpperCase()
                        : 'R',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF11191D),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(
                  Icons.wallet_rounded,
                  color: AppColors.primary,
                ),
                title: Text(
                  'nav.wallet'.tr(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  context.push('/wallet');
                },
              ),
              // Hidden entirely (not just disabled) when the city has the
              // feature switched off — never show a dead button for it.
              if (ref.watch(subscriptionStatusProvider).valueOrNull?.enabled == true)
                ListTile(
                  leading: const Icon(
                    Icons.event_repeat_rounded,
                    color: AppColors.primary,
                  ),
                  title: Text(
                    'home.daily_subscription'.tr(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/subscription');
                  },
                ),
              ListTile(
                leading: const Icon(
                  Icons.history_rounded,
                  color: AppColors.primary,
                ),
                title: Text(
                  'home.ride_history'.tr(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  context.push('/ride-history');
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.notifications_rounded,
                  color: AppColors.primary,
                ),
                title: Text(
                  'home.notifications'.tr(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  context.push('/notifications');
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.settings_rounded,
                  color: AppColors.primary,
                ),
                title: Text(
                  'home.settings'.tr(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  context.push('/settings');
                },
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            // Ambient warm golden glow in top-right background
            Positioned(
              top: -80,
              right: -80,
              child: Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFFFFB800).withValues(alpha: 0.12),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            RefreshIndicator(
              color: const Color(0xFFFFB800),
              backgroundColor: const Color(0xFF1A1F26),
              onRefresh: _refreshDriverData,
              child: ListView(
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                children: [
                  // Ride offer permissions alert banner if required
                  const RideOfferPermissionBanner(),
                  const SizedBox(height: 10),

                  // 1. DRIVER PROFILE HEADER CARD (Dark Theme with Gold Swoosh & Auto)
                  InkWell(
                    onTap: () => context.push('/profile'),
                    borderRadius: BorderRadius.circular(22),
                    child: Container(
                      width: double.infinity,
                      height: 114,
                      decoration: BoxDecoration(
                        color: const Color(0xFF161B22),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: const Color(0xFF242C38), width: 1),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black45,
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: Stack(
                          children: [
                            // Right-side golden swoosh background
                            Positioned(
                              right: 0,
                              top: 0,
                              bottom: 0,
                              width: 170,
                              child: CustomPaint(
                                painter: _GoldenHeaderSwooshPainter(),
                              ),
                            ),
                            // Auto Rickshaw image
                            Positioned(
                              right: -6,
                              top: 6,
                              bottom: 6,
                              width: 130,
                              child: Image.asset(
                                'assets/home_auto.webp',
                                fit: BoxFit.contain,
                                alignment: Alignment.centerRight,
                                errorBuilder: (context, error, stackTrace) => Image.asset(
                                  'assets/home_auto.png',
                                  fit: BoxFit.contain,
                                  alignment: Alignment.centerRight,
                                ),
                              ),
                            ),
                            // Driver info
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              child: Row(
                                children: [
                                  Container(
                                    width: 56,
                                    height: 56,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: const Color(0xFF141922),
                                      border: Border.all(
                                        color: const Color(0xFFFFB800),
                                        width: 2.2,
                                      ),
                                      image: profileImgProvider != null
                                          ? DecorationImage(
                                              image: profileImgProvider,
                                              fit: BoxFit.cover,
                                            )
                                          : null,
                                    ),
                                    child: profileImgProvider == null
                                        ? const Icon(
                                            Icons.person,
                                            size: 32,
                                            color: Colors.white,
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.only(right: 90),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            driverName.isNotEmpty ? driverName : 'Tanu',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w800,
                                              color: Colors.white,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Row(
                                            children: [
                                              const Icon(
                                                Icons.star_rounded,
                                                color: Color(0xFFFFB800),
                                                size: 16,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                ratingStr,
                                                style: const TextStyle(
                                                  fontSize: 13.5,
                                                  fontWeight: FontWeight.w800,
                                                  color: Colors.white,
                                                ),
                                              ),
                                              const SizedBox(width: 20),
                                              const Icon(
                                                Icons.chevron_right_rounded,
                                                color: Color(0xFF94A3B8),
                                                size: 18,
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            vehicleLine.isNotEmpty ? vehicleLine : 'MP09AB1234 • auto',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 11.5,
                                              color: Color(0xFF94A3B8),
                                              fontWeight: FontWeight.w500,
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
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // 1b. LIVE RIDE CARD — shrinks to nothing when there's no
                  // active trip.
                  _buildLiveRideCard(context),

                  // 2. WALLET BALANCE CARD (Ivory/Cream with 4 quick actions)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFFFFFDF8),
                          Color(0xFFFFF8E8),
                          Color(0xFFFFF1D6),
                        ],
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black38,
                          blurRadius: 10,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Top: Wallet Icon + Balance + Add Money Button
                        Row(
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFE8B5),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.account_balance_wallet_rounded,
                                color: Color(0xFF1E293B),
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'home.wallet_balance'.tr(),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF64748B),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    // "-₹120.00" in red when the driver owes
                                    // commission, never "₹-120.00".
                                    '${realWalletBalance < 0 ? '-' : ''}₹${realWalletBalance.abs().toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w900,
                                      color: realWalletBalance < 0 ? const Color(0xFFDC2626) : const Color(0xFF0F172A),
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            InkWell(
                              onTap: () => context.push('/wallet'),
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFB800),
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFFFB800).withValues(alpha: 0.35),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'home.add_money'.tr(),
                                      style: const TextStyle(
                                        color: Color(0xFF111827),
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(
                                      Icons.chevron_right_rounded,
                                      color: Color(0xFF111827),
                                      size: 16,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Bottom: 4 Quick Actions Row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildQuickActionItem(
                              icon: Icons.format_list_bulleted_rounded,
                              label: 'Transaction\nHistory',
                              onTap: () => context.push('/transactions'),
                            ),
                            _buildQuickActionItem(
                              icon: Icons.north_rounded,
                              label: 'Withdraw',
                              onTap: () => context.push('/withdraw'),
                            ),
                            _buildQuickActionItem(
                              icon: Icons.card_giftcard_rounded,
                              label: 'Incentives',
                              onTap: () => context.push('/incentives'),
                            ),
                            _buildQuickActionItem(
                              icon: Icons.settings_rounded,
                              label: 'Payment\nSettings',
                              onTap: () => context.push('/bank-account'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // 2b. DEMAND MAP ENTRY POINT
                  InkWell(
                    onTap: () => context.push('/demand-map'),
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      width: double.infinity,
                      height: 68,
                      decoration: BoxDecoration(
                        color: const Color(0xFF131A24),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFF222B38)),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black38,
                            blurRadius: 8,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Stack(
                          children: [
                            // Map grid & heatmap background
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _DemandMapCardPainter(),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              child: Row(
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE11D48),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(
                                      Icons.location_on_rounded,
                                      color: Colors.white,
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          _demandCardTitle(nearbyHotspot) ?? 'home.demand_map'.tr(),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 14.5,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.white,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _demandCardSubtitle(nearbyHotspot) ?? 'home.demand_map_sub'.tr(),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF94A3B8),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Location down arrow button & chevron
                                  Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: const Color(0xFF1C222C),
                                      border: Border.all(
                                        color: const Color(0xFFFFB800),
                                        width: 1.4,
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                      color: Color(0xFFFFB800),
                                      size: 18,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(
                                    Icons.chevron_right_rounded,
                                    color: Color(0xFF94A3B8),
                                    size: 20,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // 2a. DAILY SUBSCRIPTION CARD — hidden when the city has the
                  // feature switched off.
                  if (subscriptionStatus?.enabled == true) ...[
                    _SubscriptionCard(status: subscriptionStatus!),
                    const SizedBox(height: 10),
                  ],

                  // 2b. GO HOME (destination mode) - hidden when the admin
                  // has it switched off.
                  const GoHomeCard(),

                  // 2b'. SCHEDULED RIDES - own ones and open ones to take.
                  const ScheduledRidesTile(),

                  // 2c. ZONE PROMO BANNERS (hidden when none / dismissed)
                  const DriverBannerStrip(),
                  const SizedBox(height: 6),

                  // 3. TODAY'S SUMMARY SECTION
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'home.today_summary'.tr(),
                        style: const TextStyle(
                          fontSize: 15,
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      InkWell(
                        onTap: () => context.push('/earnings'),
                        borderRadius: BorderRadius.circular(8),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          child: Row(
                            children: [
                              Text(
                                'View Details',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF94A3B8),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(width: 2),
                              Icon(
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
                  const SizedBox(height: 10),

                  // Two Cards: Total Earnings & Total Rides
                  Row(
                    children: [
                      // Total Earnings Card
                      Expanded(
                        child: Container(
                          height: 74,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F2623),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(0xFF134E48).withValues(alpha: 0.6),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Color(0xFF0A3B31),
                                ),
                                child: const Icon(
                                  Icons.savings_rounded,
                                  color: Color(0xFF10B981),
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      '₹${earningsVal.toStringAsFixed(2)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'home.total_earnings'.tr(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF94A3B8),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Total Rides Card
                      Expanded(
                        child: Container(
                          height: 74,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF132235),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(0xFF1E3A5F).withValues(alpha: 0.6),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Color(0xFF163252),
                                ),
                                child: const Icon(
                                  Icons.directions_car_rounded,
                                  color: Color(0xFF38BDF8),
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      totalTripsStr,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'home.total_rides'.tr(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF94A3B8),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // 3 Stats Below Cards (Online Time, Acceptance, Rating)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatItem(
                        icon: Icons.access_time_rounded,
                        iconColor: Colors.white,
                        value: (summary?.activeMinutes ?? 0) > 0
                            ? '${(summary!.activeMinutes ~/ 60)}h ${(summary.activeMinutes % 60)}m'
                            : '0h 30m',
                        label: 'Online Time',
                      ),
                      _buildStatItem(
                        icon: Icons.check_circle_outline_rounded,
                        iconColor: Colors.white,
                        value: '100%',
                        label: 'Acceptance',
                      ),
                      _buildStatItem(
                        icon: Icons.star_rounded,
                        iconColor: const Color(0xFFFFB800),
                        value: ratingStr != 'New' ? ratingStr : '4.0',
                        label: 'Rating',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // 4. TODAY'S PROGRESS CARD
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF141A22),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFF222B38)),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black38,
                          blurRadius: 8,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'home.today_progress'.tr(),
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF94A3B8),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Row(
                              children: [
                                RichText(
                                  text: TextSpan(
                                    children: [
                                      TextSpan(
                                        text: '$ridesVal / 20 ',
                                        style: const TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const TextSpan(
                                        text: 'Rides',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w500,
                                          color: Color(0xFF94A3B8),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                InkWell(
                                  onTap: () => context.push('/incentives'),
                                  borderRadius: BorderRadius.circular(16),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 32,
                                        height: 32,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: const Color(0xFF28200F),
                                          border: Border.all(
                                            color: const Color(0xFFFFB800),
                                            width: 1.2,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.card_giftcard_rounded,
                                          color: Color(0xFFFFB800),
                                          size: 16,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      const Text(
                                        'Target\nReward',
                                        style: TextStyle(
                                          color: Color(0xFFCBD5E1),
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w600,
                                          height: 1.1,
                                        ),
                                      ),
                                      const SizedBox(width: 2),
                                      const Icon(
                                        Icons.chevron_right_rounded,
                                        color: Color(0xFF94A3B8),
                                        size: 14,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: (ridesVal / 20).clamp(0.05, 1.0),
                            minHeight: 6,
                            backgroundColor: const Color(0xFF1E2733),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              Color(0xFFFFB800),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 5. GO OFFLINE / GO ONLINE TOGGLE CARD
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF261E0E),
                          Color(0xFF171A20),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFFF5A623),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFF5A623).withValues(alpha: 0.15),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF281F0E),
                            border: Border.all(
                              color: const Color(0xFFF5A623),
                              width: 1.4,
                            ),
                          ),
                          child: Icon(
                            isOnline ? Icons.wifi_off_rounded : Icons.wifi_rounded,
                            color: const Color(0xFFF5A623),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isOnline ? 'home.go_offline'.tr() : 'home.go_online'.tr(),
                                style: const TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFFF5A623),
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                isOnline
                                    ? "You won't receive new ride requests"
                                    : "Go online to receive new ride requests",
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF94A3B8),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: dashboard.busy ? null : () => _toggleOnline(!isOnline),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            width: 68,
                            height: 36,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              gradient: isOnline
                                  ? const LinearGradient(
                                      colors: [Color(0xFFFFB800), Color(0xFFE5A93C)],
                                    )
                                  : null,
                              color: isOnline ? null : const Color(0xFF334155),
                              boxShadow: isOnline
                                  ? [
                                      BoxShadow(
                                        color: const Color(0xFFFFB800).withValues(alpha: 0.35),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: AnimatedAlign(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeInOut,
                              alignment: isOnline ? Alignment.centerRight : Alignment.centerLeft,
                              child: Container(
                                width: 28,
                                height: 28,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 4,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFFFEEC9),
              ),
              child: Icon(
                icon,
                color: const Color(0xFF1E293B),
                size: 20,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E293B),
                height: 1.15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required Color iconColor,
    required String value,
    required String label,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: iconColor, size: 18),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 10.5,
                color: Color(0xFF94A3B8),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Compact "how much subscription time is left" card for the home screen —
/// a ring rather than a linear bar so it reads at a glance among the other
/// square stat cards here, with the same countdown wording used on the full
/// Daily Subscription screen.
class _SubscriptionCard extends StatelessWidget {
  final SubscriptionStatus status;

  const _SubscriptionCard({required this.status});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push('/subscription'),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF222222),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF2E2E2E)),
          boxShadow: const [
            BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 3)),
          ],
        ),
        child: status.isActive ? _buildActive(context) : _buildInactive(context),
      ),
    );
  }

  Widget _buildActive(BuildContext context) {
    final cycleStart = status.currentCycle?.startsAt;
    final expiresAt = status.expiresAt;
    final now = DateTime.now().toUtc();

    double progress = 0;
    String remainingLabel = '--';
    if (expiresAt != null) {
      final totalWindow = cycleStart != null && expiresAt.isAfter(cycleStart)
          ? expiresAt.difference(cycleStart)
          : const Duration(hours: 24);
      final remaining = expiresAt.isAfter(now) ? expiresAt.difference(now) : Duration.zero;
      progress = totalWindow.inSeconds > 0
          ? (remaining.inSeconds / totalWindow.inSeconds).clamp(0.0, 1.0)
          : 0.0;
      remainingLabel = _formatRemaining(remaining);
    }

    return Row(
      children: [
        SizedBox(
          width: 54,
          height: 54,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 54,
                height: 54,
                child: CircularProgressIndicator(
                  value: progress == 0 ? 1 : progress,
                  strokeWidth: 5,
                  backgroundColor: AppColors.lightBorder,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    progress == 0 ? AppColors.error : AppColors.primary,
                  ),
                ),
              ),
              Text(
                remainingLabel,
                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'home.active'.tr(),
                      style: const TextStyle(color: AppColors.success, fontSize: 10, fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      status.subscription?.planName ?? 'home.daily_pass'.tr(),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              if (expiresAt != null)
                Text(
                  'home.valid_until'.tr(namedArgs: {
                    'time': DateFormat('h:mm a, d MMM').format(toIst(expiresAt)),
                  }),
                  style: const TextStyle(color: AppColors.lightTextSecondary, fontSize: 11.5),
                ),
              const SizedBox(height: 2),
              Text(
                'home.no_commission_today'.tr(),
                style: const TextStyle(color: AppColors.lightTextSecondary, fontSize: 11),
              ),
            ],
          ),
        ),
        const Icon(Icons.chevron_right_rounded, color: AppColors.lightTextSecondary, size: 20),
      ],
    );
  }

  Widget _buildInactive(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.event_repeat_rounded, color: AppColors.warning),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'home.no_active_sub'.tr(),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
              ),
              const SizedBox(height: 2),
              Text(
                status.blocksRidesWhenExpired
                    ? 'home.subscribe_blocked'.tr()
                    : 'home.subscribe_free'.tr(),
                style: const TextStyle(color: AppColors.lightTextSecondary, fontSize: 11.5),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            'home.subscribe'.tr(),
            style: const TextStyle(color: Color(0xFF11191D), fontSize: 11.5, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }

  static String _formatRemaining(Duration d) {
    if (d <= Duration.zero) return '0m';
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    if (hours <= 0) return '${minutes}m';
    return '${hours}h ${minutes}m';
  }
}

class _GoldenHeaderSwooshPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
        colors: [
          Color(0xFF6B4204),
          Color(0xFFB87814),
          Color(0xFFFFB800),
          Color(0xFFFFD566),
        ],
        stops: [0.0, 0.35, 0.72, 1.0],
      ).createShader(rect);

    final path = Path();
    path.moveTo(0, size.height);
    path.quadraticBezierTo(
      size.width * 0.28,
      size.height * 0.38,
      size.width,
      size.height * 0.12,
    );
    path.lineTo(size.width, size.height);
    path.close();

    canvas.drawPath(path, paint);

    // Warm radial glow in top right
    final glowPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.85, -0.3),
        radius: 0.9,
        colors: [
          const Color(0xFFFFB800).withValues(alpha: 0.4),
          Colors.transparent,
        ],
      ).createShader(rect);

    canvas.drawRect(rect, glowPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DemandMapCardPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = const Color(0xFF1E293B).withValues(alpha: 0.6)
      ..strokeWidth = 1.0;

    // A few subtle street grid lines
    canvas.drawLine(Offset(size.width * 0.45, 0), Offset(size.width * 0.8, size.height), linePaint);
    canvas.drawLine(Offset(size.width * 0.65, 0), Offset(size.width * 0.4, size.height), linePaint);
    canvas.drawLine(Offset(size.width * 0.3, size.height * 0.35), Offset(size.width, size.height * 0.25), linePaint);
    canvas.drawLine(Offset(size.width * 0.35, size.height * 0.8), Offset(size.width, size.height * 0.7), linePaint);

    // Heatmap glowing spots on right
    final spotCenter = Offset(size.width - 85, size.height * 0.45);
    final glowPaint3 = Paint()..color = const Color(0xFFFFB800).withValues(alpha: 0.12);
    final glowPaint2 = Paint()..color = const Color(0xFFFFB800).withValues(alpha: 0.24);
    final glowPaint1 = Paint()..color = const Color(0xFFFFB800).withValues(alpha: 0.45);

    canvas.drawCircle(spotCenter, 26, glowPaint3);
    canvas.drawCircle(spotCenter, 16, glowPaint2);
    canvas.drawCircle(spotCenter, 7, glowPaint1);

    // Secondary smaller pulse
    final spot2 = Offset(size.width - 45, size.height * 0.65);
    canvas.drawCircle(spot2, 18, glowPaint3);
    canvas.drawCircle(spot2, 11, glowPaint2);
    canvas.drawCircle(spot2, 5, glowPaint1);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

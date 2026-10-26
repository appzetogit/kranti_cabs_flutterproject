import '../../../core/constants/app_constants.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/image_utils.dart';
import '../../../core/utils/vehicle_marker_icons.dart';

import '../../../shared/widgets/loading_widget.dart';

import '../../home/application/home_providers.dart';
import '../application/ride_tracking_controller.dart';
import '../data/models/ride_model.dart';
import 'widgets/live_tracking_map.dart';
import 'widgets/parcel_proof_strip.dart';
import 'cancel_reason_sheet.dart';
import 'ride_upi_pay_sheet.dart';

class RideTrackingScreen extends ConsumerStatefulWidget {
  final String rideId;
  const RideTrackingScreen({super.key, required this.rideId});

  @override
  ConsumerState<RideTrackingScreen> createState() => _RideTrackingScreenState();
}

class _RideTrackingScreenState extends ConsumerState<RideTrackingScreen>
    with SingleTickerProviderStateMixin {
  bool _navigatedToRating = false;

  /// The pay screen opens by itself once per ride, as the driver nears the
  /// drop - while the rider is still in the car and before the driver ends
  /// the trip. The Pay button on the trip card stays for any other time.
  bool _offeredPayment = false;

  static const double _payPromptDistanceMeters = 500;

  bool _nearDrop(RideModel ride) {
    final driver = ride.lastDriverLocation;
    if (driver == null) return false;
    const earthRadius = 6371000.0;
    double rad(double deg) => deg * math.pi / 180;
    final dLat = rad(ride.drop.lat - driver.lat);
    final dLng = rad(ride.drop.lng - driver.lng);
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(rad(driver.lat)) * math.cos(rad(ride.drop.lat)) * math.pow(math.sin(dLng / 2), 2);
    return earthRadius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a)) <= _payPromptDistanceMeters;
  }

  // --- Collapsible bottom sheet ---------------------------------------------
  // The rider can drag the trip panel down (or tap the chevron) to reveal the
  // map behind it, leaving only a small handle peeking above the bottom bar.
  final GlobalKey _sheetKey = GlobalKey();
  double _sheetOffset = 0; // 0 = fully open; positive = slid down by px
  static const double _sheetPeek = 46; // px of the handle left visible
  late final AnimationController _slideCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );
  Animation<double>? _slideAnim;

  @override
  void dispose() {
    _slideCtrl.dispose();
    super.dispose();
  }

  /// Max distance the sheet can slide down = its height minus the peek handle.
  ///
  /// Read from a height cached after layout: asking the render object directly
  /// throws "Cannot get size during build" when build calls this.
  double _sheetHeight = 0;
  double get _maxSheetOffset {
    final max = _sheetHeight - _sheetPeek;
    return max > 0 ? max : 0;
  }

  void _measureSheet() {
    final h = _sheetKey.currentContext?.size?.height;
    if (h != null && h != _sheetHeight) _sheetHeight = h;
  }

  void _animateSheetTo(double target) {
    _slideAnim = Tween<double>(begin: _sheetOffset, end: target).animate(
      CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOut),
    )..addListener(() => setState(() => _sheetOffset = _slideAnim!.value));
    _slideCtrl
      ..reset()
      ..forward();
  }

  void _toggleSheet() {
    final max = _maxSheetOffset;
    _animateSheetTo(_sheetOffset > max / 2 ? 0 : max);
  }

  void _onSheetDragUpdate(DragUpdateDetails d) {
    if (_slideCtrl.isAnimating) _slideCtrl.stop();
    setState(() {
      _sheetOffset = (_sheetOffset + d.delta.dy).clamp(0.0, _maxSheetOffset);
    });
  }

  void _onSheetDragEnd(DragEndDetails d) {
    final max = _maxSheetOffset;
    final v = d.primaryVelocity ?? 0;
    // Fling decides direction; otherwise snap to the nearer end.
    if (v > 300) {
      _animateSheetTo(max);
    } else if (v < -300) {
      _animateSheetTo(0);
    } else {
      _animateSheetTo(_sheetOffset > max / 2 ? max : 0);
    }
  }

  Future<void> _callDriver(String phone) async {
    if (phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    // Sheet height for next frame's drag/arrow maths (see _maxSheetOffset).
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureSheet());
    final trackingState = ref.watch(
      rideTrackingControllerProvider(widget.rideId),
    );
    final controller = ref.read(
      rideTrackingControllerProvider(widget.rideId).notifier,
    );
    final ride = trackingState.ride;
    final icons = ref.watch(vehicleMarkerIconsProvider).valueOrNull;

    final family = VehicleMarkerIcons.familyFor(
      iconType: ride?.vehicleIconType,
      vehicleType: ride?.vehicleType,
      vehicleMake: ride?.driver?.vehicleMake,
      vehicleModel: ride?.driver?.vehicleModel,
      serviceType: ride?.serviceType,
    );
    // This vehicle's own art first, then the family silhouette - the same order
    // the driver app resolves in, so rider and driver see one marker, not two.
    final driverIcon =
        icons?[ride?.vehicleTypeId ?? ''] ??
        icons?[family] ??
        BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);

    ref.listen(rideTrackingControllerProvider(widget.rideId), (previous, next) {
      final r = next.ride;
      if (AppConstants.onlinePaymentsEnabled &&
          r != null &&
          !_offeredPayment &&
          r.isUnderway &&
          !r.isCompleted &&
          !r.isFarePaid &&
          (r.paymentMethod ?? 'cash').toLowerCase() == 'cash' &&
          r.fare > 0 &&
          _nearDrop(r)) {
        _offeredPayment = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) RideUpiPaySheet.show(context, r);
        });
      }
      if (r != null && r.isCompleted && !_navigatedToRating) {
        _navigatedToRating = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted)
            context.pushReplacement('/ride/${widget.rideId}/rating');
        });
      }
      if (r != null && r.isCancelled) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) context.go('/home');
        });
      }
      // Camera-follow lives inside LiveTrackingMap now, alongside the marker
      // animation it's following.
    });

    if (trackingState.isLoading || ride == null) {
      return const Scaffold(
        backgroundColor: Color(0xFFF8FAFC),
        body: LoadingWidget(message: 'Loading your ride…'),
      );
    }

    final statusLabel = _getStatusLabel(ride.status, ride.liveStatus);
    final etaLabel = _etaLabel(trackingState.etaMinutes, ride);
    final driver = ride.driver;
    final driverName = (driver?.name.isNotEmpty == true)
        ? driver!.name
        : 'Driver';
    final vehicleNo = driver?.vehicleNumber ?? '';
    // Make and model together ("Maruti Suzuki Ertiga") — falls back to the
    // booked vehicle type when the driver's own catalog entry has neither.
    final vehicleModelLine = [
      driver?.vehicleMake ?? '',
      driver?.vehicleModel ?? '',
    ].where((s) => s.isNotEmpty).join(' ');
    final vehicleDetails = vehicleModelLine.isNotEmpty
        ? vehicleModelLine
        : (ride.vehicleType ?? 'Vehicle Details');
    // The model reads a missing rating as 0. Hidden then, rather than
    // showing a made-up score.
    final driverRating = (driver != null && driver.rating > 0) ? driver.rating : null;
    final driverPhone = driver?.phone ?? '';

    // "Captain 769 m away" — only meaningful while the driver is still
    // approaching pickup; a live fix mid-trip is heading to the drop, not
    // the rider, so showing "away" then would be misleading.
    final driverLocation = ride.lastDriverLocation;
    final driverDistanceLabel = (!ride.isUnderway && driverLocation != null)
        ? _distanceAwayLabel(
            Geolocator.distanceBetween(
              driverLocation.lat,
              driverLocation.lng,
              ride.pickup.lat,
              ride.pickup.lng,
            ),
          )
        : null;

    return Scaffold(
      backgroundColor: const Color(0xFF11191D),
      body: Stack(
        children: [
          // Live map: route + pickup/drop/stop pins + the animated driver
          // marker. See LiveTrackingMap's own doc comment for why this is
          // its own widget rather than inline here.
          LiveTrackingMap(ride: ride, driverIcon: driverIcon),

          // Top Header Overlay (Light Theme Back Button, Live Pill Bar, SOS)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      _LightCircleIconButton(
                        icon: Icons.arrow_back,
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(0xFFE2E8F0),
                              width: 1.2,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black12,
                                blurRadius: 10,
                                offset: Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Row(
                                children: [
                                  Icon(
                                    Icons.sensors,
                                    size: 13,
                                    color: Color(0xFF00C853),
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'LIVE TRACKING',
                                    style: TextStyle(
                                      color: Color(0xFF00C853),
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  SizedBox(width: 4),
                                  Icon(
                                    Icons.north_east,
                                    size: 12,
                                    color: Color(0xFF00C853),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                ride.pickupAddress.toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF0F172A),
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _LightCircleIconButton(
                        icon: Icons.sos,
                        color: AppColors.error,
                        onTap: () => context.push(
                          '/support/sos?rideId=${widget.rideId}',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Bottom Sheet Panel (Dark Navy Theme UI with Driver Details, Call & Chat Options)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Transform.translate(
              offset: Offset(0, _sheetOffset),
              child: Container(
              key: _sheetKey,
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
              decoration: const BoxDecoration(
                color: Color(0xFF0A0A0A),
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black38,
                    blurRadius: 20,
                    offset: Offset(0, -4),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Drag handle + chevron: drag down (or tap) to reveal the
                    // map behind; drag up (or tap) to bring the panel back.
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _toggleSheet,
                      onVerticalDragUpdate: _onSheetDragUpdate,
                      onVerticalDragEnd: _onSheetDragEnd,
                      child: SizedBox(
                        width: double.infinity,
                        child: Column(
                          children: [
                            Container(
                              width: 44,
                              height: 5,
                              decoration: BoxDecoration(
                                color: Colors.white24,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            Icon(
                              _sheetOffset > _maxSheetOffset / 2
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                              color: Colors.white70,
                              size: 26,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    // Status Title, ETA & Distance
                    Text(
                      statusLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        letterSpacing: 0.3,
                      ),
                    ),
                    if (etaLabel != null || driverDistanceLabel != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Row(
                          children: [
                            if (etaLabel != null)
                              Text(
                                etaLabel,
                                style: const TextStyle(
                                  color: Color(0xFFF5B400),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            if (etaLabel != null && driverDistanceLabel != null)
                              const Text(
                                '  •  ',
                                style: TextStyle(
                                  color: Color(0xFF475569),
                                  fontSize: 13,
                                ),
                              ),
                            if (driverDistanceLabel != null)
                              Text(
                                'Captain $driverDistanceLabel',
                                style: const TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  letterSpacing: 0.2,
                                ),
                              ),
                          ],
                        ),
                      ),

                    // Start-of-trip PIN, shown one digit per box so it reads
                    // at a glance — the number the rider actually hands the
                    // driver, not a label to parse. Gone once the trip has
                    // started: it has done its job, and leaving it up reads
                    // as if the trip still needs starting.
                    if (ride.otp.isNotEmpty && !ride.isUnderway && !ride.isCompleted) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Text(
                            'START TRIP WITH PIN',
                            style: TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                            ),
                          ),
                          const SizedBox(width: 10),
                          for (final digit in ride.otp.split(''))
                            Container(
                              width: 28,
                              height: 32,
                              margin: const EdgeInsets.only(left: 6),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEE2E2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                digit,
                                style: const TextStyle(
                                  color: Color(0xFF991B1B),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                    // Paying the fare, Rapido-style: during the trip, a cash
                    // ride can be paid online (or to the driver's UPI) from
                    // here, and says so once it has been.
                    if (AppConstants.onlinePaymentsEnabled && ride.isUnderway && !ride.isCompleted && ride.isCashRide) ...[
                      const SizedBox(height: 14),
                      _FarePaymentRow(ride: ride),
                    ],
                    const SizedBox(height: 16),

                    // --- ACCEPTED DRIVER DETAILS CARD WITH CHAT & CALL ---
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF222222),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: const Color(0xFF2E2E2E),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              // Driver Avatar Box
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0A0A0A),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: const Color(0xFF2A2A2A),
                                  ),
                                  image: buildSafeDecorationImage(
                                    resolveMediaUrl(driver?.profileImage),
                                  ),
                                ),
                                child:
                                    buildSafeImageProvider(
                                          resolveMediaUrl(driver?.profileImage),
                                        ) ==
                                        null
                                    ? const Icon(
                                        Icons.person_outline_rounded,
                                        color: Colors.white,
                                        size: 24,
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 12),

                              // Vehicle & Driver Info Text Column — the plate
                              // is what the rider actually matches to the car
                              // pulling up, so it leads; make/model and the
                              // driver's name follow underneath it.
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (vehicleNo.isNotEmpty)
                                      Text(
                                        vehicleNo.toUpperCase(),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 16,
                                          letterSpacing: 1.0,
                                        ),
                                      ),
                                    if (vehicleNo.isNotEmpty)
                                      const SizedBox(height: 3),
                                    Text(
                                      vehicleDetails,
                                      style: TextStyle(
                                        color: vehicleNo.isNotEmpty
                                            ? const Color(0xFF94A3B8)
                                            : Colors.white,
                                        fontSize: vehicleNo.isNotEmpty
                                            ? 11.5
                                            : 16,
                                        fontWeight: vehicleNo.isNotEmpty
                                            ? FontWeight.w600
                                            : FontWeight.w900,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 3),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            driverName,
                                            style: const TextStyle(
                                              color: Color(0xFF94A3B8),
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (driverRating != null) ...[
                                          const Icon(
                                            Icons.star_rounded,
                                            size: 14,
                                            color: Color(0xFFFFB800),
                                          ),
                                          const SizedBox(width: 3),
                                          Text(
                                            driverRating.toStringAsFixed(1),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              _LightIconButton(
                                icon: Icons.call_outlined,
                                onTap: () => _callDriver(driverPhone),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Labeled rather than icon-only, so it reads as an
                          // action the rider can take, not decoration.
                          SizedBox(
                            width: double.infinity,
                            height: 44,
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  context.push('/ride/${widget.rideId}/chat'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFF5B400),
                                side: const BorderSide(
                                  color: Color(0xFFF5B400),
                                  width: 1.2,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              icon: const Icon(
                                Icons.chat_bubble_outline_rounded,
                                size: 18,
                              ),
                              label: Text(
                                'Message $driverName',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13.5,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Pickup, Drop & Stops Address Timeline Card
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF222222),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: const Color(0xFF2E2E2E),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFF5B400),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  ride.pickupAddress,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: SizedBox(
                                height: 12,
                                child: VerticalDivider(
                                  color: Color(0xFF334155),
                                  thickness: 1.5,
                                ),
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              const Icon(
                                Icons.location_on,
                                size: 14,
                                color: Color(0xFFEF4444),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  ride.dropAddress,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          for (int i = 0; i < ride.stops.length; i++) ...[
                            const Padding(
                              padding: EdgeInsets.only(left: 4),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: SizedBox(
                                  height: 12,
                                  child: VerticalDivider(
                                    color: Color(0xFFCBD5E1),
                                    thickness: 1.5,
                                  ),
                                ),
                              ),
                            ),
                            Row(
                              children: [
                                const Icon(
                                  Icons.location_on,
                                  size: 14,
                                  color: Color(0xFF3B82F6),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Stop ${i + 1}: ${ride.stops[i].address}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFF334155),
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    // Proof the captain handled the parcel. Appears the moment
                    // each photo is taken, because the server pushes fresh ride
                    // state on every proof upload rather than only on a status
                    // change.
                    if (ride.isParcel) ...[
                      const SizedBox(height: 14),
                      ParcelProofStrip(
                        pickup: ride.parcel.pickupProof,
                        delivery: ride.parcel.deliveryProof,
                        compact: true,
                      ),
                    ],

                    const SizedBox(height: 16),

                    // Cancel Ride Button (if ride is cancellable)
                    if (_isCancellable(ride.status))
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: OutlinedButton(
                          onPressed: trackingState.isCancelling
                              ? null
                              : () => _confirmCancel(context, controller, hasDriver: ride.driver != null),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(
                              color: Color(0xFFFCA5A5),
                              width: 1.2,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: Text(
                            trackingState.isCancelling
                                ? 'Cancelling…'
                                : 'Cancel ride',
                            style: const TextStyle(
                              color: Color(0xFFEF4444),
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            ),
          ),
        ],
      ),
    );
  }

  /// "4 min away" while the driver is coming, "12 min to destination" once
  /// the rider is in the car.
  ///
  /// Null whenever there is no honest number to give - no route resolved, the
  /// driver already at the kerb, the trip over. The line is then absent
  /// rather than showing a placeholder a rider might plan around.
  String? _etaLabel(double? minutes, RideModel ride) {
    if (minutes == null || minutes <= 0) return null;
    if (ride.isCompleted || ride.isCancelled) return null;

    final combined = '${ride.status} ${ride.liveStatus}'.toLowerCase();
    if (!ride.isUnderway && combined.contains('arrived')) return null;

    // Under a minute is still a minute away to a waiting rider; "0 min" is not
    // something to show them.
    final rounded = minutes < 1 ? 1 : minutes.round();
    return ride.isUnderway
        ? '$rounded min to destination'
        : 'Pickup in $rounded min';
  }

  /// "769 m away" under a kilometre, "1.4 km away" beyond it — matches how
  /// distance reads everywhere else in the app rather than a raw metre count.
  String _distanceAwayLabel(double meters) {
    if (meters < 1000) return '${meters.round()} m away';
    return '${(meters / 1000).toStringAsFixed(1)} km away';
  }

  String _getStatusLabel(String status, [String? liveStatus]) {
    final s = status.toLowerCase();
    final ls = (liveStatus ?? '').toLowerCase();

    if (s == 'requested' || s == 'searching') {
      return 'Finding your driver…';
    }
    if (s == 'arrived' || ls == 'arrived' || s == 'driver_arrived') {
      return 'Driver has arrived at pickup';
    }
    if (s == 'ongoing' ||
        s == 'started' ||
        s == 'in_progress' ||
        ls == 'started') {
      return 'Trip in progress';
    }
    if (s == 'accepted' || s == 'arriving' || ls == 'arriving') {
      return 'Driver is on the way';
    }
    if (s == 'completed') {
      return 'Ride completed';
    }
    if (s == 'cancelled') {
      return 'Ride cancelled';
    }
    return status.isNotEmpty ? status : 'Driver is on the way';
  }

  bool _isCancellable(String status) {
    final s = status.toLowerCase();
    return s == 'requested' || s == 'searching' || s == 'accepted';
  }

  Future<void> _confirmCancel(
    BuildContext context,
    RideTrackingController controller, {
    required bool hasDriver,
  }) async {
    // The reason list is admin-managed, so the sheet replaces the old hardcoded
    // "Changed my mind" that every cancellation used to be recorded as.
    final result = await showCancelReasonSheet(context, hasDriver: hasDriver);

    // Null means the rider backed out of the sheet — not a cancellation.
    if (result == null || !context.mounted) return;

    final success = await controller.cancelRide(
      reasonId: result.reasonId,
      reason: result.title,
      note: result.note,
    );
    if (success && context.mounted) context.go('/home');
  }
}

class _LightCircleIconButton extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final VoidCallback onTap;

  const _LightCircleIconButton({
    required this.icon,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(
        side: BorderSide(color: Color(0xFFE2E8F0), width: 1.2),
      ),
      elevation: 3,
      shadowColor: Colors.black26,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(icon, color: color ?? const Color(0xFF0F172A), size: 20),
        ),
      ),
    );
  }
}

class _LightIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _LightIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF5B400),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14)),
          child: Icon(icon, color: const Color(0xFF0A0A0A), size: 20),
        ),
      ),
    );
  }
}

/// "Fare ₹127 · Pay now" on the trip card, or "Paid online" once it is.
class _FarePaymentRow extends StatelessWidget {
  final RideModel ride;
  const _FarePaymentRow({required this.ride});

  String get _fare {
    final f = ride.fare;
    return '₹${f == f.roundToDouble() ? f.toInt().toString() : f.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final paid = ride.isPaidOnline;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF222222),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: paid ? const Color(0xFF10B981) : const Color(0xFF2E2E2E)),
      ),
      child: Row(
        children: [
          Icon(
            paid ? Icons.verified_rounded : Icons.payments_rounded,
            color: paid ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  paid ? 'Fare $_fare paid online' : 'Fare $_fare',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800),
                ),
                // Airport / station / tax / parking already inside the fare.
                if (ride.locationCharges.isNotEmpty)
                  Text(
                    'Incl. ${ride.locationCharges.map((c) => '${c.label} ₹${c.amount.round()}').join(', ')}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5, fontWeight: FontWeight.w600),
                  ),
              ],
            ),
          ),
          if (!paid)
            ElevatedButton(
              onPressed: () => RideUpiPaySheet.show(context, ride),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                // The app theme makes buttons full-width; in a row that
                // squeezed the fare text into a one-letter column.
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Pay now', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
        ],
      ),
    );
  }
}

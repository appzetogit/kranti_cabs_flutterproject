import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/services/route_polyline_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/image_utils.dart';
import '../../../core/theme/app_map_style.dart';
import '../../../core/utils/polyline_decoder.dart';
import '../../../core/utils/snackbar_utils.dart';
import '../../../core/providers/vehicle_icons_provider.dart';
import '../../../core/utils/vehicle_marker_helper.dart';
import '../../auth/application/auth_providers.dart';
import '../application/ride_providers.dart';
import '../data/ride_model.dart';
import 'parcel_photo_upload_screen.dart';
import 'parcel_widgets.dart';
import 'ride_payment_collect_sheet.dart';
import 'rental_widgets.dart';
import 'toll_widgets.dart';

class ActiveRideScreen extends ConsumerStatefulWidget {
  const ActiveRideScreen({super.key});

  @override
  ConsumerState<ActiveRideScreen> createState() => _ActiveRideScreenState();
}

class _ActiveRideScreenState extends ConsumerState<ActiveRideScreen>
    with SingleTickerProviderStateMixin {
  GoogleMapController? _mapController;
  StreamSubscription<Position>? _positionSub;
  final _otpController = TextEditingController();
  bool _busy = false;

  /// Floor under the 3m-filtered GPS stream above: a driver stopped at a
  /// light or waiting at pickup can go well past 30s without moving 3m, and
  /// without this the rider's live map would sit on an arbitrarily stale fix
  /// with no way to tell "still there, just stopped" from "connection lost".
  /// Only ever fires when the filter genuinely produced nothing for 30s, so
  /// it never changes the update rate while the car is actually moving.
  Timer? _stationaryHeartbeatTimer;
  Position? _lastKnownPosition;
  DateTime? _lastLocationSentAt;
  static const _stationaryHeartbeatInterval = Duration(seconds: 30);

  BitmapDescriptor? _vehicleIcon;

  /// Where the car actually is, per the last GPS fix. What the marker is
  /// drawn at is [_animatedLatLng], which eases toward this.
  LatLng? _driverLatLng;
  double _heading = 0;

  /// The driver's own marker used to be placed straight on the raw fix, so it
  /// teleported a few metres every time the filter released one and spun
  /// whenever two fixes disagreed about the bearing. It is tweened now, the
  /// same way the rider's app has always drawn the car.
  late final AnimationController _markerAnim;
  LatLng? _animatedLatLng;
  double _animatedHeading = 0;
  LatLng? _tweenFrom;
  LatLng? _tweenTo;
  double _headingFrom = 0;
  double _headingTo = 0;

  /// Sized to how long the last fix actually took to arrive, so the car
  /// covers the gap in about the time the next one takes to turn up instead
  /// of arriving early and sitting still.
  static const _minTweenDuration = Duration(milliseconds: 500);
  static const _maxTweenDuration = Duration(milliseconds: 3000);
  DateTime? _lastFixAt;

  /// Each marker and camera update crosses the platform channel. Sixty a
  /// second is what makes the map stutter; twenty-five is smooth and cheap.
  static const _mapPushInterval = Duration(milliseconds: 40);
  DateTime? _lastMapPushAt;

  /// The server accepts thirty ride-location messages per ten seconds and
  /// silently drops the rest. A 3m filter at city speed goes past that, so
  /// fixes were being thrown away and the rider saw irregular gaps - which
  /// their app then read as the car speeding up and slowing down.
  static const _minSendInterval = Duration(milliseconds: 400);

  /// Past this, a fix is a guess. Only applied once there is an earlier fix
  /// worth keeping instead.
  static const _unusableAccuracyMeters = 50.0;

  /// Road-following route for the current leg, and the leg it was fetched for.
  List<LatLng> _roadRoute = const [];
  String? _roadRouteKey;
  bool _finishing = false;

  // Waiting Clock Timer
  Timer? _waitingTimer;
  int _waitingSeconds = 0;

  /// True while a parcel handover photo is being uploaded. Separate from
  /// [_busy] so the trip buttons stay legible about *what* is happening.
  bool _uploadingProof = false;

  /// Each fires once per leg, not once per rebuild — without these a stray
  /// rebuild while already heading to pickup (or drop) would relaunch Maps
  /// on top of whatever screen the driver switched to.
  bool _autoNavigatedToPickup = false;
  bool _autoNavigatedToDrop = false;

  @override
  void initState() {
    super.initState();
    _markerAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..addListener(_onMarkerTick);
    _loadVehicleIcon();
    _initDriverLocation();
  }

  /// Eases the marker between the last two fixes. Runs at frame rate; what
  /// reaches the map is gated to [_mapPushInterval], with the final frame
  /// always landing so the car finishes exactly on the fix.
  void _onMarkerTick() {
    final from = _tweenFrom;
    final to = _tweenTo;
    if (from == null || to == null) return;

    final t = _markerAnim.value;
    final position = LatLng(
      from.latitude + ((to.latitude - from.latitude) * t),
      from.longitude + ((to.longitude - from.longitude) * t),
    );

    final now = DateTime.now();
    final last = _lastMapPushAt;
    if (t < 1.0 && last != null && now.difference(last) < _mapPushInterval) {
      return;
    }
    _lastMapPushAt = now;

    if (!mounted) return;
    setState(() {
      _animatedLatLng = position;
      _animatedHeading = _lerpBearing(_headingFrom, _headingTo, t);
    });
  }

  /// Turns the short way round: a plain lerp from 350 to 10 degrees sweeps
  /// backwards through the whole circle, which reads as the car spinning on
  /// the spot at every junction.
  static double _lerpBearing(double from, double to, double t) {
    var delta = (to - from) % 360;
    if (delta > 180) delta -= 360;
    if (delta < -180) delta += 360;
    final result = (from + (delta * t)) % 360;
    return result < 0 ? result + 360 : result;
  }

  /// Starts a new tween toward [next], from wherever the marker visually is
  /// rather than from the previous *fix* - a fix that arrives mid-tween would
  /// otherwise make the car jump forward to catch up before easing on.
  void _animateMarkerTo(LatLng next, double heading) {
    final now = DateTime.now();
    final previousFixAt = _lastFixAt;
    _lastFixAt = now;

    if (previousFixAt != null) {
      final elapsed = now.difference(previousFixAt);
      _markerAnim.duration = elapsed < _minTweenDuration
          ? _minTweenDuration
          : (elapsed > _maxTweenDuration ? _maxTweenDuration : elapsed);
    }

    final start = _animatedLatLng;
    if (start == null) {
      // First fix: nothing to ease from, so place it.
      setState(() {
        _animatedLatLng = next;
        _animatedHeading = heading;
      });
      _tweenFrom = next;
      _tweenTo = next;
      _headingFrom = heading;
      _headingTo = heading;
      return;
    }

    _tweenFrom = start;
    _tweenTo = next;
    _headingFrom = _animatedHeading;
    _headingTo = heading;
    _markerAnim
      ..stop()
      ..reset()
      ..forward();
  }

  void _startWaitingTimer() {
    if (_waitingTimer != null) return;
    _waitingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() => _waitingSeconds++);
      }
    });
  }

  void _stopWaitingTimer() {
    _waitingTimer?.cancel();
    _waitingTimer = null;
  }

  Future<void> _loadVehicleIcon() async {
    final driver = ref.read(authProvider).driver;
    final ride = ref.read(rideProvider).activeRide;
    final icon = await resolveVehicleMarker(
      ref,
      vehicleTypeId: driver?.vehicleTypeId,
      vehicleType: driver?.vehicleType,
      serviceType: ride?.serviceType,
    );
    if (mounted) setState(() => _vehicleIcon = icon);
  }

  Future<void> _initDriverLocation() async {
    final locationService = ref.read(locationServiceProvider);
    try {
      final initialPos = await locationService.getCurrentPosition();
      if (mounted) {
        final target = LatLng(initialPos.latitude, initialPos.longitude);
        setState(() {
          _driverLatLng = target;
          // Seeded together, so the marker has something to be drawn at
          // before the first streamed fix arrives.
          _animatedLatLng = target;
        });
        _mapController?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: target, zoom: 17.5),
          ),
        );
      }
    } catch (error, stackTrace) {
      // Not fatal: the stream below places the car as soon as its first fix
      // lands. Logged so a phone that never gets a fix is visible.
      developer.log(
        'No initial position for the active ride',
        name: 'ride',
        error: error,
        stackTrace: stackTrace,
      );
    }

    // Kept alive in the background: navigation opens Google Maps, and the
    // rider has to keep seeing the car move while it is open.
    // Eight metres, not three. Three produced roughly four fixes a second at
    // city speed, past the thirty-per-ten-seconds the server accepts, so the
    // surplus was dropped on arrival and the rider got ragged spacing. Eight
    // sits inside the limit at every speed a taxi travels, and the tween on
    // both sides fills the gap.
    _positionSub = locationService
        .watchPosition(distanceFilterMeters: 8, keepAliveInBackground: true)
        .listen((position) {
          if (!mounted) return;

          final next = LatLng(position.latitude, position.longitude);
          final previous = _driverLatLng;

          // A fix this vague says more about the sky than the road. Kept only
          // when there is nothing better to show at all.
          final accuracy = position.accuracy;
          if (previous != null && accuracy > _unusableAccuracyMeters) return;

          double heading = _heading;
          if (previous != null) {
            final moved = locationService.distanceMeters(
              previous.latitude,
              previous.longitude,
              next.latitude,
              next.longitude,
            );
            // Below a couple of metres the bearing between two fixes is noise,
            // not a turn, so the last real heading is kept.
            if (moved > 2) {
              heading = locationService.bearingBetween(
                previous.latitude,
                previous.longitude,
                next.latitude,
                next.longitude,
              );
            }
          } else if (position.heading >= 0) {
            // No previous fix to take a bearing from, so the device's own is
            // the only thing available.
            heading = position.heading;
          }

          _heading = heading;
          _driverLatLng = next;
          _animateMarkerTo(next, heading);

          // Second guard under the distance filter: a burst of fixes (leaving
          // a tunnel, regaining lock) must not spend the server's budget.
          final sentAt = _lastLocationSentAt;
          final nowSend = DateTime.now();
          if (sentAt != null && nowSend.difference(sentAt) < _minSendInterval) {
            _lastKnownPosition = position;
            return;
          }

          ref
              .read(rideProvider.notifier)
              .sendLocation(
                position.latitude,
                position.longitude,
                heading: heading,
                speed: position.speed,
                accuracy: position.accuracy,
                timestamp: position.timestamp,
              );
          _lastKnownPosition = position;
          _lastLocationSentAt = nowSend;
        });

    _stationaryHeartbeatTimer?.cancel();
    _stationaryHeartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      final position = _lastKnownPosition;
      final lastSentAt = _lastLocationSentAt;
      if (position == null || lastSentAt == null || !mounted) return;
      if (DateTime.now().difference(lastSentAt) < _stationaryHeartbeatInterval)
        return;

      ref
          .read(rideProvider.notifier)
          .sendLocation(
            position.latitude,
            position.longitude,
            heading: position.heading,
            speed: position.speed,
            accuracy: position.accuracy,
            // Deliberately not position.timestamp: this is a keepalive resend
            // of an old fix, not a new one, so it should be timestamped (and
            // therefore ordered) as "now" rather than claim the age of the
            // fix it's repeating.
          );
      _lastLocationSentAt = DateTime.now();
    });
  }

  void _recenterOnDriver() {
    final pos = _driverLatLng;
    if (pos != null) {
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: pos, zoom: 17.5, bearing: _heading),
        ),
      );
    }
  }

  @override
  void dispose() {
    _stopWaitingTimer();
    _positionSub?.cancel();
    _stationaryHeartbeatTimer?.cancel();
    _markerAnim.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _openExternalNavigation(double lat, double lng) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// Launches turn-by-turn navigation already running, not a directions
  /// preview the driver still has to tap Start on. `google.navigation:` is
  /// the Android intent Google Maps treats as "begin driving now"; the plain
  /// maps URL ([_openExternalNavigation]) is the fallback for a device
  /// without the Maps app (or iOS, which does not recognise that scheme).
  Future<void> _startNavigationTo(double lat, double lng) async {
    final navigationUri = Uri.parse('google.navigation:q=$lat,$lng&mode=d');
    if (await canLaunchUrl(navigationUri)) {
      await launchUrl(navigationUri, mode: LaunchMode.externalApplication);
      return;
    }
    await _openExternalNavigation(lat, lng);
  }

  /// Covers the moment this screen is first shown for an already-accepted
  /// ride — a fresh accept from the in-app flow, the native offer card, or a
  /// cold start that adopted a ride already in progress. Checked from
  /// [build] itself (guarded by [_autoNavigatedToPickup], so it only ever
  /// acts once) rather than a one-shot `initState` callback, because the ride
  /// can still be null on the very first frame and arrive a moment later.
  void _autoNavigateToPickupIfNeeded(RideModel ride, bool headingToPickup) {
    if (_autoNavigatedToPickup || !headingToPickup) return;
    final lat = ride.pickupLat;
    final lng = ride.pickupLng;
    if (lat == null || lng == null) return;
    _autoNavigatedToPickup = true;
    unawaited(_startNavigationTo(lat, lng));
  }

  Future<void> _callRider(String phone) async {
    if (phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  /// Photographs the parcel and records it against the ride.
  ///
  /// `stage` is 'pickup' or 'delivery'. The trip cannot move past the matching
  /// point until this has succeeded — the server enforces it too, but a driver
  /// standing at a doorstep deserves to be told before they press the button
  /// rather than after.
  /// Opens the dedicated full-screen Parcel Photo Upload page.
  Future<bool> _captureParcelProof(RideModel ride, String stage) async {
    final result = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0xF00D1B2A),
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (ctx, anim1, anim2) {
        return ParcelPhotoUploadScreen(ride: ride, stage: stage);
      },
      transitionBuilder: (ctx, anim1, anim2, child) {
        return FadeTransition(opacity: anim1, child: child);
      },
    );
    return result == true;
  }

  Future<void> _markArrivedAtPickup(RideModel ride) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      ref.read(rideProvider.notifier).updateStatus('arriving');
      SnackbarUtils.success('Marked arrived at pickup location');
      if (ride.isParcel && !ride.parcel.pickupProof.exists) {
        Future.microtask(() => _captureParcelProof(ride, 'pickup'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyOtpAndStart(RideModel ride) async {
    if (_busy) return;

    if (ride.isParcel && !ride.parcel.pickupProof.exists) {
      final success = await _captureParcelProof(ride, 'pickup');
      if (!success && !ride.parcel.pickupProof.exists) return;
    }

    final otp = _otpController.text.trim();
    if (otp.length != 4) {
      SnackbarUtils.error('Please enter a 4-digit PIN');
      return;
    }
    setState(() => _busy = true);
    try {
      ref.read(rideProvider.notifier).updateStatus('started', otp: otp);
      _otpController.clear();
      if (mounted) SnackbarUtils.success('Trip started');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _markArrivedAtDrop() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      ref.read(rideProvider.notifier).updateStatus('arrived');
      if (mounted) SnackbarUtils.success('Arrived at dropoff location');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _completeTrip(RideModel ride) async {
    if (_busy || _finishing) return;

    if (ride.isParcel && !ride.parcel.deliveryProof.exists) {
      final success = await _captureParcelProof(ride, 'delivery');
      if (!success && !ride.parcel.deliveryProof.exists) return;
    }

    // Collect the fare before closing the trip: show the driver's QR to the
    // rider and record whether it was taken as cash or via UPI. Dismissing the
    // sheet (null) cancels completion so no ride is closed without collection.
    if (!mounted) return;
    final collectedVia = await RidePaymentCollectSheet.show(context, ref, ride);
    if (collectedVia == null) return;

    setState(() {
      _busy = true;
      _finishing = true;
    });

    try {
      ref.read(rideProvider.notifier).updateStatus('completed', collectedVia: collectedVia);
      if (mounted) {
        context.pushReplacement('/trip-complete', extra: ride);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _finishing = false;
        });
        SnackbarUtils.error('Could not complete trip');
      }
    }
  }

  Future<void> _triggerSos(RideModel ride) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text(
          'Trigger Emergency SOS?',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.w800,
          ),
        ),
        content: const Text(
          'This will send an emergency alert with your live location to safety officers.',
          style: TextStyle(color: Color(0xFF64748B)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.sos,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('SEND SOS ALERT'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    try {
      await ref
          .read(apiClientProvider)
          .post(ApiConstants.sos, data: {'rideId': ride.id});
      if (mounted) SnackbarUtils.success('SOS alert sent');
    } catch (_) {
      if (mounted)
        SnackbarUtils.error(
          'Could not send SOS alert. Try calling emergency services directly.',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ride = ref.watch(rideProvider).activeRide;

    if (ride == null) {
      return const Scaffold(
        backgroundColor: Color(0xFFF8FAFC),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF00C853)),
        ),
      );
    }

    if (ride.liveStatus == 'arriving') {
      _startWaitingTimer();
    } else {
      _stopWaitingTimer();
    }

    final headingToPickup =
        ride.liveStatus == 'accepted' || ride.liveStatus == 'arriving';
    _autoNavigateToPickupIfNeeded(ride, headingToPickup);
    final destLat = headingToPickup ? ride.pickupLat : ride.dropLat;
    final destLng = headingToPickup ? ride.pickupLng : ride.dropLng;
    final currentAddress = headingToPickup
        ? ride.pickupAddress
        : ride.dropAddress;

    // Calculate distance & ETA dynamically
    double distanceMeters = 0;
    if (_driverLatLng != null && destLat != null && destLng != null) {
      distanceMeters = Geolocator.distanceBetween(
        _driverLatLng!.latitude,
        _driverLatLng!.longitude,
        destLat,
        destLng,
      );
    }
    final etaMins = (distanceMeters / 500).clamp(1, 60).toInt();

    ref.listen(rideProvider, (previous, next) {
      final nextRide = next.activeRide;
      if (nextRide == null &&
          previous?.activeRide != null &&
          mounted &&
          !_finishing) {
        final reason = next.acceptError;
        if (reason != null && reason.isNotEmpty) SnackbarUtils.info(reason);
        ref.read(rideProvider.notifier).clearAcceptError();
        context.go('/home');
        return;
      }

      if (nextRide == null) return;
      final wasHeadingToPickup =
          previous?.activeRide?.liveStatus == 'accepted' ||
          previous?.activeRide?.liveStatus == 'arriving';
      final isHeadingToPickup =
          nextRide.liveStatus == 'accepted' ||
          nextRide.liveStatus == 'arriving';
      if (wasHeadingToPickup == isHeadingToPickup) return;
      final lat = isHeadingToPickup ? nextRide.pickupLat : nextRide.dropLat;
      final lng = isHeadingToPickup ? nextRide.pickupLng : nextRide.dropLng;
      if (lat != null && lng != null) {
        _mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(LatLng(lat, lng), 16),
        );
      }

      // The pickup leg just ended — the only way there, given `updateStatus`
      // never changes this locally, is the server confirming the OTP and
      // moving the ride to `started`. Re-launch navigation for the drop leg
      // the same way accepting did for the pickup leg.
      if (wasHeadingToPickup &&
          !isHeadingToPickup &&
          !_autoNavigatedToDrop &&
          lat != null &&
          lng != null) {
        _autoNavigatedToDrop = true;
        unawaited(_startNavigationTo(lat, lng));
      }
    });

    final isArrivingOtpState = ride.liveStatus == 'arriving';
    final markerPosition = _animatedLatLng ?? _driverLatLng;
    final routeLine = _routePolylineFor(
      _getRoutePoints(ride, _driverLatLng, destLat, destLng),
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Stack(
        children: [
          // Google Map Background (Dark Theme)
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target:
                  _driverLatLng ??
                  LatLng(destLat ?? 20.5937, destLng ?? 78.9629),
              zoom: 17.5,
            ),
            style: AppMapStyle.light,
            // Resolved once, not twice: this used to be called for the
            // emptiness check and again for the points, decoding the whole
            // stored polyline both times, on every rebuild.
            polylines: {if (routeLine != null) routeLine},
            onMapCreated: (controller) => _mapController = controller,
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            markers: {
              if (markerPosition != null)
                VehicleMarkerHelper.buildVehicleMarker(
                  position: markerPosition,
                  heading: _animatedHeading,
                  customIcon: _vehicleIcon,
                ),
              if (ride.pickupLat != null)
                Marker(
                  markerId: const MarkerId('pickup'),
                  position: LatLng(ride.pickupLat!, ride.pickupLng!),
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueGreen,
                  ),
                  infoWindow: InfoWindow(
                    title: 'Pickup',
                    snippet: ride.pickupAddress,
                  ),
                ),
              if (ride.dropLat != null)
                Marker(
                  markerId: const MarkerId('drop'),
                  position: LatLng(ride.dropLat!, ride.dropLng!),
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueRed,
                  ),
                  infoWindow: InfoWindow(
                    title: 'Drop',
                    snippet: ride.dropAddress,
                  ),
                ),
              for (int i = 0; i < ride.stops.length; i++)
                Marker(
                  markerId: MarkerId('stop_$i'),
                  position: LatLng(ride.stops[i].lat, ride.stops[i].lng),
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueAzure,
                  ),
                  infoWindow: InfoWindow(
                    title: 'Stop ${i + 1}',
                    snippet: ride.stops[i].address,
                  ),
                ),
            },
          ),

          // Top Header Overlay (Dark Theme Back Button, Address Capsule, 3 Metrics Chips)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Top Pill Bar (Back button + Location Header Capsule)
                  Row(
                    children: [
                      _DarkCircleIconButton(
                        icon: Icons.arrow_back,
                        onTap: () => context.pop(),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF222222),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(0xFF2E2E2E),
                              width: 1.2,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black38,
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
                                    color: AppColors.primary,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'DRIVER LIVE',
                                    style: TextStyle(
                                      color: AppColors.primary,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  SizedBox(width: 4),
                                  Icon(
                                    Icons.north_east,
                                    size: 12,
                                    color: AppColors.primary,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                currentAddress.toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // 3 Metric Chips Row (TRIP STAGE, ETA, ROUTE)
                  Row(
                    children: [
                      Expanded(
                        child: _MetricChip(
                          label: 'TRIP STAGE',
                          value: _getStageText(ride.liveStatus),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _MetricChip(
                          label: 'ETA',
                          value: '$etaMins mins',
                          icon: Icons.access_time_rounded,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _MetricChip(
                          label: 'ROUTE',
                          value: headingToPickup ? 'Pickup First' : 'Dropoff',
                          icon: Icons.location_on_outlined,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Floating Map Control Buttons
          Positioned(
            right: 16,
            top: 155,
            child: Column(
              children: [
                _DarkCircleIconButton(
                  icon: Icons.my_location_rounded,
                  onTap: _recenterOnDriver,
                ),
                if (destLat != null && destLng != null) ...[
                  const SizedBox(height: 10),
                  _DarkCircleIconButton(
                    icon: Icons.directions_outlined,
                    color: AppColors.primary,
                    onTap: () => _openExternalNavigation(destLat, destLng),
                  ),
                ],
                const SizedBox(height: 10),
                _DarkCircleIconButton(
                  icon: Icons.sos,
                  color: AppColors.sos,
                  onTap: () => _triggerSos(ride),
                ),
              ],
            ),
          ),

          // Draggable Bottom Sheet Panel (Dark Professional Layout / Light OTP Layout)
          DraggableScrollableSheet(
            key: ValueKey('active_ride_sheet_$isArrivingOtpState'),
            initialChildSize: isArrivingOtpState ? 0.70 : 0.42,
            minChildSize: isArrivingOtpState ? 0.45 : 0.22,
            maxChildSize: isArrivingOtpState ? 0.90 : 0.88,
            snap: true,
            snapSizes: isArrivingOtpState
                ? const [0.45, 0.70, 0.90]
                : const [0.22, 0.42, 0.88],
            builder: (context, scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: isArrivingOtpState
                      ? Colors.white
                      : const Color(0xFF11191D),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(32),
                  ),
                  border: Border(
                    top: BorderSide(
                      color: isArrivingOtpState
                          ? Colors.white
                          : const Color(0xFF2E2E2E),
                      width: 1.5,
                    ),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black54,
                      blurRadius: 20,
                      offset: Offset(0, -4),
                    ),
                  ],
                ),
                child: isArrivingOtpState
                    ? SingleChildScrollView(
                        controller: scrollController,
                        child: _SecurityPinSheet(
                          ride: ride,
                          busy: _busy,
                          waitingSeconds: _waitingSeconds,
                          otpController: _otpController,
                          onSubmitPin: () => _verifyOtpAndStart(ride),
                          onGoBack: () => ref
                              .read(rideProvider.notifier)
                              .updateStatus('accepted'),
                          onSupport: () => context.push('/support'),
                        ),
                      )
                    : SingleChildScrollView(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
                        child: SafeArea(
                          top: false,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Drag Handle Pill Bar
                              Center(
                                child: Container(
                                  width: 40,
                                  height: 4.5,
                                  margin: const EdgeInsets.only(bottom: 16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF475569),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),

                              // Rider Header Card
                              Row(
                                children: [
                                  Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF222222),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: const Color(0xFF2E2E2E),
                                      ),
                                      image: buildSafeDecorationImage(
                                        resolveMediaUrl(ride.riderProfileImage),
                                      ),
                                    ),
                                    child: buildSafeImageProvider(
                                              resolveMediaUrl(ride.riderProfileImage),
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
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          ride.riderName.toUpperCase(),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 17,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.star_rounded,
                                              size: 15,
                                              color: Color(0xFFFFC107),
                                            ),
                                            const SizedBox(width: 3),
                                            Text(
                                              '4.8 • ${_formatDistance(distanceMeters)} AWAY',
                                              style: const TextStyle(
                                                color: Color(0xFF94A3B8),
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  _DarkIconButton(
                                    icon: Icons.chat_bubble_outline_rounded,
                                    onTap: () => context.push('/ride-chat'),
                                  ),
                                  const SizedBox(width: 8),
                                  _DarkIconButton(
                                    icon: Icons.call_outlined,
                                    onTap: () => _callRider(ride.riderPhone),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),

                              // Arrival Radius Container
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF222222),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: const Color(0xFF2E2E2E),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'ARRIVAL RADIUS',
                                            style: TextStyle(
                                              color: Color(0xFF94A3B8),
                                              fontSize: 10,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 0.8,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            '${_formatDistance(distanceMeters)} away from ${headingToPickup ? 'pickup' : 'drop'}',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary.withValues(
                                          alpha: 0.15,
                                        ),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: AppColors.primary,
                                          width: 1.2,
                                        ),
                                      ),
                                      child: const Text(
                                        'UNLOCKED',
                                        style: TextStyle(
                                          color: AppColors.primary,
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 0.8,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),

                              // Pickup & Drop Summary Card
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF222222),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: const Color(0xFF2E2E2E),
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
                                            color: AppColors.primary,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            ride.pickupAddress,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.primary.withValues(
                                              alpha: 0.15,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: const Text(
                                            'PICKUP',
                                            style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.w900,
                                              color: AppColors.primary,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const Padding(
                                      padding: EdgeInsets.only(
                                        left: 4,
                                        top: 3,
                                        bottom: 3,
                                      ),
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: SizedBox(
                                          height: 10,
                                          child: VerticalDivider(
                                            color: Color(0xFF334155),
                                            thickness: 1.5,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        Container(
                                          width: 10,
                                          height: 10,
                                          decoration: const BoxDecoration(
                                            color: Color(0xFFFF4D6D),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            ride.rental != null
                                                ? 'Hourly rental · ${ride.rental!.packageName}'
                                                : ride.dropAddress,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(
                                              0xFFFF4D6D,
                                            ).withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: Text(
                                            ride.rental != null ? 'RENTAL' : 'DROP',
                                            style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.w900,
                                              color: Color(0xFFFF4D6D),
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                              if (ride.rental != null) ...[
                                const SizedBox(height: 12),
                                RentalUsageCard(
                                  rental: ride.rental!,
                                  startedAt: ride.startedAt,
                                ),
                              ],

                              // Outstation tolls: the driver pays these at
                              // the plaza and keeps them in full.
                              if (ride.tollCharges.hasTolls) ...[
                                const SizedBox(height: 12),
                                TollChargesNote(
                                  tolls: ride.tollCharges,
                                  dark: true,
                                ),
                              ],

                              // Parcel Details (If parcel ride - photo upload step removed!)
                              if (ride.isParcel) ...[
                                const SizedBox(height: 12),
                                ParcelDetailsCard(
                                  parcel: ride.parcel,
                                  dark: true,
                                  compact: true,
                                ),
                              ],

                              const SizedBox(height: 16),

                              // Main Action Button
                              _ActionButton(
                                ride: ride,
                                busy: _busy,
                                onArrivedPickup: () =>
                                    _markArrivedAtPickup(ride),
                                onStartTrip: () => _verifyOtpAndStart(ride),
                                onArrivedDrop: _markArrivedAtDrop,
                                onCompleteTrip: () => _completeTrip(ride),
                              ),
                            ],
                          ),
                        ),
                      ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// The drawn route.
  ///
  /// Prefers a server-supplied polyline, then a real road route fetched from
  /// [RoutePolylineService]. The two-point line is a last resort only — it used
  /// to be the *only* path here, which is why the map drew a straight line
  /// through buildings instead of following roads.
  Polyline? _routePolyline;

  /// Keeps one Polyline for as long as its points are the same list. A fresh
  /// object carrying the same few hundred points on every rebuild is the whole
  /// route being re-uploaded to the native map each time.
  Polyline? _routePolylineFor(List<LatLng> route) {
    if (route.isEmpty) {
      _routePolyline = null;
      return null;
    }

    final existing = _routePolyline;
    if (existing != null && identical(existing.points, route)) {
      return existing;
    }

    _routePolyline = Polyline(
      polylineId: const PolylineId('route'),
      points: route,
      color: const Color(0xFF38BDF8),
      width: 5,
      jointType: JointType.round,
      startCap: Cap.roundCap,
      endCap: Cap.roundCap,
    );
    return _routePolyline;
  }

  List<LatLng> _getRoutePoints(
    RideModel ride,
    LatLng? driverLoc,
    double? destLat,
    double? destLng,
  ) {
    // The stored route runs pickup -> drop, so it only describes the leg the
    // driver is on once the trip has started. Using it earlier would draw the
    // trip itself while the driver is still trying to reach the rider.
    final isUnderway =
        ride.liveStatus == 'started' || ride.liveStatus == 'arrived';
    if (isUnderway) {
      final decoded = PolylineDecoder.decode(ride.routePolyline);
      if (decoded.isNotEmpty) return decoded;
    }

    final start =
        driverLoc ??
        (ride.pickupLat != null && ride.pickupLng != null
            ? LatLng(ride.pickupLat!, ride.pickupLng!)
            : null);
    final end = (destLat != null && destLng != null)
        ? LatLng(destLat, destLng)
        : null;
    if (start == null || end == null) return const [];

    _ensureRoadRoute(start, end);
    if (_roadRoute.isNotEmpty) return _roadRoute;

    // Held rather than rebuilt: a new list each call means a new Polyline each
    // rebuild, which is exactly what the caching above is for.
    final fallback = _straightFallback;
    if (fallback != null &&
        fallback.length == 2 &&
        fallback.first == start &&
        fallback.last == end) {
      return fallback;
    }
    return _straightFallback = [start, end];
  }

  List<LatLng>? _straightFallback;

  /// Fetches the road route for the current leg.
  ///
  /// Called from build, so it has to be guarded. The key is rounded to ~100 m
  /// on the origin: keying on the raw GPS fix re-requested the route on every
  /// location tick — several times a minute while driving — which hammered the
  /// routing service and kept resetting the drawn line.
  ///
  /// The destination is kept at full precision so the leg switching from pickup
  /// to drop always refetches.
  void _ensureRoadRoute(LatLng start, LatLng end) {
    final key =
        '${start.latitude.toStringAsFixed(3)},${start.longitude.toStringAsFixed(3)}'
        '_${end.latitude.toStringAsFixed(5)},${end.longitude.toStringAsFixed(5)}';
    if (key == _roadRouteKey) return;
    _roadRouteKey = key;

    RoutePolylineService.getRoutePoints(pickup: start, drop: end)
        .then((points) {
          if (!mounted || points.isEmpty) return;
          // Guarded against a slow response for a leg the driver has already left.
          if (_roadRouteKey != key) return;
          setState(() => _roadRoute = points);
        })
        .catchError((_) {
          // A failed lookup leaves the previous route drawn; the next tick retries.
          if (_roadRouteKey == key) _roadRouteKey = null;
        });
  }

  String _getStageText(String status) {
    switch (status) {
      case 'accepted':
        return 'Heading To Pickup';
      case 'arriving':
        return 'Arrived At Pickup';
      case 'started':
        return 'Trip In Progress';
      case 'arrived':
        return 'Arrived At Drop';
      default:
        return 'En Route';
    }
  }

  String _formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.toStringAsFixed(0)} m';
    }
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }
}

/// Light Theme Security PIN Bottom Sheet Layout
class _SecurityPinSheet extends StatelessWidget {
  final RideModel ride;
  final bool busy;
  final int waitingSeconds;
  final TextEditingController otpController;
  final VoidCallback onSubmitPin;
  final VoidCallback onGoBack;
  final VoidCallback onSupport;

  const _SecurityPinSheet({
    required this.ride,
    required this.busy,
    required this.waitingSeconds,
    required this.otpController,
    required this.onSubmitPin,
    required this.onGoBack,
    required this.onSupport,
  });

  String _formatTimer(int totalSecs) {
    final mins = (totalSecs ~/ 60).toString().padLeft(2, '0');
    final secs = (totalSecs % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 24,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Title Header
            const Text(
              'SECURITY PIN',
              style: TextStyle(
                color: Color(0xFF0F172A),
                fontWeight: FontWeight.w900,
                fontSize: 20,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'ASK ${ride.riderName.toUpperCase()} FOR START PIN',
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w800,
                fontSize: 11,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 20),

            // Waiting Clock Card (Light Neutral Card)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      // Clock Circle Icon Box
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFFDE68A)),
                        ),
                        child: const Icon(
                          Icons.access_time_filled_rounded,
                          color: Color(0xFFD97706),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      // Waiting Clock Label & Counter
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'WAITING CLOCK',
                              style: TextStyle(
                                color: Color(0xFFD97706),
                                fontSize: 10.5,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _formatTimer(waitingSeconds),
                              style: const TextStyle(
                                color: Color(0xFF0F172A),
                                fontSize: 26,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Free Left Counter
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'FREE LEFT',
                            style: TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            '00:00',
                            style: TextStyle(
                              color: Color(0xFF0F172A),
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // 2 Sub-Chips Inside Card
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'FREE BEFORE RIDE',
                                style: TextStyle(
                                  color: Color(0xFF64748B),
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                '0 min',
                                style: TextStyle(
                                  color: Color(0xFF0F172A),
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'WAITING CHARGE',
                                style: TextStyle(
                                  color: Color(0xFF64748B),
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Rs 0/min • 1 billable',
                                style: TextStyle(
                                  color: Color(0xFF0F172A),
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 4-Digit Security PIN Box Input
            PinCodeTextField(
              appContext: context,
              length: 4,
              controller: otpController,
              autoDisposeControllers: false,
              keyboardType: TextInputType.number,
              animationType: AnimationType.fade,
              onCompleted: (_) => onSubmitPin(),
              onChanged: (_) {},
              textStyle: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
              ),
              pinTheme: PinTheme(
                shape: PinCodeFieldShape.box,
                borderRadius: BorderRadius.circular(18),
                fieldHeight: 64,
                fieldWidth: 60,
                activeColor: const Color(0xFF00C853),
                selectedColor: const Color(0xFF00C853),
                inactiveColor: const Color(0xFFE2E8F0),
                activeFillColor: const Color(0xFFF8FAFC),
                selectedFillColor: Colors.white,
                inactiveFillColor: const Color(0xFFF8FAFC),
              ),
              enableActiveFill: true,
              cursorColor: const Color(0xFF00C853),
            ),
            const SizedBox(height: 20),

            // Submit PIN Button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  foregroundColor: Colors.white,
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                ),
                onPressed: busy ? null : onSubmitPin,
                child: busy
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : const Text(
                        'SUBMIT PIN',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 16),

            // Bottom Action Buttons (GO BACK & SUPPORT)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0F172A),
                      minimumSize: const Size(double.infinity, 50),
                      side: const BorderSide(
                        color: Color(0xFFE2E8F0),
                        width: 1.2,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      backgroundColor: const Color(0xFFF1F5F9),
                    ),
                    onPressed: onGoBack,
                    child: const Text(
                      'GO BACK',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF64748B),
                      minimumSize: const Size(double.infinity, 50),
                    ),
                    onPressed: onSupport,
                    child: const Text(
                      'SUPPORT',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;

  const _MetricChip({required this.label, required this.value, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF222222),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2E2E2E), width: 1),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 13, color: Colors.white),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DarkCircleIconButton extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final VoidCallback onTap;

  const _DarkCircleIconButton({
    required this.icon,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF222222),
      shape: const CircleBorder(
        side: BorderSide(color: Color(0xFF2E2E2E), width: 1.2),
      ),
      elevation: 4,
      shadowColor: Colors.black54,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(icon, color: color ?? Colors.white, size: 20),
        ),
      ),
    );
  }
}

class _DarkIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _DarkIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF222222),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF2E2E2E)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final RideModel ride;
  final bool busy;
  final VoidCallback onArrivedPickup;
  final VoidCallback onStartTrip;
  final VoidCallback onArrivedDrop;
  final VoidCallback onCompleteTrip;

  const _ActionButton({
    required this.ride,
    required this.busy,
    required this.onArrivedPickup,
    required this.onStartTrip,
    required this.onArrivedDrop,
    required this.onCompleteTrip,
  });

  @override
  Widget build(BuildContext context) {
    String label = 'I HAVE ARRIVED';
    IconData icon = Icons.check_circle_outline_rounded;
    VoidCallback onTap = onArrivedPickup;

    switch (ride.liveStatus) {
      case 'accepted':
        label = 'I HAVE ARRIVED';
        icon = Icons.check_circle_outline_rounded;
        onTap = onArrivedPickup;
        break;
      case 'arriving':
        label = 'START TRIP';
        icon = Icons.play_circle_outline_rounded;
        onTap = onStartTrip;
        break;
      case 'started':
        label = ride.rental != null ? 'END TRIP' : 'ARRIVED AT DESTINATION';
        icon = Icons.check_circle_outline_rounded;
        onTap = onArrivedDrop;
        break;
      case 'arrived':
        label = 'COMPLETE TRIP';
        icon = Icons.task_alt_rounded;
        onTap = onCompleteTrip;
        break;
    }

    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: const Color(0xFF11191D),
          elevation: 4,
          shadowColor: AppColors.primary.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
        ),
        onPressed: busy ? null : onTap,
        child: busy
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Color(0xFF11191D),
                  strokeWidth: 2.5,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                      color: Color(0xFF11191D),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(icon, size: 22, color: const Color(0xFF11191D)),
                ],
              ),
      ),
    );
  }
}

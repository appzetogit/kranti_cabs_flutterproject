import '../../../core/constants/app_constants.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../core/services/route_polyline_service.dart';
import '../../../core/theme/app_map_style.dart';
import '../../../shared/widgets/custom_bottom_sheet.dart';
import '../../../shared/widgets/sheet_drag_area.dart';
import '../../../core/utils/image_utils.dart';
import '../application/booking_controller.dart';
import '../data/models/trip_category.dart';
import '../data/models/vehicle_type_model.dart';

import '../../../core/utils/route_marker_helper.dart';
import 'nearby_driver_markers.dart';
import '../../../core/utils/snackbar_utils.dart';
import 'schedule_ride_sheet.dart';

const _fallbackLatLng = LatLng(22.7196, 75.8577);

class RideTypeScreen extends ConsumerStatefulWidget {
  const RideTypeScreen({super.key});

  @override
  ConsumerState<RideTypeScreen> createState() => _RideTypeScreenState();
}

class _RideTypeScreenState extends ConsumerState<RideTypeScreen> {
  GoogleMapController? _mapController;
  List<LatLng> _routePoints = [];
  Map<String, BitmapDescriptor> _customMarkers = {};

  /// How much of the screen the vehicle sheet currently covers.
  ///
  /// The map fills the whole Scaffold and the sheet sits on top of it, so
  /// without this the camera frames the route against the *full* screen and
  /// most of it ends up hidden behind the sheet — the route appeared squashed
  /// into the top strip with the pickup and drop pins pushed off the edges.
  double _sheetExtent = _initialSheetExtent;

  /// Drives the vehicle sheet from its handle and route header. Only the
  /// vehicle list was wired to the sheet, so grabbing the handle bar or the
  /// addresses - where everyone reaches to slide it - did nothing at all.
  final DraggableScrollableController _sheetController = DraggableScrollableController();

  static const double _minSheetExtent = 0.50;
  static const double _maxSheetExtent = 0.92;

  /// The handle and route header slide the sheet too - see [SheetDragArea].
  Widget _dragsSheet(Widget child) => SheetDragArea(
        controller: _sheetController,
        minExtent: _minSheetExtent,
        maxExtent: _maxSheetExtent,
        restExtent: _initialSheetExtent,
        child: child,
      );

  static const double _initialSheetExtent = 0.65;

  /// Map padding never goes past this, so dragging the sheet all the way up
  /// cannot squeeze the camera into a sliver it fails to fit bounds into.
  static const double _maxCameraSheetExtent = 0.66;

  /// The area of the map the rider can actually see, expressed as padding the
  /// camera has to keep clear.
  EdgeInsets get _mapPadding => EdgeInsets.only(
        bottom: MediaQuery.sizeOf(context).height *
            (_sheetExtent > _maxCameraSheetExtent ? _maxCameraSheetExtent : _sheetExtent),
      );

  /// Re-prices the list every minute. Surge starts and ends by the minute, and
  /// the price the rider books at is the one on screen, so it must stay current.
  Timer? _priceRefreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final booking = ref.read(bookingControllerProvider.notifier);
      booking.loadCatalog().then((_) {
        // After the catalog, so the module switch can pick a vehicle from it.
        if (mounted) booking.recheckTrip();
      });
      _fetchRoutePolyline();
      _generateCustomMarkers();
    });
    _priceRefreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) ref.read(bookingControllerProvider.notifier).refreshTariffs();
    });
  }

  @override
  void dispose() {
    _priceRefreshTimer?.cancel();
    _sheetController.dispose();
    super.dispose();
  }

  Future<void> _generateCustomMarkers() async {
    final booking = ref.read(bookingControllerProvider);
    const boxBgColor = Color(0xFF222222);
    const textColor = Colors.white;

    final Map<String, BitmapDescriptor> markers = {};

    if (booking.pickup != null) {
      markers['pickup'] = await RouteMarkerHelper.createCustomPinWithLabel(
        labelText: booking.pickup!.address,
        pinColor: const Color(0xFFF5B400),
        boxBgColor: boxBgColor,
        textColor: textColor,
        prefix: 'Pickup',
      );
    }

    if (booking.drop != null) {
      markers['drop'] = await RouteMarkerHelper.createCustomPinWithLabel(
        labelText: booking.drop!.address,
        pinColor: const Color(0xFFEF4444),
        boxBgColor: boxBgColor,
        textColor: textColor,
        prefix: 'Drop',
      );
    }

    for (int i = 0; i < booking.stops.length; i++) {
      markers['stop_$i'] = await RouteMarkerHelper.createCustomPinWithLabel(
        labelText: booking.stops[i].address,
        pinColor: const Color(0xFF1E88E5),
        boxBgColor: boxBgColor,
        textColor: textColor,
        prefix: 'Stop ${i + 1}',
      );
    }

    if (mounted) {
      setState(() {
        _customMarkers = markers;
      });
    }
  }

  Future<void> _fetchRoutePolyline() async {
    final booking = ref.read(bookingControllerProvider);
    if (booking.pickup == null || booking.drop == null) return;

    final pickup = LatLng(booking.pickup!.lat, booking.pickup!.lng);
    final drop = LatLng(booking.drop!.lat, booking.drop!.lng);
    final stops = booking.stops.map((s) => LatLng(s.lat, s.lng)).toList();

    final points = await RoutePolylineService.getRoutePoints(
      pickup: pickup,
      drop: drop,
      stops: stops,
    );

    if (mounted) {
      setState(() {
        _routePoints = points;
      });
      _fitRouteBounds(points);
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    // Deferred a frame: the map reports itself created before it has applied
    // the padding above, and fitting bounds against a zero padding puts the
    // route back under the sheet.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fitRouteBounds(_routePoints);
    });
  }

  void _fitRouteBounds([List<LatLng>? points]) {
    final booking = ref.read(bookingControllerProvider);
    if (booking.pickup == null || booking.drop == null || _mapController == null) return;

    final pickup = LatLng(booking.pickup!.lat, booking.pickup!.lng);
    final drop = LatLng(booking.drop!.lat, booking.drop!.lng);

    final allPoints = (points != null && points.isNotEmpty) ? points : [pickup, drop];

    double minLat = allPoints.first.latitude;
    double maxLat = allPoints.first.latitude;
    double minLng = allPoints.first.longitude;
    double maxLng = allPoints.first.longitude;

    for (final p in allPoints) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    // 48px inside the visible strip. The sheet is handled by the map's own
    // padding, so this is only breathing room around the pins.
    _mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        48,
      ),
    );
  }

  String _formatDropTime(double? durationSeconds) {
    final minutes = (durationSeconds ?? 0) / 60;
    final dropTime = DateTime.now().add(Duration(minutes: minutes.round()));
    final hour = dropTime.hour > 12 ? dropTime.hour - 12 : (dropTime.hour == 0 ? 12 : dropTime.hour);
    final minute = dropTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final booking = ref.watch(bookingControllerProvider);
    final controller = ref.read(bookingControllerProvider.notifier);

    final pickupLatLng = booking.pickup != null
        ? LatLng(booking.pickup!.lat, booking.pickup!.lng)
        : _fallbackLatLng;
    final dropLatLng =
        booking.drop != null ? LatLng(booking.drop!.lat, booking.drop!.lng) : _fallbackLatLng;

    final List<LatLng> fallbackPolylinePoints = [
      pickupLatLng,
      ...booking.stops.map((s) => LatLng(s.lat, s.lng)),
      dropLatLng,
    ];

    final activePoints = _routePoints.isNotEmpty ? _routePoints : fallbackPolylinePoints;

    const bgColor = Color(0xFF11191D);
    const cardBgColor = Color(0xFF222222);
    const borderColor = Color(0xFF2E2E2E);
    const tealColor = Color(0xFFF5B400);

    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        children: [
          // ==================== LAYER 1: INTERACTIVE GOOGLE MAP ====================
          Positioned.fill(
            child: Stack(
              children: [
                // Wrapped in its own Consumer so the nearby-driver glide
                // ticker (see NearbyDriverAnimationNotifier) only rebuilds
                // the map widget, not this whole screen's build method —
                // the bottom sheet and vehicle list below don't depend on it.
                Consumer(
                  builder: (context, ref, _) {
                    final nearbyDriverMarkers = buildNearbyDriverMarkers(
                      ref,
                      onlyVehicleTypeIds: moduleVehicleTypeIds(ref),
                    );
                    return GoogleMap(
                      style: AppMapStyle.light,
                      initialCameraPosition: CameraPosition(target: pickupLatLng, zoom: 14),
                      // Keeps every camera move — fitting the route, and the
                      // my-location button — inside the strip above the sheet.
                      padding: _mapPadding,
                      onMapCreated: _onMapCreated,
                      myLocationEnabled: false,
                      myLocationButtonEnabled: false,
                      zoomControlsEnabled: false,
                      polylines: {
                        Polyline(
                          polylineId: const PolylineId('ride_route'),
                          points: activePoints,
                          color: tealColor,
                          width: 5,
                          jointType: JointType.round,
                          startCap: Cap.roundCap,
                          endCap: Cap.roundCap,
                        ),
                      },
                      markers: {
                        ...nearbyDriverMarkers,
                        Marker(
                          markerId: const MarkerId('pickup_marker'),
                          position: pickupLatLng,
                          icon: _customMarkers['pickup'] ??
                              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
                        ),
                        Marker(
                          markerId: const MarkerId('drop_marker'),
                          position: dropLatLng,
                          icon: _customMarkers['drop'] ??
                              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                        ),
                        for (int i = 0; i < booking.stops.length; i++)
                          Marker(
                            markerId: MarkerId('stop_$i'),
                            position: LatLng(booking.stops[i].lat, booking.stops[i].lng),
                            icon: _customMarkers['stop_$i'] ??
                                BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
                          ),
                      },
                    );
                  },
                ),

                // Top Floating Back Button
                Positioned(
                  top: MediaQuery.of(context).padding.top + 10,
                  left: 16,
                  child: FloatingActionButton.small(
                    heroTag: 'back_btn',
                    backgroundColor: cardBgColor,
                    foregroundColor: Colors.white,
                    elevation: 3,
                    onPressed: () => context.pop(),
                    child: const Icon(Icons.arrow_back_rounded, size: 20),
                  ),
                ),

                // Top Floating Current Location Button
                Positioned(
                  top: MediaQuery.of(context).padding.top + 10,
                  right: 16,
                  child: FloatingActionButton.small(
                    heroTag: 'my_location_btn',
                    backgroundColor: cardBgColor,
                    foregroundColor: Colors.white,
                    elevation: 3,
                    onPressed: () {
                      // Centres the pickup in the visible strip rather than the
                      // whole screen, which used to drop it behind the sheet.
                      _mapController?.animateCamera(
                        CameraUpdate.newLatLngZoom(pickupLatLng, 16.5),
                      );
                    },
                    child: const Icon(Icons.my_location_rounded, size: 20),
                  ),
                ),
              ],
            ),
          ),

          // ==================== LAYER 2: VEHICLE SELECTION SHEET ====================
          NotificationListener<DraggableScrollableNotification>(
            onNotification: (notification) {
              // Re-frames as the rider drags the sheet, so the route stays in
              // view instead of sliding under it.
              if ((notification.extent - _sheetExtent).abs() > 0.02) {
                setState(() => _sheetExtent = notification.extent);
              }
              return false;
            },
            child: DraggableScrollableSheet(
            controller: _sheetController,
            initialChildSize: _initialSheetExtent,
            minChildSize: _minSheetExtent,
            maxChildSize: _maxSheetExtent,
            builder: (context, scrollController) {
              return Container(
                decoration: const BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black38,
                      blurRadius: 18,
                      offset: Offset(0, -6),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Handle bar and route header both slide the sheet.
                    _dragsSheet(
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                    // Top Drag Handle Bar
                    Container(
                      margin: const EdgeInsets.only(top: 10, bottom: 8),
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFF334155),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),

                    // Header Category & Route Summary Box
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Category Badge Pill (e.g. CATEGORY: CAR)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF044B47),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: tealColor),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: tealColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'CATEGORY: ${(booking.selectedVehicle?.iconType ?? 'CAR').toUpperCase()}',
                                  style: const TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    color: tealColor,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 10),

                          // Route Timeline (Left) & Edit + Clock Schedule (Right)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Route Timeline (Left)
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Pickup Row
                                    Row(
                                      children: [
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: const BoxDecoration(
                                            color: tealColor,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            booking.pickup?.address ?? 'Pickup Location',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),

                                    // Vertical Connecting Line
                                    Padding(
                                      padding: const EdgeInsets.only(left: 3, top: 2, bottom: 2),
                                      child: Container(
                                        width: 2,
                                        height: 14,
                                        color: const Color(0xFF334155),
                                      ),
                                    ),

                                    // Drop Row
                                    Row(
                                      children: [
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: const BoxDecoration(
                                            color: Color(0xFFEF4444),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            booking.drop?.address ?? 'Drop Location',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),

                                    const SizedBox(height: 6),

                                    // Distance & Duration Pills
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: cardBgColor,
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: borderColor),
                                          ),
                                          child: Text(
                                            '${((booking.distanceMeters ?? 0) / 1000).toStringAsFixed(1)} km',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                              color: Color(0xFF60A5FA),
                                            ),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: cardBgColor,
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: borderColor),
                                          ),
                                          child: Text(
                                            '${((booking.durationSeconds ?? 0) / 60).round()} mins',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                              color: Color(0xFF34D399),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (booking.tripCategory != null &&
                                        (booking.tripCategory!.isAirport || booking.tripCategory!.isOutstation)) ...[
                                      const SizedBox(height: 6),
                                      _TripCategoryBadge(trip: booking.tripCategory!),
                                    ],
                                  ],
                                ),
                              ),

                              const SizedBox(width: 10),

                              // Edit & Clock Schedule Button (Right)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextButton(
                                    onPressed: () => context.pop(),
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: const Text(
                                      'Edit',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: tealColor,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),

                                  // Functional Clock Schedule Button
                                  InkWell(
                                    onTap: () async {
                                      final selected = await showModalBottomSheet<DateTime?>(
                                        context: context,
                                        isScrollControlled: true,
                                        backgroundColor: bgColor,
                                        shape: const RoundedRectangleBorder(
                                          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                                        ),
                                        builder: (_) => Padding(
                                          padding: const EdgeInsets.all(20),
                                          child: ScheduleRideSheet(initial: booking.scheduledAt),
                                        ),
                                      );
                                      // Dismissed: keep whatever was set.
                                      if (selected == null) return;
                                      controller.setScheduledAt(
                                        identical(selected, ScheduleRideSheet.rideNow) ? null : selected,
                                      );
                                    },
                                    borderRadius: BorderRadius.circular(14),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: booking.scheduledAt != null
                                            ? const Color(0xFF044B47)
                                            : cardBgColor,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: booking.scheduledAt != null
                                              ? tealColor
                                              : borderColor,
                                          width: 1.2,
                                        ),
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.access_time_rounded,
                                            size: 18,
                                            color: booking.scheduledAt != null
                                                ? tealColor
                                                : Colors.white,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            booking.scheduledAt != null
                                                ? '${booking.scheduledAt!.day}/${booking.scheduledAt!.month}\n${TimeOfDay.fromDateTime(booking.scheduledAt!).format(context)}'
                                                : 'Now',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w800,
                                              color: booking.scheduledAt != null
                                                  ? tealColor
                                                  : Colors.white,
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
                        ],
                      ),
                    ),
                        ],
                      ),
                    ),

                    const Divider(height: 14, color: borderColor),

                    // High-demand banner intentionally hidden in the rider app —
                    // high demand is shown only in the driver (partner) app.

                    // Scrollable Vehicle Types List
                    Expanded(
                      child: () {
                        // Only what the module the rider tapped actually
                        // offers. A vehicle with no modules assigned shows
                        // everywhere, so an untagged catalog behaves exactly as
                        // it did before this filter existed.
                        final taxiVehicles = booking.vehicleTypes
                            .where((v) => v.isOfferedUnderModule(booking.moduleId))
                            // An intercity trip may only be offered on a vehicle
                            // whose own tariff has outstation switched on with
                            // rates behind it. Without this the list showed
                            // city-only cars that would then be quoted, and
                            // driven, on a city tariff for a 300 km trip.
                            .where((v) => !booking.isOutstation || booking.supportsOutstation(v.id))
                            .where((v) => (v.transportType.isEmpty || v.transportType == 'taxi') && v.deliveryCategory.isEmpty)
                            .toList();
                        // Deliberately no "show everything" fallback when the
                        // module has nothing: that would put parcel scooters on
                        // an airport booking, which is the bug this fixes.
                        final displayVehicles = taxiVehicles.isNotEmpty
                            ? taxiVehicles
                            : booking.vehicleTypes
                                .where((v) => v.isOfferedUnderModule(booking.moduleId))
                                .where((v) => !booking.isOutstation || booking.supportsOutstation(v.id))
                                .toList();

                        // Cheapest first. A vehicle with no fare yet (pricing
                        // still loading, or not configured for this route)
                        // sorts to the end rather than dropping out of the
                        // list.
                        displayVehicles.sort((a, b) {
                          final fareA = controller.fareForVehicle(a)?.total ?? double.infinity;
                          final fareB = controller.fareForVehicle(b)?.total ?? double.infinity;
                          return fareA.compareTo(fareB);
                        });

                        if (displayVehicles.isEmpty) {
                          // An empty catalog used to render a spinner forever,
                          // which is indistinguishable from a slow network and
                          // leaves the rider with nothing to do. Loading and
                          // "nothing configured" are now different screens.
                          if (booking.isLoadingCatalog) {
                            return const Center(
                              child: CircularProgressIndicator(color: tealColor),
                            );
                          }

                          return _VehicleListEmptyState(
                            // An outstation list is empty for a specific,
                            // fixable reason — no tariff has intercity enabled
                            // — and saying so beats a generic "unavailable".
                            message: booking.isOutstation
                                ? 'No vehicles are set up for outstation trips yet.'
                                : booking.error ?? 'No vehicles are available right now.',
                            onRetry: controller.loadCatalog,
                          );
                        }

                        return ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          itemCount: displayVehicles.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final vehicle = displayVehicles[index];
                            final fare = controller.fareForVehicle(vehicle);
                            final isSelected = booking.selectedVehicle?.id == vehicle.id;
                            final dropTimeStr = _formatDropTime(booking.durationSeconds);
                            final etaMinutes = booking.etaMinutesByVehicle[vehicle.id];

                            return _VehicleSelectionTile(
                              vehicle: vehicle,
                              calculatedPrice: fare?.total,
                              discount: controller.promoDiscountFor(vehicle),
                              surgeLabel: null, // high demand hidden in rider app
                              dropTimeStr: dropTimeStr,
                              etaMinutes: etaMinutes,
                              isSelected: isSelected,
                              onTap: () => controller.selectVehicle(vehicle),
                            );
                          },
                        );
                      }(),
                    ),

                    // Bottom Action Bar & CTA Button
                    SafeArea(
                      top: false,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                        decoration: const BoxDecoration(
                          color: bgColor,
                          border: Border(top: BorderSide(color: borderColor)),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                          // Segmented Row (Payment | Coupon). The "Myself"
                          // segment was a dead tap with no booking-for-others
                          // flow behind it, so it is gone rather than shown.
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: cardBgColor,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: borderColor),
                            ),
                            child: Row(
                              children: [
                                // 1. Cash Button
                                Expanded(
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () => _showPaymentSheet(context, controller, booking.paymentMethod),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const Icon(Icons.payments_outlined, size: 16, color: tealColor),
                                          const SizedBox(width: 6),
                                          Text(
                                            switch (booking.paymentMethod) {
                                              'cash' => 'Cash',
                                              // Matches the option's name in the payment sheet.
                                              'razorpay' => 'Card/UPI',
                                              final other => other.toUpperCase(),
                                            },
                                            style: const TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                Container(height: 16, width: 1, color: borderColor),
                                // 2. Coupon Button
                                Expanded(
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () => _showPromoSheet(context, controller, booking.appliedPromo?.code),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const Icon(Icons.confirmation_number_outlined, size: 16, color: Color(0xFF60A5FA)),
                                          const SizedBox(width: 6),
                                          // Flexible so a long code ellipsizes inside its
                                          // half of the bar instead of overflowing it.
                                          Flexible(
                                            child: Text(
                                              () {
                                                final code = booking.appliedPromo?.code;
                                                if (code == null) return 'Coupon';
                                                final vehicle = booking.selectedVehicle;
                                                final off = vehicle == null ? 0.0 : controller.promoDiscountFor(vehicle);
                                                // A code that does not cover this ride says so rather than
                                                // looking applied.
                                                return off > 0 ? '$code −₹${off.round()}' : '$code (n/a)';
                                              }(),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.w700,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 10),

                          // Why Book is disabled, when it is: no price for this
                          // vehicle in this zone, or the fare still loading.
                          if (controller.bookingBlocker != null) ...[
                            Text(
                              controller.bookingBlocker!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFFCA5A5),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],

                          // Large CTA Button (Book / Schedule <VehicleName>)
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: tealColor,
                                foregroundColor: const Color(0xFF0A0A0A),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              onPressed: booking.isSubmitting || controller.bookingBlocker != null
                                  ? null
                                  : () async {
                                      final wasScheduled = booking.scheduledAt != null;
                                      // Surge confirmation removed: high demand is a driver-app-only concept now.
                                      if (!context.mounted) return;
                                      var attempt = await controller.confirmBooking();
                                      if (attempt == BookingAttempt.kycRequired && context.mounted) {
                                        final needsReview = ref.read(bookingControllerProvider).error?.toLowerCase().contains('review') ?? false;
                                        if (!needsReview && await context.push<bool>('/profile/verify-identity', extra: true) == true) {
                                          attempt = await controller.confirmBooking();
                                        }
                                      }

                                      if (!context.mounted) return;
                                      // Nothing was sent; the reason is shown above.
                                      if (attempt == BookingAttempt.notReady || attempt == BookingAttempt.kycRequired) return;
                                      if (attempt == BookingAttempt.failed) {
                                        context.pushReplacement('/home/no-driver');
                                        return;
                                      }

                                      if (wasScheduled) {
                                        // A reservation has no search to watch: left
                                        // running, the search polled and could show
                                        // "no driver found" for a ride days away.
                                        controller.reset();
                                        SnackbarUtils.success(
                                          context,
                                          'Ride scheduled. We will tell you when a driver is assigned.',
                                        );
                                        context.go('/rides');
                                        return;
                                      }

                                      context.pushReplacement('/home/finding-driver');
                                    },
                              child: booking.isSubmitting
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: Color(0xFF0A0A0A),
                                      ),
                                    )
                                  : Text(
                                      booking.scheduledAt != null
                                          ? 'Schedule ${booking.selectedVehicle?.name ?? 'Ride'}'
                                          : 'Book ${booking.selectedVehicle?.name ?? 'Ride'}',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w900,
                                        color: Color(0xFF0A0A0A),
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  ],
                ),
              );
            },
            ),
          ),
        ],
      ),
    );
  }

  void _showPaymentSheet(BuildContext context, BookingController controller, String current) {
    CustomBottomSheet.show(
      context,
      title: 'Select Payment Method',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: const Text('Cash', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            leading: const Icon(Icons.money_rounded, color: Color(0xFFF5B400)),
            trailing: current == 'cash' ? const Icon(Icons.check_rounded, color: Color(0xFFF5B400)) : null,
            onTap: () {
              controller.setPaymentMethod('cash');
              Navigator.of(context).pop();
            },
          ),
          if (AppConstants.onlinePaymentsEnabled)
          ListTile(
            title: const Text('Card / UPI', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            leading: const Icon(Icons.credit_card_rounded, color: Color(0xFF60A5FA)),
            trailing: current == 'razorpay' ? const Icon(Icons.check_rounded, color: Color(0xFFF5B400)) : null,
            onTap: () {
              controller.setPaymentMethod('razorpay');
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }

  void _showPromoSheet(BuildContext context, BookingController controller, String? currentPromo) {
    final textController = TextEditingController(text: currentPromo);
    String? error;
    bool checking = false;

    CustomBottomSheet.show(
      context,
      title: 'Apply Coupon',
      child: StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          Future<void> apply() async {
            if (checking) return;
            setSheetState(() {
              checking = true;
              error = null;
            });
            final refusal = await controller.applyPromoCode(textController.text);
            if (!sheetContext.mounted) return;
            if (refusal != null) {
              setSheetState(() {
                checking = false;
                error = refusal;
              });
              return;
            }
            Navigator.of(sheetContext).pop();
            if (textController.text.trim().isNotEmpty && context.mounted) {
              SnackbarUtils.success(context, 'Coupon applied');
            }
          }

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: textController,
                  textCapitalization: TextCapitalization.characters,
                  enabled: !checking,
                  onSubmitted: (_) => apply(),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  cursorColor: const Color(0xFFF5B400),
                  decoration: InputDecoration(
                    hintText: 'Enter promo code (e.g. RIDE100)',
                    hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                    errorText: error,
                    errorMaxLines: 2,
                    enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF2A2A2A))),
                    focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFF5B400))),
                    errorBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFF87171))),
                    focusedErrorBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFF87171))),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF5B400),
                      foregroundColor: const Color(0xFF0A0A0A),
                    ),
                    onPressed: checking ? null : apply,
                    child: checking
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF0A0A0A)),
                          )
                        : const Text('Apply', style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ),
                if (currentPromo != null) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: checking
                        ? null
                        : () {
                            controller.applyPromoCode(null);
                            Navigator.of(sheetContext).pop();
                          },
                    child: const Text(
                      'Remove coupon',
                      style: TextStyle(color: Color(0xFFF87171), fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _VehicleSelectionTile extends StatelessWidget {
  final VehicleTypeModel vehicle;
  final double? calculatedPrice;

  /// Coupon discount on [calculatedPrice]; 0 when none applies.
  final double discount;

  /// "1.10x" while the pickup is surging - already in [calculatedPrice].
  final String? surgeLabel;
  final String dropTimeStr;
  final int? etaMinutes;
  final bool isSelected;
  final VoidCallback onTap;

  const _VehicleSelectionTile({
    required this.vehicle,
    required this.calculatedPrice,
    this.discount = 0,
    this.surgeLabel,
    required this.dropTimeStr,
    required this.etaMinutes,
    required this.isSelected,
    required this.onTap,
  });

  String _assetForVehicle(String iconType, String name) {
    final lower = (iconType + name).toLowerCase();
    if (lower.contains('bike')) return 'assets/bike_service.webp';
    if (lower.contains('parcel')) return 'assets/parcel.webp';
    if (lower.contains('auto') || lower.contains('rickshaw')) return 'assets/markerauto.webp';
    // Only assets that are actually bundled — booknow.png and allservice.png
    // are referenced across the app but do not exist, and Image.asset throws
    // "Asset not found" rather than degrading.
    return 'assets/car.webp';
  }

  String _subtitleCategory(VehicleTypeModel vehicle) {
    if (vehicle.shortDescription.isNotEmpty) return vehicle.shortDescription;
    if (vehicle.description.isNotEmpty) return vehicle.description;
    final nameLower = vehicle.name.toLowerCase();
    if (nameLower.contains('mini') || nameLower.contains('auto') || nameLower.contains('bike')) {
      return 'Affordable';
    }
    if (nameLower.contains('sedan') || nameLower.contains('cab')) {
      return 'Comfortable';
    }
    if (nameLower.contains('suv') || nameLower.contains('xl') || nameLower.contains('ertiga') || nameLower.contains('fortuner')) {
      return 'Spacious';
    }
    if (nameLower.contains('premium') || nameLower.contains('luxury') || nameLower.contains('innova')) {
      return 'Luxury';
    }
    return 'Comfortable';
  }

  @override
  Widget build(BuildContext context) {
    final assetPath = _assetForVehicle(vehicle.iconType, vehicle.name);
    // The catalog stores vehicle art as a server-relative path
    // (`/vehicles/fortuner.jpg`), never an absolute URL. Handing that straight
    // to CachedNetworkImage is not a loadable URL, so every tile failed to its
    // errorWidget and drew the bundled placeholder instead of the real vehicle.
    final backendImageUrl = resolveMediaUrl(
      vehicle.image.isNotEmpty ? vehicle.image : vehicle.mapIcon,
    );
    // buildSafeImageProvider covers http(s), data: URIs and local files, and
    // returns null for anything unusable so the bundled art can take over.
    final vehicleImage = buildSafeImageProvider(backendImageUrl);

    const tealColor = Color(0xFFF5B400);
    const cardBgColor = Color(0xFF222222);
    const borderColor = Color(0xFF2E2E2E);
    const textSecondary = Color(0xFF94A3B8);

    // No ETA is shown rather than a made-up one when none came back.
    final etaMin = etaMinutes;
    final capText = vehicle.capacity > 0 ? '${vehicle.capacity} Seater' : '';
    final categoryText = _subtitleCategory(vehicle);
    final subtitleFull = [
      if (capText.isNotEmpty) capText,
      if (categoryText.isNotEmpty) categoryText,
    ].join(' • ');

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: cardBgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? tealColor : borderColor,
            width: isSelected ? 1.8 : 1,
          ),
        ),
        child: Row(
          children: [
            // 1. Radio Button Indicator (1:1 Matching Image 2)
            Icon(
              isSelected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: isSelected ? tealColor : const Color(0xFF334155),
              size: 20,
            ),
            const SizedBox(width: 10),

            // 2. High-Fidelity Vehicle Graphic Image
            Container(
              width: 74,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF11191D),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected
                      ? tealColor.withValues(alpha: 0.5)
                      : const Color(0xFF2E2E2E),
                  width: isSelected ? 1.4 : 0.8,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: vehicleImage != null
                    ? Image(
                        image: vehicleImage,
                        width: 74,
                        height: 48,
                        fit: BoxFit.cover,
                        alignment: Alignment.center,
                        gaplessPlayback: true,
                        errorBuilder: (context, error, stackTrace) => Container(
                          padding: const EdgeInsets.all(5),
                          child: Image.asset(
                            assetPath,
                            fit: BoxFit.contain,
                            alignment: Alignment.center,
                          ),
                        ),
                      )
                    : Container(
                        padding: const EdgeInsets.all(5),
                        child: Image.asset(
                          assetPath,
                          fit: BoxFit.contain,
                          alignment: Alignment.center,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),

            // 3. Dynamic Name & Capacity/Comfort Subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    vehicle.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitleFull,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: textSecondary,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 10),

            // 4. Dynamic Price & ETA Range
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (calculatedPrice != null && discount > 0)
                  Text(
                    '₹${calculatedPrice!.round()}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: textSecondary,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                Text(
                  calculatedPrice == null
                      ? '--'
                      : '₹${(calculatedPrice! - discount).clamp(0, double.infinity).round()}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: discount > 0 ? const Color(0xFFF5B400) : Colors.white,
                  ),
                ),
                if (surgeLabel != null)
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFF059669),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '⚡ $surgeLabel',
                      style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: Colors.white),
                    ),
                  ),
                if (etaMin != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    '$etaMin-${etaMin + 2} min',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown when the catalog came back with nothing to book.
///
/// Deliberately explicit about the cause and offers a retry: the two real
/// reasons are a dropped request and an empty vehicle catalog on the server,
/// and the rider can only do something about the first.
class _VehicleListEmptyState extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _VehicleListEmptyState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    // Matches the accent the rest of this screen uses; it is declared per-build
    // there rather than as a file-level constant.
    const tealColor = Color(0xFFF5B400);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_transfer_outlined, size: 44, color: Color(0xFF64748B)),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Pull to retry, or try again in a moment.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              style: OutlinedButton.styleFrom(
                foregroundColor: tealColor,
                side: const BorderSide(color: tealColor),
                minimumSize: const Size(0, 42),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(21)),
              ),
              label: const Text('Retry', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Airport trip · Kempegowda" or "Outstation trip" under the route, so a rider
/// who tapped City Ride sees why the list now shows airport or outstation cabs.
class _TripCategoryBadge extends StatelessWidget {
  final TripCategory trip;

  const _TripCategoryBadge({required this.trip});

  @override
  Widget build(BuildContext context) {
    final airport = trip.isAirport;
    final label = airport
        ? 'Airport trip${trip.airportName != null ? ' · ${trip.airportName}' : ''}'
            '${trip.airportFee > 0 ? ' · ₹${trip.airportFee.round()} airport fee incl.' : ''}'
        : 'Outstation trip · intercity cabs';
    final colour = airport ? const Color(0xFF60A5FA) : const Color(0xFFFBBF24);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colour.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(airport ? Icons.flight_rounded : Icons.alt_route_rounded, size: 13, color: colour),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: colour),
            ),
          ),
        ],
      ),
    );
  }
}

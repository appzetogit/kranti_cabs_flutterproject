import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/services/route_polyline_service.dart';
import '../../../core/theme/app_map_style.dart';
import '../../../core/utils/image_utils.dart';
import '../../../core/utils/route_marker_helper.dart';
import '../../../core/utils/snackbar_utils.dart';
import '../application/delivery_booking_controller.dart';

const _fallbackLatLng = LatLng(22.7196, 75.8577);

/// Step 4 of the delivery flow: pick a priced vehicle and book.
///
/// Comes after parcel details rather than before the address, mirroring the
/// ride flow's own vehicle-selection screen ([RideTypeScreen]) both in
/// behaviour and, deliberately, in look — same map-with-route header, same
/// route summary card, same radio-style vehicle list. The old flow asked for
/// a vehicle up front and then tried to price only that one, which is why the
/// address screen used to show a single "Approx. Delivery Fare" card before
/// the rider had compared anything.
class DeliveryVehicleSelectScreen extends ConsumerStatefulWidget {
  const DeliveryVehicleSelectScreen({super.key});

  @override
  ConsumerState<DeliveryVehicleSelectScreen> createState() =>
      _DeliveryVehicleSelectScreenState();
}

class _DeliveryVehicleSelectScreenState
    extends ConsumerState<DeliveryVehicleSelectScreen> {
  GoogleMapController? _mapController;
  List<LatLng> _routePoints = [];
  Map<String, BitmapDescriptor> _customMarkers = {};

  DeliveryVehicleOption? _selected;
  bool _booking = false;

  static const double _initialSheetExtent = 0.65;
  static const double _maxCameraSheetExtent = 0.62;

  EdgeInsets get _mapPadding => EdgeInsets.only(
    bottom: MediaQuery.sizeOf(context).height * _maxCameraSheetExtent,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchRoutePolyline();
      _generateCustomMarkers();
    });
  }

  BookingLikeLocation? get _pickup {
    final p = ref.read(deliveryBookingProvider).pickup;
    if (p == null) return null;
    return BookingLikeLocation(lat: p.lat, lng: p.lng, address: p.address);
  }

  BookingLikeLocation? get _drop {
    final d = ref.read(deliveryBookingProvider).drop;
    if (d == null) return null;
    return BookingLikeLocation(lat: d.lat, lng: d.lng, address: d.address);
  }

  Future<void> _generateCustomMarkers() async {
    final pickup = _pickup;
    final drop = _drop;
    const boxBgColor = Color(0xFF222222);
    const textColor = Colors.white;

    final Map<String, BitmapDescriptor> markers = {};

    if (pickup != null) {
      markers['pickup'] = await RouteMarkerHelper.createCustomPinWithLabel(
        labelText: pickup.address,
        pinColor: const Color(0xFFF5B400),
        boxBgColor: boxBgColor,
        textColor: textColor,
        prefix: 'Pickup',
      );
    }

    if (drop != null) {
      markers['drop'] = await RouteMarkerHelper.createCustomPinWithLabel(
        labelText: drop.address,
        pinColor: const Color(0xFFEF4444),
        boxBgColor: boxBgColor,
        textColor: textColor,
        prefix: 'Drop',
      );
    }

    if (mounted) setState(() => _customMarkers = markers);
  }

  Future<void> _fetchRoutePolyline() async {
    final pickup = _pickup;
    final drop = _drop;
    if (pickup == null || drop == null) return;

    final points = await RoutePolylineService.getRoutePoints(
      pickup: LatLng(pickup.lat, pickup.lng),
      drop: LatLng(drop.lat, drop.lng),
    );

    if (!mounted) return;
    setState(() => _routePoints = points);
    _fitRouteBounds(points);
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fitRouteBounds(_routePoints);
    });
  }

  void _fitRouteBounds([List<LatLng>? points]) {
    final pickup = _pickup;
    final drop = _drop;
    if (pickup == null || drop == null || _mapController == null) return;

    final pickupLatLng = LatLng(pickup.lat, pickup.lng);
    final dropLatLng = LatLng(drop.lat, drop.lng);
    final allPoints = (points != null && points.isNotEmpty)
        ? points
        : [pickupLatLng, dropLatLng];

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

  /// Waits for the controller's own quote to catch up with [id].
  ///
  /// The tile is already priced from the list this screen fetched, but
  /// `confirm()` reads the quote back off controller state, not off this
  /// screen's copy, so state has to catch up before booking.
  Future<bool> _awaitControllerQuote(String id) async {
    for (var attempt = 0; attempt < 20; attempt++) {
      final state = ref.read(deliveryBookingProvider);
      if (state.vehicleTypeId == id && state.quote != null) return true;
      if (state.vehicleTypeId == id && state.error != null) return false;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    return false;
  }

  Future<void> _book() async {
    final option = _selected;
    if (option == null || _booking) return;

    setState(() => _booking = true);

    ref
        .read(deliveryBookingProvider.notifier)
        .selectVehicle(id: option.vehicle.id, name: option.vehicle.name);

    final ready = await _awaitControllerQuote(option.vehicle.id);
    if (!mounted) return;

    if (!ready) {
      SnackbarUtils.error(
        context,
        'Could not price this vehicle. Please try another one.',
      );
      setState(() => _booking = false);
      return;
    }

    try {
      final rideId = await ref.read(deliveryBookingProvider.notifier).confirm();
      if (!mounted) return;
      context.pushReplacement('/delivery/finding/$rideId');
    } catch (e) {
      if (!mounted) return;
      SnackbarUtils.error(context, e.toString());
      setState(() => _booking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pickup = _pickup;
    final drop = _drop;
    final optionsAsync = ref.watch(deliveryVehicleQuotesProvider);

    final pickupLatLng = pickup != null
        ? LatLng(pickup.lat, pickup.lng)
        : _fallbackLatLng;
    final dropLatLng = drop != null
        ? LatLng(drop.lat, drop.lng)
        : _fallbackLatLng;
    final polylinePoints = _routePoints.isNotEmpty
        ? _routePoints
        : [pickupLatLng, dropLatLng];

    const bgColor = Color(0xFF11191D);
    const cardBgColor = Color(0xFF222222);
    const borderColor = Color(0xFF2E2E2E);
    const tealColor = Color(0xFFF5B400);

    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        children: [
          // ==================== LAYER 1: MAP WITH ROUTE ====================
          Positioned.fill(
            child: Stack(
              children: [
                GoogleMap(
                  style: AppMapStyle.light,
                  initialCameraPosition: CameraPosition(
                    target: pickupLatLng,
                    zoom: 14,
                  ),
                  padding: _mapPadding,
                  onMapCreated: _onMapCreated,
                  myLocationEnabled: false,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  polylines: {
                    Polyline(
                      polylineId: const PolylineId('delivery_route'),
                      points: polylinePoints,
                      color: tealColor,
                      width: 5,
                      jointType: JointType.round,
                      startCap: Cap.roundCap,
                      endCap: Cap.roundCap,
                    ),
                  },
                  markers: {
                    Marker(
                      markerId: const MarkerId('pickup_marker'),
                      position: pickupLatLng,
                      icon:
                          _customMarkers['pickup'] ??
                          BitmapDescriptor.defaultMarkerWithHue(
                            BitmapDescriptor.hueGreen,
                          ),
                    ),
                    Marker(
                      markerId: const MarkerId('drop_marker'),
                      position: dropLatLng,
                      icon:
                          _customMarkers['drop'] ??
                          BitmapDescriptor.defaultMarkerWithHue(
                            BitmapDescriptor.hueRed,
                          ),
                    ),
                  },
                ),
                Positioned(
                  top: MediaQuery.of(context).padding.top + 10,
                  left: 16,
                  child: FloatingActionButton.small(
                    heroTag: 'delivery_back_btn',
                    backgroundColor: cardBgColor,
                    foregroundColor: Colors.white,
                    elevation: 3,
                    onPressed: () => context.pop(),
                    child: const Icon(Icons.arrow_back_rounded, size: 20),
                  ),
                ),
              ],
            ),
          ),

          // ==================== LAYER 2: VEHICLE SELECTION SHEET ====================
          DraggableScrollableSheet(
            initialChildSize: _initialSheetExtent,
            minChildSize: 0.50,
            maxChildSize: 0.92,
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
                    Container(
                      margin: const EdgeInsets.only(top: 10, bottom: 8),
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFF334155),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
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
                                  'CATEGORY: ${(_selected?.vehicle.iconType ?? 'PARCEL').toUpperCase()}',
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
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
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
                                            pickup?.address ??
                                                'Pickup location',
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
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        left: 3,
                                        top: 2,
                                        bottom: 2,
                                      ),
                                      child: Container(
                                        width: 2,
                                        height: 14,
                                        color: const Color(0xFF334155),
                                      ),
                                    ),
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
                                            drop?.address ?? 'Drop location',
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
                                    optionsAsync.maybeWhen(
                                      data: (options) => options.isEmpty
                                          ? const SizedBox.shrink()
                                          : _DistancePill(
                                              distanceKm: options
                                                  .first
                                                  .quote
                                                  .distanceKm,
                                            ),
                                      orElse: () => const SizedBox.shrink(),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              TextButton(
                                onPressed: () => context.pop(),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
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
                            ],
                          ),
                        ],
                      ),
                    ),

                    const Divider(height: 14, color: borderColor),

                    Expanded(
                      child: optionsAsync.when(
                        loading: () => const Center(
                          child: CircularProgressIndicator(color: tealColor),
                        ),
                        error: (error, _) => _VehicleListEmptyState(
                          message: 'Could not load vehicles: $error',
                          onRetry: () async =>
                              ref.invalidate(deliveryVehicleQuotesProvider),
                        ),
                        data: (options) {
                          if (options.isEmpty) {
                            return _VehicleListEmptyState(
                              message:
                                  'No delivery vehicle is priced for this route yet. '
                                  'Please try a different pickup or drop location.',
                              onRetry: () async =>
                                  ref.invalidate(deliveryVehicleQuotesProvider),
                            );
                          }

                          return ListView.separated(
                            controller: scrollController,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 6,
                            ),
                            itemCount: options.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final option = options[index];
                              final isSelected =
                                  _selected?.vehicle.id == option.vehicle.id;
                              return _VehicleSelectionTile(
                                option: option,
                                isSelected: isSelected,
                                onTap: _booking
                                    ? null
                                    : () => setState(() => _selected = option),
                              );
                            },
                          );
                        },
                      ),
                    ),

                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      decoration: const BoxDecoration(
                        color: bgColor,
                        border: Border(top: BorderSide(color: borderColor)),
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: tealColor,
                            foregroundColor: const Color(0xFF0A0A0A),
                            disabledBackgroundColor: const Color(0xFF334155),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: _selected == null || _booking
                              ? null
                              : _book,
                          child: _booking
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Color(0xFF0A0A0A),
                                  ),
                                )
                              : Text(
                                  _selected != null
                                      ? 'Book ${_selected!.vehicle.name}'
                                      : 'Select a vehicle',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF0A0A0A),
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Lightweight stand-in for `BookingLocation` so this screen does not have to
/// import the ride feature's state class just to read three fields.
class BookingLikeLocation {
  final double lat;
  final double lng;
  final String address;
  const BookingLikeLocation({
    required this.lat,
    required this.lng,
    required this.address,
  });
}

class _DistancePill extends StatelessWidget {
  final double distanceKm;
  const _DistancePill({required this.distanceKm});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF222222),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2E2E2E)),
      ),
      child: Text(
        '${distanceKm.toStringAsFixed(1)} km',
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: Color(0xFF60A5FA),
        ),
      ),
    );
  }
}

class _VehicleSelectionTile extends StatelessWidget {
  final DeliveryVehicleOption option;
  final bool isSelected;
  final VoidCallback? onTap;

  const _VehicleSelectionTile({
    required this.option,
    required this.isSelected,
    required this.onTap,
  });

  String _fallbackAsset() {
    final key = '${option.vehicle.iconType}${option.vehicle.name}'
        .toLowerCase();
    if (key.contains('bike') ||
        key.contains('scoot') ||
        key.contains('2wheeler')) {
      return 'assets/scooter_cat.webp';
    }
    if (key.contains('auto') || key.contains('rickshaw')) {
      return 'assets/auto_cat.webp';
    }
    if (key.contains('truck') || key.contains('van') || key.contains('mover')) {
      return 'assets/truck_cat.webp';
    }
    return 'assets/movers_cat.png';
  }

  @override
  Widget build(BuildContext context) {
    const tealColor = Color(0xFFF5B400);
    const cardBgColor = Color(0xFF222222);
    const borderColor = Color(0xFF2E2E2E);
    const textSecondary = Color(0xFF94A3B8);

    final assetPath = _fallbackAsset();
    final backendImageUrl = resolveMediaUrl(
      option.vehicle.image.isNotEmpty
          ? option.vehicle.image
          : option.vehicle.mapIcon,
    );
    final vehicleImage = buildSafeImageProvider(backendImageUrl);

    final subtitle = option.vehicle.shortDescription.isNotEmpty
        ? option.vehicle.shortDescription
        : (option.vehicle.description.isNotEmpty
              ? option.vehicle.description
              : 'Parcel delivery');

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
            Icon(
              isSelected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: isSelected ? tealColor : const Color(0xFF334155),
              size: 20,
            ),
            const SizedBox(width: 10),
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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.vehicle.name,
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
                    subtitle,
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
            Text(
              '₹${option.quote.total.round()}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VehicleListEmptyState extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _VehicleListEmptyState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    const tealColor = Color(0xFFF5B400);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.no_transfer_outlined,
              size: 44,
              color: Color(0xFF64748B),
            ),
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
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              style: OutlinedButton.styleFrom(
                foregroundColor: tealColor,
                side: const BorderSide(color: tealColor),
                minimumSize: const Size(0, 42),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(21),
                ),
              ),
              label: const Text(
                'Retry',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_map_style.dart';
import '../../../core/utils/snackbar_utils.dart';
import '../../home/presentation/nearby_driver_markers.dart';
import '../../ride/application/ride_tracking_controller.dart';
import '../application/delivery_booking_controller.dart';

/// Step 3: the booking exists and dispatch is notifying nearby captains.
/// Includes animated radar map pulse and dynamic light & dark theme support.
class FindingCaptainScreen extends ConsumerStatefulWidget {
  final String rideId;
  const FindingCaptainScreen({super.key, required this.rideId});

  @override
  ConsumerState<FindingCaptainScreen> createState() => _FindingCaptainScreenState();
}

class _FindingCaptainScreenState extends ConsumerState<FindingCaptainScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  bool _cancelling = false;
  bool _left = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _cancel() async {
    if (_cancelling) return;
    setState(() => _cancelling = true);

    final ok = await ref
        .read(rideTrackingControllerProvider(widget.rideId).notifier)
        .cancelRide(reason: 'Cancelled by sender');

    if (!mounted) return;
    if (ok) {
      ref.read(deliveryBookingProvider.notifier).reset();
      context.go('/home');
    } else {
      SnackbarUtils.error(context, 'Could not cancel. Please try again.');
      setState(() => _cancelling = false);
    }
  }

  Widget _radarRing(double t) {
    final size = 40 + t * 140;
    final opacity = (1 - t).clamp(0.0, 1.0) * 0.5;
    return Opacity(
      opacity: opacity,
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: Color(0xFF10B981),
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tracking = ref.watch(rideTrackingControllerProvider(widget.rideId));
    final ride = tracking.ride;
    final booking = ref.watch(deliveryBookingProvider);

    ref.listen(rideTrackingControllerProvider(widget.rideId), (previous, next) {
      final r = next.ride;
      if (r == null || _left) return;

      // A captain accepted — hand over to live tracking.
      if (r.driver != null && r.status.toLowerCase() != 'searching') {
        _left = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.pushReplacement('/ride/tracking/${widget.rideId}');
        });
        return;
      }

      // Dispatch gave up, or the parcel was cancelled elsewhere.
      if (r.isCancelled) {
        _left = true;
        // The sender's own cancel already explains itself; otherwise say why
        // the screen closed instead of silently dropping them on Home.
        final explain = !_cancelling;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (explain) SnackbarUtils.info(context, 'No captains available right now');
          context.go('/home');
        });
      }
    });

    final pickup = ride != null
        ? LatLng(ride.pickup.lat, ride.pickup.lng)
        : LatLng(booking.pickup?.lat ?? 22.7196, booking.pickup?.lng ?? 75.8577);

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
        body: Column(
          children: [
            // ==================== MAP WITH RADAR PULSE ====================
            Expanded(
              flex: 5,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Its own Consumer so the nearby-driver glide ticker only
                  // rebuilds the map, not this whole screen.
                  Consumer(
                    builder: (context, ref, _) {
                      final nearbyDriverMarkers = buildNearbyDriverMarkers(ref);
                      return GoogleMap(
                        style: AppMapStyle.light,
                        initialCameraPosition: CameraPosition(target: pickup, zoom: 15),
                        myLocationEnabled: false,
                        myLocationButtonEnabled: false,
                        zoomControlsEnabled: false,
                        scrollGesturesEnabled: false,
                        markers: {
                          ...nearbyDriverMarkers,
                          Marker(
                            markerId: const MarkerId('pickup'),
                            position: pickup,
                            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
                          ),
                          if (ride != null)
                            Marker(
                              markerId: const MarkerId('drop'),
                              position: LatLng(ride.drop.lat, ride.drop.lng),
                              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                            ),
                        },
                      );
                    },
                  ),

                  // Animated Radar Pulse
                  IgnorePointer(
                    child: Center(
                      child: AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          return Stack(
                            alignment: Alignment.center,
                            children: [
                              for (final delay in [0.0, 0.33, 0.66])
                                _radarRing((_pulseController.value + delay) % 1.0),
                              Container(
                                width: 14,
                                height: 14,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF10B981),
                                  shape: BoxShape.circle,
                                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),

                  // Top Parcel Route Card Overlay
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E293B) : Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: isDark ? Border.all(color: const Color(0xFF334155)) : null,
                            boxShadow: [
                              BoxShadow(
                                color: isDark ? Colors.black38 : const Color(0x1A000000),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'PARCEL ROUTE',
                                style: TextStyle(
                                  fontSize: 9,
                                  letterSpacing: 0.7,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF94A3B8),
                                ),
                              ),
                              Text(
                                ride?.pickupAddress ??
                                    booking.pickup?.address ??
                                    'Pickup location',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: isDark ? Colors.white : const Color(0xFF0F172A),
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
            ),

            // ==================== BOTTOM DETAILS PANEL ====================
            Expanded(
              flex: 4,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  boxShadow: [
                    BoxShadow(
                      color: isDark ? Colors.black38 : Colors.black12,
                      blurRadius: 18,
                      offset: const Offset(0, -6),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Text(
                      'Finding your delivery captain',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Booking created. Notifying nearby captains…',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF451A03) : const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDark ? const Color(0xFF7C2D12) : const Color(0xFFFED7AA),
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'EXPECTED PRICE',
                            style: TextStyle(
                              fontSize: 9.5,
                              letterSpacing: 0.7,
                              fontWeight: FontWeight.w800,
                              color: isDark ? const Color(0xFFFF8550) : const Color(0xFFEA580C),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Rs ${(ride?.fare ?? booking.quote?.total ?? 0).toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                            ),
                          ),
                          if (booking.quote != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 18),
                              child: Text(
                                'Estimated for about ${booking.quote!.distanceKm.toStringAsFixed(1)} km. '
                                'Includes ${booking.quote!.serviceTaxPercentage.toStringAsFixed(2)}% service tax.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: isDark ? const Color(0xFFFDBA74) : const Color(0xFF9A3412),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _Chip(icon: Icons.bolt, label: 'FAST DISPATCH'),
                        SizedBox(width: 10),
                        _Chip(icon: Icons.verified_user_outlined, label: 'PARCEL SAFETY'),
                      ],
                    ),
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _cancelling ? null : _cancel,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          side: BorderSide(
                            color: isDark ? const Color(0xFF991B1B) : const Color(0xFFFECACA),
                          ),
                          backgroundColor: isDark ? const Color(0xFF451212) : const Color(0xFFFEF2F2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _cancelling
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(
                                'CANCEL SEARCH',
                                style: TextStyle(
                                  color: isDark ? const Color(0xFFFCA5A5) : const Color(0xFFEF4444),
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.4,
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
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Chip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: isDark ? const Color(0xFF60A5FA) : AppColors.primary),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              color: isDark ? Colors.white : const Color(0xFF334155),
            ),
          ),
        ],
      ),
    );
  }
}

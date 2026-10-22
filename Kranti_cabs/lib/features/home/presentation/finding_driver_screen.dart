import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_map_style.dart';
import '../../../core/utils/snackbar_utils.dart';
import '../../ride/application/ride_providers.dart';
import '../../ride/presentation/cancel_reason_sheet.dart';
import '../application/booking_controller.dart';
import '../application/booking_state.dart';
import '../application/ride_search_controller.dart';
import '../application/ride_search_state.dart';
import 'nearby_driver_markers.dart';
import 'widgets/raise_fare_card.dart';
import '../../../shared/widgets/vehicle_art.dart';

const _fallbackLatLng = LatLng(22.7196, 75.8577);

class FindingDriverScreen extends ConsumerStatefulWidget {
  const FindingDriverScreen({super.key});

  @override
  ConsumerState<FindingDriverScreen> createState() => _FindingDriverScreenState();
}

class _FindingDriverScreenState extends ConsumerState<FindingDriverScreen>
    with SingleTickerProviderStateMixin {
  /// True while a fare increase is in flight, so the button cannot be
  /// double-tapped into two increments.
  bool _raisingFare = false;

  late final AnimationController _pulseController;
  bool _leaving = false;

  /// Where "Trip Details" scrolls to — the pickup/drop/fare/payment sections
  /// stay in the same panel rather than a separate sheet, so nothing about
  /// how they're populated changes; tapping the pill just brings them into
  /// view instead of the rider hunting for them below the fold.
  final _bookingDetailsKey = GlobalKey();
  final _panelScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkInitialState();
    });
  }

  void _scrollToTripDetails() {
    final context = _bookingDetailsKey.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
    );
  }

  Future<void> _checkInitialState() async {
    final search = ref.read(rideSearchControllerProvider);
    if (search.phase == RideSearchPhase.accepted && search.rideId != null) {
      _handlePhase(search);
      return;
    }
    try {
      final activeRide = await ref.read(rideRepositoryProvider).getMyActiveRide();
      if (activeRide != null && !_leaving && mounted) {
        final s = activeRide.status.toLowerCase();
        if (s == 'accepted' || s == 'arriving' || s == 'started' || s == 'arrived') {
          _leaving = true;
          context.pushReplacement('/ride/tracking/${activeRide.rideId}');
        }
      }
    } catch (_) {}
  }


  @override
  void dispose() {
    _pulseController.dispose();
    _panelScrollController.dispose();
    super.dispose();
  }

  /// The search phase is decided entirely by the server: `rideSearchUpdate`
  /// keeps us here, `rideAccepted` moves to tracking, and `rideCancelled`
  /// (reasonCode `no_drivers`) sends us to the retry screen. There is no
  /// client-side timer — the backend owns the dispatch budget.
  void _handlePhase(RideSearchState next) {
    if (_leaving || !mounted) return;

    switch (next.phase) {
      case RideSearchPhase.accepted:
        final rideId = next.rideId;
        if (rideId == null || rideId.isEmpty) return;
        _leaving = true;
        context.pushReplacement('/ride/tracking/$rideId');
        break;
      case RideSearchPhase.noDrivers:
        _leaving = true;
        context.pushReplacement('/home/no-driver');
        break;
      case RideSearchPhase.failed:
        _leaving = true;
        SnackbarUtils.error(context, next.message ?? 'Could not create your booking');
        context.pushReplacement('/home/no-driver');
        break;
      case RideSearchPhase.cancelled:
        _leaving = true;
        context.go('/home');
        break;
      case RideSearchPhase.idle:
      case RideSearchPhase.creating:
      case RideSearchPhase.searching:
        break;
    }
  }

  /// Bumps the fare and lets dispatch try again at the new price.
  ///
  /// The created ride is refetched rather than patched locally, because the
  /// server also moves `nextFareIncreaseAt`, and a stale copy of that would let
  /// the rider tap straight through the cooling-off period.
  Future<void> _raiseFare(String rideId, int steps) async {
    if (_raisingFare) return;
    setState(() => _raisingFare = true);

    try {
      final ride = await ref.read(rideRepositoryProvider).raiseFare(rideId, steps: steps);
      if (!mounted) return;
      ref.read(bookingControllerProvider.notifier).replaceCreatedRide(ride);
      SnackbarUtils.success(context, 'Fare raised to ₹${ride.fare.toStringAsFixed(0)}');
    } catch (error) {
      if (mounted) SnackbarUtils.error(context, error.toString());
    } finally {
      if (mounted) setState(() => _raisingFare = false);
    }
  }

  Future<void> _cancelSearch() async {
    if (_leaving) return;

    // Asked before claiming the exit: backing out of the sheet has to leave the
    // search running.
    final result = await showCancelReasonSheet(context, hasDriver: false);
    if (result == null || !mounted) return;

    // Claim the exit up front so the phase listener doesn't also navigate when
    // cancelSearch flips the state to `cancelled`.
    _leaving = true;

    final ok = await ref.read(rideSearchControllerProvider.notifier).cancelSearch(
          reasonId: result.reasonId,
          reason: result.title,
          note: result.note,
        );
    if (!mounted) return;
    if (!ok) {
      _leaving = false;
      final detail = ref.read(rideSearchControllerProvider).message;
      SnackbarUtils.error(
        context,
        (detail ?? '').isNotEmpty ? detail! : 'Could not cancel the ride. Please try again.',
      );
      return;
    }
    ref.read(bookingControllerProvider.notifier).reset();
    if (mounted) context.go('/home');
  }

  Widget _radarRing(double t) {
    final size = 40 + t * 140;
    final opacity = (1 - t).clamp(0.0, 1.0) * 0.5;
    return Opacity(
      opacity: opacity,
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle),
      ),
    );
  }

  /// A row of filled/unfilled bars rather than one continuous bar — reads at
  /// a glance as "attempt 2 of 5" the way a continuous fill doesn't. Segment
  /// count and fill both come from the same real dispatch progress as before;
  /// this only changes how it's drawn.
  Widget _segmentedProgress(double? progress, bool isDark) {
    const segments = 5;
    final filled = progress == null
        ? 0
        : (progress * segments).ceil().clamp(0, segments);
    return Row(
      children: [
        for (var i = 0; i < segments; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: Container(
                height: 5,
                color: i < filled
                    ? const Color(0xFF2563EB)
                    : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _detailChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: color),
        ),
      ],
    );
  }

  Widget _addressRow({
    required IconData icon,
    required Color iconColor,
    required double iconSize,
    required String text,
    required bool isDark,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: iconSize, color: iconColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final booking = ref.watch(bookingControllerProvider);
    final search = ref.watch(rideSearchControllerProvider);
    final pickup = booking.pickup;
    final drop = booking.drop;
    final vehicle = booking.selectedVehicle;
    final pickupLatLng = pickup != null ? LatLng(pickup.lat, pickup.lng) : _fallbackLatLng;

    ref.listen(rideSearchControllerProvider, (previous, next) => _handlePhase(next));

    // Progress reflects the server's real dispatch attempts, so the bar can
    // only reach the end when the backend has genuinely run out of drivers.
    final progress = search.maxAttempts > 0
        ? (search.attempt / search.maxAttempts).clamp(0.0, 1.0)
        : null;
    final searchLabel = search.radiusMeters > 0
        ? 'Searching ${(search.radiusMeters / 1000).toStringAsFixed(1)} km around you'
        : 'Contacting nearby drivers…';
    final paymentLabel =
        booking.paymentMethod == 'cash' ? 'Cash' : booking.paymentMethod.toUpperCase();

    // Ride details come from the ride the server actually created wherever it
    // exists - that is the fare and distance the rider will be charged on. The
    // local estimate is only the fallback for the moment between tapping Book
    // and the create call returning.
    final createdRide = booking.createdRide;
    final fareValue = (createdRide != null && createdRide.fare > 0)
        ? createdRide.fare
        : booking.fareBreakdown?.total;
    final distanceKm = (createdRide != null && createdRide.estimatedDistanceMeters > 0)
        ? createdRide.estimatedDistanceMeters / 1000
        : (booking.distanceMeters != null ? booking.distanceMeters! / 1000 : null);
    final durationMinutes = (createdRide != null && createdRide.estimatedDurationMinutes > 0)
        ? createdRide.estimatedDurationMinutes
        : (booking.durationSeconds != null ? booking.durationSeconds! / 60 : null);

    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final cardBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final cardBorder = isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9);

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
                  // rebuilds the map, not this whole screen, as on the ride
                  // type screen.
                  Consumer(
                    builder: (context, ref, _) => GoogleMap(
                      style: AppMapStyle.light,
                      initialCameraPosition: CameraPosition(target: pickupLatLng, zoom: 15),
                      myLocationEnabled: false,
                      myLocationButtonEnabled: false,
                      zoomControlsEnabled: false,
                      scrollGesturesEnabled: false,
                      rotateGesturesEnabled: false,
                      tiltGesturesEnabled: false,
                      // Keep the live fleet visible while searching — the radar
                      // pulse over an empty map reads as "no drivers here".
                      markers: buildNearbyDriverMarkers(
                        ref,
                        onlyVehicleTypeIds: moduleVehicleTypeIds(ref),
                      ),
                    ),
                  ),
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
                              Icon(Icons.location_on, size: 44, color: isDark ? Colors.white : const Color(0xFF334155)),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ==================== BOTTOM DETAILS PANEL ====================
            Expanded(
              flex: 6,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
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
                child: SingleChildScrollView(
                  controller: _panelScrollController,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 14),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF475569) : const Color(0xFFE2E8F0),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              'Looking for your ${vehicle?.name ?? 'ride'}',
                              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: textPrimary),
                            ),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton(
                            onPressed: _scrollToTripDetails,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: textPrimary,
                              side: BorderSide(color: cardBorder),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text(
                              'Trip Details',
                              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _segmentedProgress(progress, isDark),
                      const SizedBox(height: 8),
                      Text(
                        searchLabel,
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: textSecondary),
                      ),
                      if (search.totalNotifiedDrivers > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            '${search.totalNotifiedDrivers} driver(s) notified',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                          ),
                        ),

                      // A ride that came with a raise-fare card leads with it —
                      // it's the one thing the rider can act on while waiting,
                      // so it sits above the address/fare summary rather than
                      // buried under it.
                      if (createdRide != null && createdRide.bidding.isUserIncrement) ...[
                        const SizedBox(height: 16),
                        RaiseFareCard(
                          bidding: createdRide.bidding,
                          currentFare: createdRide.fare,
                          busy: _raisingFare,
                          onRaise: (steps) => _raiseFare(createdRide.rideId, steps),
                        ),
                      ],

                      const SizedBox(height: 20),
                      Text(
                        'Booking Details',
                        key: _bookingDetailsKey,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: textPrimary),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: const BorderRadius.all(Radius.circular(12)),
                          border: Border.fromBorderSide(BorderSide(color: cardBorder)),
                        ),
                        child: Column(
                          children: [
                            _addressRow(
                              icon: Icons.circle,
                              iconColor: const Color(0xFF10B981),
                              iconSize: 12,
                              text: pickup?.address ?? '—',
                              isDark: isDark,
                            ),
                            Divider(height: 1, color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9)),
                            _addressRow(
                              icon: Icons.location_on,
                              iconColor: AppColors.primaryOrange,
                              iconSize: 18,
                              text: drop?.address ?? '—',
                              isDark: isDark,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text('Ride details', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: textPrimary)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: const BorderRadius.all(Radius.circular(12)),
                          border: Border.fromBorderSide(BorderSide(color: cardBorder)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                // Shows the catalog art for the vehicle actually
                                // booked. This used to be a bundled asset only,
                                // and the one it named is not in the bundle, so
                                // the row rendered a red "Asset not found" box.
                                VehicleArt(
                                  source: vehicle?.image.isNotEmpty == true
                                      ? vehicle?.image
                                      : vehicle?.mapIcon,
                                  iconType: vehicle?.iconType,
                                  name: vehicle?.name,
                                  width: 34,
                                  height: 34,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        vehicle?.name ?? 'Ride',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.w700,
                                          color: textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        booking.isOutstation
                                            ? 'Outstation \u00b7 ${booking.tripType.label}'
                                            : booking.tripType.label,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (fareValue != null && fareValue > 0)
                                  Text(
                                    '\u20b9${fareValue.toStringAsFixed(0)}',
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                      color: textPrimary,
                                    ),
                                  ),
                              ],
                            ),
                            if (distanceKm != null || durationMinutes != null) ...[
                              const SizedBox(height: 10),
                              Divider(height: 1, color: cardBorder),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  if (distanceKm != null)
                                    _detailChip(
                                      icon: Icons.route_outlined,
                                      label: '${distanceKm.toStringAsFixed(1)} km',
                                      color: textSecondary,
                                    ),
                                  if (distanceKm != null && durationMinutes != null)
                                    const SizedBox(width: 16),
                                  if (durationMinutes != null)
                                    _detailChip(
                                      icon: Icons.schedule,
                                      label: '${durationMinutes.round()} min',
                                      color: textSecondary,
                                    ),
                                  const Spacer(),
                                  if (createdRide != null && createdRide.otp.isNotEmpty)
                                    _detailChip(
                                      icon: Icons.pin_outlined,
                                      label: 'OTP ${createdRide.otp}',
                                      color: textSecondary,
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text('Payment', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: textPrimary)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: const BorderRadius.all(Radius.circular(12)),
                          border: Border.fromBorderSide(BorderSide(color: cardBorder)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.payments_outlined, size: 20, color: isDark ? const Color(0xFF60A5FA) : const Color(0xFF0F172A)),
                            const SizedBox(width: 10),
                            Text(
                              paymentLabel,
                              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: textPrimary),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),
                      Text('Manage Ride', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: textPrimary)),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isDark ? const Color(0xFF991B1B) : const Color(0xFFEF4444),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                          ),
                          onPressed: _cancelSearch,
                          icon: const Icon(Icons.cancel_outlined),
                          label: const Text(
                            'Cancel Ride',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
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
    );
  }
}

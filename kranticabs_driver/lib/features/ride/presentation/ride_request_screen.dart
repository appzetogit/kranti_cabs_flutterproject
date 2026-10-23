import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/image_utils.dart';
import '../../../core/utils/snackbar_utils.dart';
import '../application/ride_providers.dart';
import 'bid_entry_panel.dart';
import 'parcel_widgets.dart';
import 'toll_widgets.dart';

class RideRequestScreen extends ConsumerStatefulWidget {
  const RideRequestScreen({super.key});

  @override
  ConsumerState<RideRequestScreen> createState() => _RideRequestScreenState();
}

class _RideRequestScreenState extends ConsumerState<RideRequestScreen> {
  Timer? _timer;
  int _secondsLeft = 25;
  int _totalSeconds = 25;
  bool _responding = false;

  @override
  void initState() {
    super.initState();
    final request = ref.read(rideProvider).incomingRequest;
    _secondsLeft = request?.expiresInSeconds ?? 25;
    _totalSeconds = _secondsLeft > 0 ? _secondsLeft : 25;

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft <= 1) {
        timer.cancel();
        _reject();
      } else {
        setState(() => _secondsLeft -= 1);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// True once the server confirmed the bid, which changes what leaving this
  /// screen means.
  bool get _bidSubmitted => ref.read(rideProvider).submittedBidFare != null;

  /// Leaves the offer on screen no more, but keeps the bid standing.
  void _dismissAfterBid() {
    ref.read(rideProvider.notifier).clearIncoming();
    if (mounted && context.canPop()) context.pop();
  }

  void _submitBid(num bidFare) {
    if (_responding) return;
    setState(() => _responding = true);
    _timer?.cancel();
    ref.read(rideProvider.notifier).submitBid(bidFare);
  }

  void _accept() {
    if (_responding) return;
    setState(() => _responding = true);
    _timer?.cancel();
    ref.read(rideProvider.notifier).acceptIncoming();
  }

  void _reject() {
    if (_responding) return;
    ref.read(rideProvider.notifier).rejectIncoming();
    if (mounted && context.canPop()) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final request = ref.watch(rideProvider).incomingRequest;

    ref.listen(rideProvider, (previous, next) {
      final error = next.acceptError;
      if (error != null && previous?.acceptError != error) {
        SnackbarUtils.info(error);
        ref.read(rideProvider.notifier).clearAcceptError();
      }

      final isStillVisible = ModalRoute.of(context)?.isCurrent ?? false;
      if (next.incomingRequest == null && isStillVisible && context.canPop()) {
        context.pop();
        return;
      }

      // An accept that ended without closing the offer (accept limit hit, or
      // no answer and the ride is not ours) lets the driver tap Accept once
      // more by hand. Nothing is retried automatically.
      if ((previous?.busy ?? false) && !next.busy && next.incomingRequest != null && _responding) {
        setState(() => _responding = false);
      }
    });

    if (request == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF11191D),
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    final km = (request.estimatedDistanceMeters / 1000).toStringAsFixed(1);
    final pickupKm = request.pickupDistanceMeters != null
        ? (request.pickupDistanceMeters! / 1000).toStringAsFixed(1)
        : null;
    final durationMins = request.estimatedDurationMinutes > 0
        ? request.estimatedDurationMinutes.toInt()
        : (request.estimatedDistanceMeters / 500).clamp(1, 60).toInt();
    final timerProgress = (_secondsLeft / _totalSeconds).clamp(0.0, 1.0);

    final isParcel =
        request.parcel.isNotEmpty || request.serviceType == 'parcel';
    final rental = request.rental;
    final titleText = rental != null
        ? 'New hourly rental request'
        : isParcel
        ? 'New Parcel Request'
        : (request.isOutstation ? 'Outstation Request' : 'New Ride Request');
    final badgeText = rental != null
        ? 'RENTAL'
        : isParcel
        ? 'PARCEL'
        : (request.isOutstation ? 'OUTSTATION' : 'PASSENGER');

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF11191D),
        body: Stack(
          children: [
            // 1. Sleek Cyberpunk Dark Map Canvas Background
            const Positioned.fill(child: _DarkMapBackground()),

            // 2. Main Content Overlay
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                child: Column(
                  children: [
                    // Request Details Container Box
                    Expanded(
                      child: SingleChildScrollView(
                       // physics: const BouncingScrollPhysics(),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: const Color(0xFF222222),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: const Color(0xFF2E2E2E),
                              width: 1.5,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black54,
                                blurRadius: 20,
                                offset: Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Title & Service Badge Header
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          titleText,
                                          style: const TextStyle(
                                            fontSize: 19,
                                            fontWeight: FontWeight.w900,
                                            color: Colors.white,
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                        // The specific vehicle class this
                                        // request is for (e.g. "Kranti Mini
                                        // Truck") — the badge only says
                                        // ride vs. parcel vs. outstation, not
                                        // which of the driver's registered
                                        // vehicle types it's asking for.
                                        if (request.vehicleLabel.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 2,
                                            ),
                                            child: Text(
                                              request.vehicleLabel,
                                              style: const TextStyle(
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF94A3B8),
                                              ),
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
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: AppColors.primary.withValues(
                                          alpha: 0.4,
                                        ),
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          isParcel
                                              ? Icons.inventory_2_rounded
                                              : Icons
                                                    .directions_car_filled_rounded,
                                          size: 13,
                                          color: AppColors.primary,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          badgeText,
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w900,
                                            color: AppColors.primary,
                                            letterSpacing: 0.8,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),

                              // Rider Profile Line
                              if (request.riderName.isNotEmpty) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF11191D),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: const Color(0xFF2E2E2E),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 32,
                                        height: 32,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF2E2E2E),
                                          shape: BoxShape.circle,
                                          image: buildSafeDecorationImage(
                                            resolveMediaUrl(request.riderImage),
                                          ),
                                        ),
                                        child: buildSafeImageProvider(
                                                  resolveMediaUrl(request.riderImage),
                                                ) ==
                                                null
                                            ? const Icon(
                                                Icons.person_rounded,
                                                color: Colors.white,
                                                size: 18,
                                              )
                                            : null,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          request.riderName.toUpperCase(),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 13.5,
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                      ),
                                      // No rating here: offers don't carry
                                      // one, and this used to show a fixed
                                      // 4.8 for every rider.
                                      const SizedBox(width: 10),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF2E2E2E),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: Text(
                                          request.paymentMethod.toUpperCase(),
                                          style: const TextStyle(
                                            color: AppColors.primary,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 14),
                              ],

                              const Divider(
                                color: Color(0xFF2E2E2E),
                                height: 1,
                              ),
                              const SizedBox(height: 16),

                              // Route Summary (Pickup & Drop Locations)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Column(
                                    children: [
                                      const SizedBox(height: 4),
                                      Container(
                                        width: 12,
                                        height: 12,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: AppColors.primary,
                                          boxShadow: [
                                            BoxShadow(
                                              color: AppColors.primary
                                                  .withValues(alpha: 0.5),
                                              blurRadius: 6,
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        width: 2,
                                        height: 44,
                                        decoration: const BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                              AppColors.primary,
                                              Color(0xFFFF4D6D),
                                            ],
                                          ),
                                        ),
                                      ),
                                      Container(
                                        width: 12,
                                        height: 12,
                                        decoration: const BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Color(0xFFFF4D6D),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'PICKUP LOCATION',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: AppColors.primary,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 0.8,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          // Never a sample address: a driver
                                          // decides whether to accept on this.
                                          request.pickupAddress.isNotEmpty
                                              ? request.pickupAddress
                                              : 'Pickup address not shared',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.white,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        if (rental != null) ...[
                                          const SizedBox(height: 16),
                                          Text(
                                            '${rental.packageName} · extra ₹${rental.extraKmRate}/km · ₹${rental.extraMinuteRate}/min',
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w800,
                                              color: AppColors.primary,
                                            ),
                                          ),
                                        ] else ...[
                                        const SizedBox(height: 16),
                                        const Text(
                                          'DROP LOCATION',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Color(0xFFFF4D6D),
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 0.8,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          request.dropAddress.isNotEmpty
                                              ? request.dropAddress
                                              : 'Drop address not shared',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.white,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),

                              // Metrics Bar: pickup distance, trip distance,
                              // est. time and fare, as a 2x2 grid — a single
                              // row of 4 got too cramped once pickup distance
                              // joined the original 3.
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF11191D),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: const Color(0xFF2E2E2E),
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _MetricCell(
                                            label: 'PICKUP',
                                            // Not yet known (older server
                                            // build, or the driver's location
                                            // wasn't available at dispatch
                                            // time) reads as a dash, never a
                                            // guessed distance.
                                            value: pickupKm != null
                                                ? '$pickupKm km'
                                                : '—',
                                          ),
                                        ),
                                        Container(
                                          width: 1,
                                          height: 32,
                                          color: const Color(0xFF2E2E2E),
                                        ),
                                        Expanded(
                                          child: Padding(
                                            padding: const EdgeInsets.only(
                                              left: 14,
                                            ),
                                            child: _MetricCell(
                                              label: rental != null ? 'PACKAGE' : 'TRIP DISTANCE',
                                              value: rental != null ? rental.includedLabel : '$km km',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 14),
                                    Container(
                                      height: 1,
                                      color: const Color(0xFF2E2E2E),
                                    ),
                                    const SizedBox(height: 14),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _MetricCell(
                                            label: 'EST. TIME',
                                            value: '$durationMins mins',
                                          ),
                                        ),
                                        Container(
                                          width: 1,
                                          height: 32,
                                          color: const Color(0xFF2E2E2E),
                                        ),
                                        Expanded(
                                          child: Padding(
                                            padding: const EdgeInsets.only(
                                              left: 14,
                                            ),
                                            child: _MetricCell(
                                              label: 'FARE',
                                              value:
                                                  '₹${request.fare.toStringAsFixed(0)}',
                                              valueColor: AppColors.primary,
                                              valueFontSize: 17,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                              // Outstation tolls inside the fare above.
                              if (request.tollCharges.hasTolls) ...[
                                const SizedBox(height: 10),
                                TollChargesNote(
                                  tolls: request.tollCharges,
                                  dark: true,
                                  compact: true,
                                ),
                              ],

                              // Parcel Details Card (If parcel request)
                              if (request.parcel.isNotEmpty) ...[
                                const SizedBox(height: 14),
                                ParcelDetailsCard(
                                  parcel: request.parcel,
                                  dark: true,
                                  compact: true,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Floating Circular Countdown Timer
                    Center(
                      child: Container(
                        width: 76,
                        height: 76,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFF11191D),
                          boxShadow: [
                            BoxShadow(color: Colors.black54, blurRadius: 12),
                          ],
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              width: 76,
                              height: 76,
                              child: CircularProgressIndicator(
                                value: timerProgress,
                                strokeWidth: 4.5,
                                backgroundColor: const Color(0xFF2E2E2E),
                                color: AppColors.primary,
                              ),
                            ),
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  '$_secondsLeft',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                    height: 1.0,
                                  ),
                                ),
                                const Text(
                                  'sec',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: Color(0xFF94A3B8),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // A bidding ride cannot be accepted outright - the
                    // server refuses it and the rider picks from the bids - so
                    // the panel replaces this button rather than joining it.
                    if (request.biddingEnabled)
                      BidEntryPanel(
                        baseFare: request.fare,
                        floorFare: request.bidFloorFare,
                        ceilingFare: request.bidCeilingFare,
                        stepAmount: request.bidStepAmount,
                        submittedFare: ref.watch(rideProvider).submittedBidFare,
                        busy: _responding,
                        onSubmit: _submitBid,
                      )
                    else
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: const Color(0xFF11191D),
                            elevation: 4,
                            shadowColor: AppColors.primary.withValues(
                              alpha: 0.4,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28),
                            ),
                          ),
                          onPressed: _responding ? null : _accept,
                          child: _responding
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    color: Color(0xFF11191D),
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : const Text(
                                  'Accept Request',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                        ),
                      ),
                    const SizedBox(height: 10),

                    // A submitted bid stays in the running while the rider
                    // decides, so leaving must not send a rejection — that
                    // would withdraw the driver from the ride they just bid on.
                    Center(
                      child: TextButton(
                        onPressed: _bidSubmitted
                            ? _dismissAfterBid
                            : (_responding ? null : _reject),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 8,
                          ),
                        ),
                        child: Text(
                          _bidSubmitted ? 'Keep driving' : 'Reject Request',
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
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

class _MetricCell extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  final double valueFontSize;

  const _MetricCell({
    required this.label,
    required this.value,
    this.valueColor = Colors.white,
    this.valueFontSize = 16,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: Color(0xFF94A3B8),
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            fontSize: valueFontSize,
            fontWeight: FontWeight.w900,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

class _DarkMapBackground extends StatelessWidget {
  const _DarkMapBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF11191D),
      child: CustomPaint(
        painter: _DarkMapPainter(),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _DarkMapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final roadPaint = Paint()
      ..color = const Color(0xFF142538)
      ..strokeWidth = 14.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final minorRoadPaint = Paint()
      ..color = const Color(0xFF1B324B)
      ..strokeWidth = 6.0
      ..style = PaintingStyle.stroke;

    final routeGlowPaint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.15)
      ..strokeWidth = 8.0
      ..style = PaintingStyle.stroke;

    final path1 = Path()
      ..moveTo(0, size.height * 0.25)
      ..cubicTo(
        size.width * 0.4,
        size.height * 0.2,
        size.width * 0.6,
        size.height * 0.4,
        size.width,
        size.height * 0.35,
      );

    final path2 = Path()
      ..moveTo(size.width * 0.3, 0)
      ..lineTo(size.width * 0.7, size.height);

    final path3 = Path()
      ..moveTo(0, size.height * 0.7)
      ..cubicTo(
        size.width * 0.3,
        size.height * 0.75,
        size.width * 0.7,
        size.height * 0.65,
        size.width,
        size.height * 0.8,
      );

    canvas.drawPath(path1, roadPaint);
    canvas.drawPath(path2, roadPaint);
    canvas.drawPath(path3, roadPaint);

    canvas.drawPath(path1, minorRoadPaint);
    canvas.drawPath(path2, minorRoadPaint);
    canvas.drawPath(path3, minorRoadPaint);

    canvas.drawPath(path1, routeGlowPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

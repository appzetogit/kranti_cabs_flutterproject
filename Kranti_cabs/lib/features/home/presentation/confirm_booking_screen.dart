import '../../../core/constants/app_constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/custom_bottom_sheet.dart';
import '../application/booking_controller.dart';

class ConfirmBookingScreen extends ConsumerWidget {
  const ConfirmBookingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final booking = ref.watch(bookingControllerProvider);
    final controller = ref.read(bookingControllerProvider.notifier);
    final fare = booking.fareBreakdown;
    final blocker = controller.bookingBlocker;
    const bgColor = Color(0xFF11191D);
    const cardBgColor = Color(0xFF222222);
    const borderColor = Color(0xFF2E2E2E);
    const tealColor = Color(0xFFF5B400);
    const textSecondary = Color(0xFF94A3B8);

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          children: [
            // --- TOP APP BAR ---
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 24),
                    onPressed: () => context.pop(),
                  ),
                  const SizedBox(width: 16),
                  const Text(
                    'Confirm Your Ride',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                children: [
                  // --- 1. PICKUP & DROP ROUTE CARD ---
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cardBgColor,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: borderColor),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: const BoxDecoration(
                                color: tealColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Pickup Location',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFFB0BEC5),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    booking.pickup?.address ?? 'Pickup not set',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const Padding(
                          padding: EdgeInsets.only(left: 4, top: 4, bottom: 4),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: SizedBox(
                              height: 16,
                              child: VerticalDivider(color: Color(0xFF334155), thickness: 1.5),
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: const BoxDecoration(
                                color: Color(0xFFEF4444),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Drop Location',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFFB0BEC5),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    booking.drop?.address ?? 'MG Road, Bengaluru',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // --- 2. SELECTED RIDE SUB-CARD ---
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cardBgColor,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: borderColor),
                    ),
                    child: Row(
                      children: [
                        Image.asset(
                          'assets/Ridenow.webp',
                          width: 54,
                          height: 40,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, _) => const Icon(
                            Icons.directions_car_rounded,
                            size: 36,
                            color: tealColor,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                booking.selectedVehicle?.name ?? 'Sedan',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${booking.selectedVehicle?.capacity ?? 4} Seater • Comfortable',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // --- 3. FARE DETAILS CARD ---
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cardBgColor,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: borderColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Fare Details',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 12),
                        // No invented figures: these used to fall back to Rs 220, Rs 30
                        // and a Rs 250 total, over a made-up 12.6 km, whenever there was
                        // no fare - so a ride with no price was shown as costing Rs 250.
                        _FareRow(label: 'Base Fare', value: fare == null ? '--' : '₹${fare.baseFare.round()}'),
                        const SizedBox(height: 8),
                        _FareRow(
                          label: booking.distanceMeters == null
                              ? 'Distance'
                              : 'Distance (${Formatters.distanceKm(booking.distanceMeters!)})',
                          value: fare == null ? '--' : '₹${fare.distanceFare.round()}',
                        ),
                        if (fare != null && fare.airportFee > 0) ...[
                          const SizedBox(height: 8),
                          _FareRow(label: 'Airport fee', value: _rupees(fare.airportFee)),
                        ],
                        // Station entry fee and state / MCD tax, in the total.
                        if (fare != null)
                          for (final line in fare.locationCharges) ...[
                            const SizedBox(height: 8),
                            _FareRow(label: line.label, value: _rupees(line.amount)),
                          ],
                        // Outstation round trip: the driver's daily allowance.
                        if (fare != null && fare.driverAllowance > 0) ...[
                          const SizedBox(height: 8),
                          _FareRow(
                            label: 'Driver allowance (${fare.tripDays} ${fare.tripDays == 1 ? 'day' : 'days'})',
                            value: _rupees(fare.driverAllowance),
                          ),
                        ],
                        if (fare != null && fare.platformFee > 0) ...[
                          const SizedBox(height: 8),
                          _FareRow(label: 'Platform fee (incl. GST)', value: _rupees(fare.platformFee)),
                        ],
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 10),
                          child: Divider(height: 1, color: borderColor),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Total Fare',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              fare == null ? '--' : _rupees(fare.total),
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        // Parking is not in the total: the server adds it when
                        // the trip ends, from how long the driver waited.
                        if (fare != null && fare.parkingFrom > 0) ...[
                          const SizedBox(height: 10),
                          Text(
                            'Plus station / airport parking${fare.parkingVaries ? ' from' : ''} '
                            '${_rupees(fare.parkingFrom)}, added at the end of the trip from how '
                            'long the driver waits there.',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // --- 4. PAYMENT METHOD DROPDOWN CARD ---
                  InkWell(
                    onTap: () => _showPaymentSheet(context, controller, booking.paymentMethod),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: cardBgColor,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: borderColor),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.payments_outlined, color: tealColor, size: 20),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Payment Method',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFFB0BEC5),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                booking.paymentMethod == 'cash' ? 'Cash' : booking.paymentMethod.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          const Icon(Icons.keyboard_arrow_down_rounded, color: textSecondary, size: 22),
                        ],
                      ),
                    ),
                  ),

                  // Why Book is disabled when it is, otherwise the last error.
                  if ((blocker ?? booking.error) != null) ...[
                    const SizedBox(height: 12),
                    Text(blocker ?? booking.error!, style: const TextStyle(color: AppColors.error)),
                  ],
                ],
              ),
            ),

            // --- 5. BOTTOM CONFIRM & BOOK TEAL BUTTON ---
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: tealColor,
                        foregroundColor: const Color(0xFF0A0A0A),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: booking.isSubmitting || blocker != null
                          ? null
                          : () async {
                              var attempt = await controller.confirmBooking();
                              if (attempt == BookingAttempt.kycRequired && context.mounted) {
                                final needsReview = ref.read(bookingControllerProvider).error?.toLowerCase().contains('review') ?? false;
                                if (!needsReview && await context.push<bool>('/profile/verify-identity', extra: true) == true) {
                                  attempt = await controller.confirmBooking();
                                }
                              }

                              if (!context.mounted) return;
                              switch (attempt) {
                                case BookingAttempt.booked:
                                  context.pushReplacement('/home/finding-driver');
                                case BookingAttempt.failed:
                                  context.pushReplacement('/home/no-driver');
                                case BookingAttempt.notReady:
                                case BookingAttempt.kycRequired:
                                  // Nothing was sent; the reason is on screen.
                                  break;
                              }
                            },
                      child: booking.isSubmitting
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF0A0A0A)),
                            )
                          : const Text(
                              'Confirm & Book',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'You can cancel up to 2 mins of booking',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPaymentSheet(BuildContext context, BookingController controller, String current) {
    CustomBottomSheet.show(
      context,
      title: 'Payment Method',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RadioListTile<String>(
            value: 'cash',
            groupValue: current,
            title: const Text('Cash'),
            secondary: const Icon(Icons.money_rounded, color: Color(0xFF10B981)),
            onChanged: (v) {
              controller.setPaymentMethod(v!);
              Navigator.of(context).pop();
            },
          ),
          if (AppConstants.onlinePaymentsEnabled)
          RadioListTile<String>(
            value: 'razorpay',
            groupValue: current,
            title: const Text('Card / UPI'),
            secondary: const Icon(Icons.credit_card_rounded, color: Color(0xFF2563EB)),
            onChanged: (v) {
              controller.setPaymentMethod(v!);
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }
}

class _FareRow extends StatelessWidget {
  final String label;
  final String value;
  const _FareRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF94A3B8),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}

/// Whole rupees when there are no paise, otherwise two decimals - a Rs 6.30 fee
/// must not show a total that is 30 paise off what the rider pays.
String _rupees(double value) => value == value.roundToDouble()
    ? '₹${value.round()}'
    : '₹${value.toStringAsFixed(2)}';

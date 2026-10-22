import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/services/review_service.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/snackbar_utils.dart';
import '../application/ride_providers.dart';
import '../data/ride_model.dart';
import 'parcel_widgets.dart';
import 'toll_widgets.dart';

class TripCompleteScreen extends ConsumerStatefulWidget {
  final RideModel? ride;

  const TripCompleteScreen({super.key, this.ride});

  @override
  ConsumerState<TripCompleteScreen> createState() => _TripCompleteScreenState();
}

class _TripCompleteScreenState extends ConsumerState<TripCompleteScreen> {
  int _rating = 5;
  final _commentController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  /// The trip this screen is about, or null when it was opened without one
  /// (a deep link, or a restart after the trip was cleared). This used to
  /// return a sample trip, so the driver saw a made-up rider and a ₹123 fare.
  RideModel? _resolveRide() {
    if (widget.ride != null) return widget.ride!;
    return ref.watch(rideProvider).activeRide;
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    final ride = _resolveRide();

    if (ride != null && ride.id.isNotEmpty) {
      await ref.read(rideRepositoryProvider).submitReview(
            ride.id,
            rating: _rating,
            comment: _commentController.text.trim().isEmpty ? null : _commentController.text.trim(),
          );
    }

    if (mounted) {
      setState(() => _submitting = false);
      SnackbarUtils.success('Thank you for rating the rider!');
      ref.read(rideProvider.notifier).completeTripLocally();
      await ReviewService.requestReviewIfEligible(rating: _rating);
      if (mounted) context.go('/home');
    }
  }

  void _shareReceipt(RideModel ride, double earnings) {
    final completedDate = ride.completedAt ?? DateTime.now();
    final dateStr = Formatters.date(completedDate);
    final fareStr = earnings.toStringAsFixed(2);
    final text =
        'Trip Receipt\nDate: $dateStr\nRider: ${ride.riderName}\nEarnings: ₹$fareStr\nThank you for driving with KrantiCabs!';
    Share.share(text);
  }

  String _getRatingFeedbackText(int rating) {
    switch (rating) {
      case 1:
        return 'Poor';
      case 2:
        return 'Okay';
      case 3:
        return 'Good';
      case 4:
        return 'Very Good';
      case 5:
        return 'Excellent';
      default:
        return 'Excellent';
    }
  }

  IconData _getVehicleIcon(String? type) {
    final t = (type ?? '').toLowerCase();
    if (t.contains('bike') || t.contains('moto') || t.contains('scooter')) {
      return Icons.two_wheeler_rounded;
    } else if (t.contains('auto') || t.contains('rickshaw')) {
      return Icons.electric_rickshaw_rounded;
    }
    return Icons.directions_car_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final ride = _resolveRide();
    if (ride == null) return const _TripUnavailable();

    // Every fallback says what is missing rather than inventing a value.
    final completedDate = ride.completedAt ?? DateTime.now();
    final pickup = ride.pickupAddress.isNotEmpty ? ride.pickupAddress : 'Pickup location not recorded';
    final drop = ride.dropAddress.isNotEmpty ? ride.dropAddress : 'Drop location not recorded';
    final riderName = ride.riderName.isNotEmpty ? ride.riderName : 'Passenger';
    final riderPhone = ride.riderPhone;
    final riderRating = ride.riderRating > 0 ? ride.riderRating.toStringAsFixed(1) : 'New';
    final baseFare = ride.fare.toDouble();
    final driverEarnings = ride.driverEarnings > 0 ? ride.driverEarnings.toDouble() : baseFare;
    final paymentMethod = ride.paymentMethod.isNotEmpty ? ride.paymentMethod : 'Cash';
    final vehicleIcon = _getVehicleIcon(ride.serviceType ?? ride.vehicleType);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            children: [
              // --- TOP CHECKMARK HEADER ---
              const SizedBox(height: 12),
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x3310B981),
                            blurRadius: 16,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 38,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'You have arrived!',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Great job on completing the trip! 👋',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // --- CARD 1: TRIP RECEIPT ---
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 10,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Row with Date & Share
                    Row(
                      children: [
                        const Icon(
                          Icons.calendar_today_outlined,
                          size: 20,
                          color: Color(0xFFF97316),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Trip Receipt',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${Formatters.date(completedDate)} • ${Formatters.time(completedDate)}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        InkWell(
                          onTap: () => _shareReceipt(ride, driverEarnings),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.share_outlined, size: 14, color: Color(0xFF0F172A)),
                                SizedBox(width: 5),
                                Text(
                                  'Share',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Rider Info Box (Avatar, Rider Name, Phone, Rating, Vehicle graphic)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              shape: BoxShape.circle,
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: (ride.riderProfileImage != null && ride.riderProfileImage!.isNotEmpty)
                                ? ClipOval(
                                    child: CachedNetworkImage(
                                      imageUrl: ride.riderProfileImage!,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                : const Icon(Icons.person, color: Color(0xFF0F172A), size: 26),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  riderName,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  riderPhone.isNotEmpty ? riderPhone : 'Passenger',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Row(
                                  children: [
                                    const Icon(Icons.star_rounded, size: 14, color: Color(0xFFFFB800)),
                                    const SizedBox(width: 3),
                                    Text(
                                      riderRating,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            vehicleIcon,
                            size: 42,
                            color: const Color(0xFF0F172A),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Pickup & Drop Timeline Sub-box
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF10B981),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  pickup,
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF0F172A),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDCFCE7),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'PICKUP',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF15803D),
                                    letterSpacing: 0.5,
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
                                  color: Color(0xFFCBD5E1),
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
                                  color: Color(0xFFF97316),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  drop,
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF0F172A),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFEDD5),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'DROP',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFFC2410C),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (ride.isParcel || ride.parcel.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      ParcelDetailsCard(parcel: ride.parcel, dark: false),
                    ],
                    const SizedBox(height: 16),

                    // Fare & Earnings breakdown rows
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Trip fare',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        Text(
                          '₹${baseFare.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                    if (ride.tollCharges.hasTolls) ...[
                      const SizedBox(height: 6),
                      TollChargesNote(tolls: ride.tollCharges, dark: false),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Payment method',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        Text(
                          paymentMethod.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Divider(color: Color(0xFFE2E8F0), thickness: 1),
                    ),

                    // Total Earnings Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total Earnings',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        Text(
                          '₹${driverEarnings.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF10B981),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // --- CARD 2: RATING CARD (RATE THE PASSENGER) ---
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 10,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Text(
                      'How was your trip with $riderName?',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 5 Star rating buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (index) {
                        final starIndex = index + 1;
                        final isFilled = _rating >= starIndex;
                        return InkWell(
                          onTap: () => setState(() => _rating = starIndex),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Icon(
                              isFilled ? Icons.star_rounded : Icons.star_border_rounded,
                              size: 40,
                              color: isFilled ? const Color(0xFFF97316) : const Color(0xFFCBD5E1),
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _getRatingFeedbackText(_rating),
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _commentController,
                      decoration: InputDecoration(
                        hintText: 'Add a comment for the rider (optional)',
                        hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFF97316)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // --- BOTTOM PRIMARY BUTTON: DONE ---
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF97316),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text(
                          'Done',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown when the screen has no trip to describe, instead of a made-up one.
class _TripUnavailable extends StatelessWidget {
  const _TripUnavailable();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.receipt_long_outlined, size: 48, color: Color(0xFF94A3B8)),
                const SizedBox(height: 12),
                const Text(
                  'This trip is no longer open',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Its receipt is in Ride history.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13.5, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () => context.go('/home'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF97316),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Back to home',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
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

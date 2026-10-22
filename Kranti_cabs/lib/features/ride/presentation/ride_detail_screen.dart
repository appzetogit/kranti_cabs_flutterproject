import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/image_utils.dart';
import '../../../shared/widgets/loading_widget.dart';
import '../application/ride_providers.dart';
import '../data/models/ride_model.dart';
import 'widgets/parcel_proof_strip.dart';

final _rideDetailProvider = FutureProvider.autoDispose.family<RideModel, String>((ref, rideId) {
  return ref.watch(rideRepositoryProvider).getRideById(rideId);
});

class RideDetailScreen extends ConsumerWidget {
  final String rideId;
  const RideDetailScreen({super.key, required this.rideId});

  Widget _buildStatusTag(RideModel ride, bool isDark) {
    final status = (ride.status.isNotEmpty ? ride.status : 'completed').toLowerCase();
    final isScheduled = ride.scheduledAt != null && ride.scheduledAt!.isAfter(DateTime.now());

    String label = status.toUpperCase();
    IconData icon = Icons.info_outline_rounded;
    Color bg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9);
    Color textColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    if (isScheduled || status == 'scheduled') {
      label = 'SCHEDULED';
      icon = Icons.access_time_rounded;
      bg = isDark ? const Color(0xFF0C4A6E) : const Color(0xFFE0F2FE);
      textColor = isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7);
    } else if (status == 'completed') {
      label = 'COMPLETED';
      icon = Icons.check_circle_rounded;
      bg = isDark ? const Color(0xFF064E3B) : const Color(0xFFDCFCE7);
      textColor = isDark ? const Color(0xFF4ADE80) : const Color(0xFF15803D);
    } else if (status == 'cancelled' || status == 'canceled') {
      label = 'CANCELLED';
      icon = Icons.cancel_rounded;
      bg = isDark ? const Color(0xFF4C0519) : const Color(0xFFFFEBEB);
      textColor = isDark ? const Color(0xFFF87171) : const Color(0xFFFF3B30);
    } else if (status == 'ongoing' || status == 'accepted' || status == 'arrived') {
      label = status.toUpperCase();
      icon = Icons.directions_car_rounded;
      bg = isDark ? const Color(0xFF1E3A8A) : const Color(0xFFEFF6FF);
      textColor = isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB);
    } else if (status == 'searching') {
      label = 'SEARCHING';
      icon = Icons.search_rounded;
      bg = isDark ? const Color(0xFF451A03) : const Color(0xFFFEF3C7);
      textColor = isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: textColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rideAsync = ref.watch(_rideDetailProvider(rideId));

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppColors.darkBackground : AppColors.lightBackground;
    final cardBgColor = isDark ? AppColors.darkCard : Colors.white;
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final dividerColor = isDark ? AppColors.darkBorder : const Color(0xFFF1F5F9);
    final iconBoxBg = isDark ? AppColors.darkSurface : const Color(0xFFF8FAFC);
    final highlightBg = isDark ? const Color(0xFF2A1B14) : const Color(0xFFFFF7ED);
    final statusBg = isDark ? const Color(0xFF064E3B) : const Color(0xFFDCFCE7);
    final statusText = isDark ? const Color(0xFF4ADE80) : const Color(0xFF15803D);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: cardBgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Ride Details',
          style: TextStyle(
            color: textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: rideAsync.when(
              data: (ride) => _buildStatusTag(ride, isDark),
              loading: () => const SizedBox.shrink(),
              error: (err, stack) => const SizedBox.shrink(),
            ),
          ),
        ],
      ),
      body: rideAsync.when(
        data: (ride) {
          final completedDate = ride.completedAt ?? ride.acceptedAt ?? DateTime.now();
          final pickup = ride.pickupAddress.isNotEmpty ? ride.pickupAddress : 'Unknown location';
          final drop = ride.dropAddress.isNotEmpty
              ? ride.dropAddress
              : 'Unknown location';
          final distanceKm = (ride.estimatedDistanceMeters > 0)
              ? (ride.estimatedDistanceMeters / 1000).toStringAsFixed(1)
              : '0.0';
          final durationMin = (ride.estimatedDurationMinutes > 0)
              ? ride.estimatedDurationMinutes.toInt()
              : 0;
          final baseFare = ride.baseFare > 0 ? ride.baseFare : ride.fare;
          final totalFare = ride.fare;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- DRIVER DETAILS CARD ---
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cardBgColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: borderColor),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: highlightBg,
                        backgroundImage: buildSafeImageProvider(ride.driver?.profileImage),
                        child: buildSafeImageProvider(ride.driver?.profileImage) == null
                            ? const Icon(Icons.person_rounded, color: AppColors.primaryOrange, size: 26)
                            : null,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ride.driver?.name.isNotEmpty == true
                                  ? ride.driver!.name
                                  : 'Captain Assigned',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                color: textPrimary,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                const Icon(Icons.star_rounded, size: 15, color: Color(0xFFF59E0B)),
                                const SizedBox(width: 3),
                                Text(
                                  (ride.driver?.rating ?? 4.8).toStringAsFixed(1),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: textPrimary,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '• ${ride.vehicleType ?? 'Taxi'}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // --- TRIP ADDRESS & METRICS CARD ---
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: cardBgColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: borderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${Formatters.date(completedDate)} • ${Formatters.time(completedDate)}',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: textSecondary,
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Pickup & Drop
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
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              pickup,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: SizedBox(
                            height: 14,
                            child: VerticalDivider(
                              color: dividerColor,
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
                              color: AppColors.primaryOrange,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              drop,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Divider(color: dividerColor, thickness: 1),
                      const SizedBox(height: 12),

                      // Metrics (Distance & Duration)
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: iconBoxBg,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(Icons.directions_car_outlined,
                                      size: 20, color: textSecondary),
                                ),
                                const SizedBox(width: 10),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '$distanceKm km',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w900,
                                        color: textPrimary,
                                      ),
                                    ),
                                    Text(
                                      'Distance',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: iconBoxBg,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.access_time_rounded,
                                      size: 20, color: AppColors.primaryOrange),
                                ),
                                const SizedBox(width: 10),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '$durationMin min',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w900,
                                        color: textPrimary,
                                      ),
                                    ),
                                    Text(
                                      'Duration',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // --- PARCEL PROOF SECTION ---
                // The record is where a dispute gets settled, so the photos
                // outlive the trip rather than vanishing with the tracking
                // screen. Sender's own photos sit alongside the captain's,
                // because comparing them is the entire point.
                if (ride.isParcel) ...[
                  Text(
                    'Parcel Photos',
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ParcelProofStrip(
                    pickup: ride.parcel.pickupProof,
                    delivery: ride.parcel.deliveryProof,
                    senderPhotos: ride.parcel.photos,
                  ),
                  const SizedBox(height: 20),
                ],

                // --- FARE BREAKDOWN SECTION ---
                Text(
                  'Fare Breakdown',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: cardBgColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: borderColor),
                  ),
                  child: Column(
                    children: [
                      // Total Fare Peach Box
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: highlightBg,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Total Fare',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: textPrimary,
                              ),
                            ),
                            Text(
                              '₹${totalFare.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                color: AppColors.primaryOrange,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Base fare',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textSecondary),
                          ),
                          Text(
                            '₹${baseFare.toStringAsFixed(2)}',
                            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: textPrimary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Tip',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textSecondary),
                          ),
                          Text(
                            '₹0.00',
                            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: textPrimary),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Divider(color: dividerColor, thickness: 1),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Paid Amount',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: textPrimary),
                          ),
                          Text(
                            '₹${totalFare.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF10B981),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // --- PAYMENT METHOD SECTION ---
                Text(
                  'Payment Method',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: cardBgColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: borderColor),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: isDark ? borderColor : textPrimary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'C',
                          style: TextStyle(
                            color: isDark ? textPrimary : cardBgColor,
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Cash',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: textPrimary,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusBg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Paid',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: statusText,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // --- NEED HELP CARD ---
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
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: highlightBg,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.headset_mic_outlined,
                              size: 22,
                              color: AppColors.primaryOrange,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Need help?',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                    color: textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Get help with this trip',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: textSecondary,
                            size: 22,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      InkWell(
                        onTap: () => context.push('/support'),
                        child: const Text(
                          'Contact Support',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w900,
                            color: AppColors.primaryOrange,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const LoadingWidget(message: 'Loading ride details…'),
        error: (err, stack) => const Center(child: Text('Could not load ride details')),
      ),
    );
  }
}

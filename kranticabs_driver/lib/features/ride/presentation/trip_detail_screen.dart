import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../data/ride_history_item.dart';
import 'parcel_widgets.dart';

class TripDetailScreen extends StatelessWidget {
  final RideHistoryItem ride;

  const TripDetailScreen({super.key, required this.ride});

  Color get _statusColor {
    if (ride.isCompleted) return AppColors.primary;
    if (ride.isCancelled) return const Color(0xFFEF4444);
    return const Color(0xFFFFB800);
  }

  @override
  Widget build(BuildContext context) {
    final date = ride.completedAt ?? ride.createdAt;
    final distanceKm = ride.estimatedDistanceMeters / 1000;

    return Scaffold(
      backgroundColor: const Color(0xFF11191D),
      appBar: const CustomAppBar(title: 'Trip Detail', showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF222222),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF2E2E2E)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      date != null ? '${date.day}/${date.month}/${date.year} · ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}' : '—',
                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _statusColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        ride.status,
                        style: TextStyle(color: _statusColor, fontSize: 11, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      children: [
                        const SizedBox(height: 4),
                        Container(
                          width: 12,
                          height: 12,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.primary,
                          ),
                        ),
                        Container(width: 1.5, height: 36, color: const Color(0xFF2E2E2E)),
                        Container(
                          width: 12,
                          height: 12,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFFEF4444),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Pickup', style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(ride.pickupAddress, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                          const SizedBox(height: 16),
                          const Text('Drop', style: TextStyle(color: Color(0xFFEF4444), fontSize: 12, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(ride.dropAddress, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (ride.isParcel || ride.parcel.isNotEmpty) ...[
            const SizedBox(height: 16),
            ParcelDetailsCard(parcel: ride.parcel, dark: true),
          ],
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF222222),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF2E2E2E)),
            ),
            child: Column(
              children: [
                _DetailRow(label: 'Rider', value: ride.riderName.isEmpty ? '—' : ride.riderName),
                _DetailRow(label: 'Distance', value: '${distanceKm.toStringAsFixed(1)} km'),
                if (ride.estimatedDurationMinutes > 0)
                  _DetailRow(label: 'Duration', value: '${ride.estimatedDurationMinutes.toStringAsFixed(0)} min'),
                _DetailRow(label: 'Payment method', value: ride.paymentMethod.isEmpty ? '—' : ride.paymentMethod),
                const Divider(color: Color(0xFF2E2E2E), height: 24),
                _DetailRow(
                  label: 'Total Fare',
                  value: '₹${ride.fare.toStringAsFixed(0)}',
                  isBold: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isBold;

  const _DetailRow({required this.label, required this.value, this.isBold = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: isBold ? Colors.white : const Color(0xFF94A3B8),
              fontSize: isBold ? 15 : 13.5,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: isBold ? AppColors.primary : Colors.white,
              fontWeight: isBold ? FontWeight.w900 : FontWeight.w700,
              fontSize: isBold ? 18 : 14.5,
            ),
          ),
        ],
      ),
    );
  }
}

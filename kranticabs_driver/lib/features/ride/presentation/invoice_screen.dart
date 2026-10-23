import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../data/ride_history_item.dart';

class InvoiceScreen extends StatelessWidget {
  final RideHistoryItem ride;

  const InvoiceScreen({super.key, required this.ride});

  @override
  Widget build(BuildContext context) {
    final date = ride.completedAt ?? ride.createdAt;
    // With location charges in the fare, the base row is the trip alone so the
    // rows add up to the total.
    final locationTotal = ride.locationCharges.fold<double>(0, (sum, c) => sum + c.amount);
    final baseFare = ride.locationCharges.isNotEmpty
        ? (ride.fare - locationTotal).clamp(0, double.infinity).toDouble()
        : (ride.baseFare > 0 ? ride.baseFare : ride.fare);
    final commission = ride.commissionAmount;

    return Scaffold(
      appBar: const CustomAppBar(title: 'Invoice'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.lightBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Trip Invoice', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        ride.status,
                        style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Trip ID: ${ride.id}',
                  style: const TextStyle(color: AppColors.lightTextSecondary, fontSize: 12),
                ),
                if (date != null)
                  Text(
                    '${date.day}/${date.month}/${date.year} · ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(color: AppColors.lightTextSecondary, fontSize: 12),
                  ),
                const Divider(height: 32),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      children: [
                        const Icon(Icons.circle, size: 8, color: AppColors.primary),
                        Container(width: 1.5, height: 26, color: AppColors.lightBorder),
                        const Icon(Icons.location_on, size: 12, color: AppColors.error),
                      ],
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(ride.pickupAddress, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                          const SizedBox(height: 16),
                          Text(ride.dropAddress, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 32),
                const Text('Fare breakdown', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 12),
                _FareRow(label: 'Base fare', value: baseFare),
                for (final charge in ride.locationCharges)
                  _FareRow(label: charge.label, value: charge.amount),
                if (commission > 0) _FareRow(label: 'Platform commission', value: -commission),
                const Divider(height: 24),
                _FareRow(label: 'Total fare', value: ride.fare, bold: true),
                const SizedBox(height: 6),
                _FareRow(label: 'Your earnings', value: ride.driverEarnings, bold: true, color: AppColors.primary),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Payment method', style: TextStyle(color: AppColors.lightTextSecondary, fontSize: 13)),
                    Text(
                      ride.paymentMethod.isEmpty ? '—' : ride.paymentMethod,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FareRow extends StatelessWidget {
  final String label;
  final double value;
  final bool bold;
  final Color? color;

  const _FareRow({required this.label, required this.value, this.bold = false, this.color});

  @override
  Widget build(BuildContext context) {
    final isNegative = value < 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: bold ? 14 : 13,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: bold ? AppColors.lightTextPrimary : AppColors.lightTextSecondary,
            ),
          ),
          Text(
            '${isNegative ? '-' : ''}₹${value.abs().toStringAsFixed(0)}',
            style: TextStyle(
              fontSize: bold ? 15 : 13,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              color: color ?? (bold ? AppColors.lightTextPrimary : AppColors.lightTextSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

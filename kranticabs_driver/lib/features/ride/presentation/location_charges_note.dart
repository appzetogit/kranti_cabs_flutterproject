import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../data/location_charges.dart';

/// The location charges inside the fare - airport fee, station entry fee,
/// state / MCD tax and parking - so the driver knows what the fare already
/// covers. Everything but the airport fee is theirs in full, no commission.
///
/// Renders nothing when the trip has none. Like [TollChargesNote] the palette
/// is passed in since it sits on both dark and light screens.
class LocationChargesNote extends StatelessWidget {
  final List<RideLocationCharge> charges;
  final bool dark;

  const LocationChargesNote({super.key, required this.charges, required this.dark});

  @override
  Widget build(BuildContext context) {
    if (charges.isEmpty) return const SizedBox.shrink();

    final textPrimary = dark ? Colors.white : const Color(0xFF0F172A);
    final textMuted = dark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final total = charges.fold<double>(0, (sum, c) => sum + c.amount);
    final passThrough = charges.any((c) => c.isPassThrough);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.local_parking_rounded, size: 16, color: AppColors.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Includes ₹${total.toStringAsFixed(0)} location charges'
                '${passThrough ? ' (station / tax / parking yours in full, no commission)' : ''}',
                style: TextStyle(color: textPrimary, fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                charges.map((c) => '${c.label} ₹${c.amount.toStringAsFixed(0)}').join(' · '),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: textMuted, fontSize: 11.5),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../data/toll_charges.dart';

/// The outstation tolls inside the fare, so the driver knows that part is
/// theirs to pay at the plaza and is not commissioned.
///
/// Renders nothing when the trip has no tolls. Like the parcel card, the
/// palette is passed in since it sits on both dark and light screens.
class TollChargesNote extends StatelessWidget {
  final TollCharges tolls;
  final bool dark;

  /// Just the one line, for the offer card where the driver has seconds.
  final bool compact;

  const TollChargesNote({
    super.key,
    required this.tolls,
    required this.dark,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!tolls.hasTolls) return const SizedBox.shrink();

    final textPrimary = dark ? Colors.white : const Color(0xFF0F172A);
    final textMuted = dark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final headline = compact
        ? 'Includes ${tolls.totalText} tolls · ${tolls.plazaCountText}'
        : 'Includes ${tolls.totalText} tolls (yours in full, no commission)';
    final plazas = tolls.items
        .where((p) => p.name.isNotEmpty)
        .map((p) => p.amount > 0 ? '${p.name} ₹${p.amount.toStringAsFixed(0)}' : p.name)
        .join(' · ');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.toll_rounded, size: 16, color: AppColors.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                headline,
                style: TextStyle(color: textPrimary, fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
              if (!compact && plazas.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  tolls.roundTrip ? '$plazas (both ways)' : plazas,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: textMuted, fontSize: 11.5),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

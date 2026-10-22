import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../data/ride_rental.dart';

String _hm(int minutes) => '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}';

/// In-trip card: package, live used timer (display only, the server bills),
/// and the overage rates.
class RentalUsageCard extends StatefulWidget {
  final RideRental rental;
  final DateTime? startedAt;
  const RentalUsageCard({super.key, required this.rental, this.startedAt});

  @override
  State<RentalUsageCard> createState() => _RentalUsageCardState();
}

class _RentalUsageCardState extends State<RentalUsageCard> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.rental;
    final used = widget.startedAt == null
        ? 0
        : DateTime.now().difference(widget.startedAt!).inMinutes.clamp(0, 100000);
    final progress = r.includedMinutes > 0 ? (used / r.includedMinutes).clamp(0.0, 1.0) : 0.0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF11191D),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Hourly rental · ${r.packageName}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          if (widget.startedAt != null) ...[
            Text('${_hm(used)} / ${_hm(r.includedMinutes.toInt())} hr used',
                style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: progress,
              color: AppColors.primary,
              backgroundColor: AppColors.darkBorder,
            ),
            const SizedBox(height: 8),
          ],
          Text(
            'Included ${r.includedLabel} · extra ₹${r.extraKmRate}/km · ₹${r.extraMinuteRate}/min',
            style: TextStyle(color: AppColors.darkTextSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

String _rs(num v) => '₹${v == v.roundToDouble() ? v.toInt() : v.toStringAsFixed(2)}';

/// Final bill lines. The total shown elsewhere is always the server's fare.
class RentalBill extends StatelessWidget {
  final RideRental rental;
  const RentalBill({super.key, required this.rental});

  @override
  Widget build(BuildContext context) {
    final r = rental;
    Widget line(String a, num v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(child: Text(a, style: TextStyle(color: AppColors.darkTextSecondary, fontSize: 13))),
              Text(_rs(v), style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
            ],
          ),
        );
    return Column(children: [
      line('Package (${r.packageName})', r.packagePrice),
      if (r.extraKm > 0)
        line('Extra ${r.extraKm} km (${r.travelledKm.toStringAsFixed(1)} km driven)', r.extraKmCharge),
      if (r.extraMinutes > 0)
        line('Extra ${r.extraMinutes} min (${_hm(r.usedMinutes.toInt())} hr used)', r.extraTimeCharge),
    ]);
  }
}

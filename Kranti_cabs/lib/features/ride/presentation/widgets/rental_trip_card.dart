import 'dart:async';

import 'package:flutter/material.dart';

import '../../../rental/data/hourly_rental.dart';

String _hm(int minutes) => '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}';
String _rs(num v) => '₹${v == v.roundToDouble() ? v.toInt() : v.toStringAsFixed(2)}';

/// Hourly-rental trip status for the tracking screen: package, time used of the
/// time included, and once the server settles it, the extra km / time charges.
/// Elapsed time is computed here from [startedAt] and is display-only; the
/// server does the billing.
class RentalTripCard extends StatefulWidget {
  final RideRental rental;
  final DateTime? startedAt;
  const RentalTripCard({super.key, required this.rental, this.startedAt});

  @override
  State<RentalTripCard> createState() => _RentalTripCardState();
}

class _RentalTripCardState extends State<RentalTripCard> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 20), (_) {
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
    final started = widget.startedAt;
    final settled = r.isSettled;
    final used = settled
        ? r.usedMinutes.toInt()
        : (started == null ? 0 : DateTime.now().difference(started).inMinutes.clamp(0, 100000));
    final over = used > r.includedMinutes;
    final progress = r.includedMinutes > 0 ? (used / r.includedMinutes).clamp(0.0, 1.0).toDouble() : 0.0;

    Widget line(String a, num v) => Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Flexible(child: Text(a, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5))),
            Text(_rs(v), style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700)),
          ]),
        );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF222222),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: over ? const Color(0xFFEF4444) : const Color(0xFF2E2E2E)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Hourly rental · ${r.packageName}',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        if (started != null || settled) ...[
          const SizedBox(height: 8),
          Text(
            '${_hm(used)} / ${_hm(r.includedMinutes.toInt())} hr'
            '${settled ? ' · ${r.travelledKm.toStringAsFixed(1)} / ${r.includedKm} km' : ''}'
            '${over && !settled ? ' · extra time is charged' : ''}',
            style: TextStyle(color: over ? const Color(0xFFEF4444) : const Color(0xFFF5B400), fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: progress,
            color: over ? const Color(0xFFEF4444) : const Color(0xFFF5B400),
            backgroundColor: const Color(0xFF2E2E2E),
          ),
        ],
        const SizedBox(height: 8),
        Text('Includes ${r.includedKm} km. Extra ${_rs(r.extraKmRate)}/km, ${_rs(r.extraMinuteRate)}/min.',
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5)),
        if (settled) ...[
          const SizedBox(height: 6),
          line('Package (${r.packageName})', r.packagePrice),
          if (r.extraKm > 0) line('Extra ${r.extraKm} km', r.extraKmCharge),
          if (r.extraMinutes > 0) line('Extra ${r.extraMinutes} min', r.extraTimeCharge),
        ],
      ]),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/scheduled_rides_providers.dart';

/// Home-screen entry to Scheduled Rides, with how many are the driver's own
/// and how many are open to take.
class ScheduledRidesTile extends ConsumerWidget {
  const ScheduledRidesTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rides = ref.watch(scheduledRidesProvider).valueOrNull ?? const [];
    final mine = rides.where((r) => r.isMine).length;
    final open = rides.length - mine;
    final subtitle = rides.isEmpty
        ? 'Rides booked for later'
        : [
            if (mine > 0) '$mine yours',
            if (open > 0) '$open open to take',
          ].join(' · ');

    return InkWell(
      onTap: () async {
        await context.push('/scheduled-rides');
        // Back from the list: pick up anything accepted or given back there.
        if (context.mounted) ref.invalidate(scheduledRidesProvider);
      },
      borderRadius: BorderRadius.circular(18),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFE0F2FE),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.event_rounded, color: Color(0xFF0369A1)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Scheduled Rides',
                    style: TextStyle(color: Color(0xFF0F172A), fontSize: 14.5, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 11.5, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8)),
          ],
        ),
      ),
    );
  }
}

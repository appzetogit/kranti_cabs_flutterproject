import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/bus_auth_providers.dart';
import '../bus_ui.dart';

/// Tab 4 — the bus driver's profile, bus details and logout.
class BusProfileTab extends ConsumerWidget {
  const BusProfileTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(busAuthProvider).profile;
    final bus = profile?.busService;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      children: [
        Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: BusColors.tealDark,
                shape: BoxShape.circle,
                border: Border.all(color: BusColors.teal),
              ),
              child: const Icon(Icons.person_rounded, color: BusColors.teal, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(profile?.name ?? 'Bus Partner',
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text('+91 ${profile?.phone ?? ''}',
                      style: const TextStyle(color: BusColors.textMuted, fontSize: 13)),
                ],
              ),
            ),
            BusTag(
              label: (profile?.isApproved ?? false) ? 'Approved' : 'Pending',
              color: (profile?.isApproved ?? false) ? BusColors.teal : const Color(0xFFF59E0B),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (profile != null)
          Row(
            children: [
              _stat('Upcoming', '${profile.upcomingBookings}'),
              const SizedBox(width: 12),
              _stat('Schedules', '${profile.totalSchedules}'),
              const SizedBox(width: 12),
              _stat('Capacity', '${profile.totalCapacity}'),
            ],
          ),
        const SizedBox(height: 18),
        if (bus != null)
          BusCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('My Bus',
                    style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                _row('Operator', bus.operatorName),
                _row('Bus', bus.busName),
                _row('Type', bus.coachType),
                if (bus.serviceNumber.isNotEmpty) _row('Service no.', bus.serviceNumber),
                if (bus.registrationNumber.isNotEmpty) _row('Reg. no.', bus.registrationNumber),
                if (bus.originCity.isNotEmpty || bus.destinationCity.isNotEmpty)
                  _row('Route', '${bus.originCity} → ${bus.destinationCity}'),
                _row('Bus status', bus.status.toUpperCase()),
              ],
            ),
          ),
        const SizedBox(height: 18),
        BusCard(
          onTap: () async {
            await ref.read(busAuthProvider.notifier).refreshProfile();
          },
          child: const Row(
            children: [
              Icon(Icons.refresh_rounded, color: BusColors.teal, size: 20),
              SizedBox(width: 12),
              Text('Refresh profile', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        BusCard(
          onTap: () async {
            await ref.read(busAuthProvider.notifier).logout();
            if (context.mounted) context.go('/login');
          },
          child: const Row(
            children: [
              Icon(Icons.logout_rounded, color: Color(0xFFEF4444), size: 20),
              SizedBox(width: 12),
              Text('Log out', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _stat(String label, String value) {
    return Expanded(
      child: BusCard(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        child: Column(
          children: [
            Text(value, style: const TextStyle(color: BusColors.teal, fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: BusColors.textMuted, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _row(String k, String v) {
    if (v.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 92, child: Text(k, style: const TextStyle(color: BusColors.textMuted, fontSize: 12.5))),
          Expanded(
            child: Text(v,
                style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

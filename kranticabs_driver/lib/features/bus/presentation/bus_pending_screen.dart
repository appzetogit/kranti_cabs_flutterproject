import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/snackbar_utils.dart';
import '../application/bus_auth_providers.dart';
import 'bus_ui.dart';

/// Shown to a bus driver whose account (or bus) is not yet active. Lets them
/// re-check approval and log out.
class BusPendingScreen extends ConsumerStatefulWidget {
  const BusPendingScreen({super.key});

  @override
  ConsumerState<BusPendingScreen> createState() => _BusPendingScreenState();
}

class _BusPendingScreenState extends ConsumerState<BusPendingScreen> {
  bool _checking = false;

  Future<void> _check() async {
    setState(() => _checking = true);
    final profile = await ref.read(busAuthProvider.notifier).refreshProfile();
    if (!mounted) return;
    setState(() => _checking = false);
    if (profile != null && profile.canOperate) {
      context.go('/bus-home');
    } else {
      SnackbarUtils.info('Still under review. We will notify you once active.');
    }
  }

  Future<void> _logout() async {
    await ref.read(busAuthProvider.notifier).logout();
    if (!mounted) return;
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(busAuthProvider).profile;
    final busDraft = profile?.busService != null && !(profile!.busService!.isActive);
    final blocked = profile?.isBlocked ?? false;

    return BusScaffold(
      title: 'Approval Pending',
      showBack: false,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
        children: [
          Center(
            child: Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: (blocked ? const Color(0xFFEF4444) : BusColors.teal).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                blocked ? Icons.block_rounded : Icons.hourglass_top_rounded,
                color: blocked ? const Color(0xFFEF4444) : BusColors.teal,
                size: 40,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            blocked ? 'Account blocked' : 'Verification in progress',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Text(
            blocked
                ? 'Your bus partner account has been blocked. Please contact support.'
                : busDraft
                    ? 'Your account is approved-pending and your bus is still being set up by our team (seats, pricing, schedules). You can operate once it is active.'
                    : 'Your bus partner account is under review. You will be able to manage bookings and trips once an admin approves it.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: BusColors.textMuted, fontSize: 14, height: 1.5),
          ),
          if (profile != null) ...[
            const SizedBox(height: 24),
            BusCard(
              child: Column(
                children: [
                  _row('Name', profile.name),
                  _row('Mobile', profile.phone),
                  if (profile.busService != null)
                    _row('Bus', profile.busService!.busName.isNotEmpty
                        ? profile.busService!.busName
                        : profile.busService!.operatorName),
                  _row('Status', profile.status.toUpperCase()),
                  if (profile.busService != null)
                    _row('Bus status', profile.busService!.status.toUpperCase()),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          if (!blocked)
            BusBottomBar(actionLabel: 'Check Status', isLoading: _checking, onPressed: _check),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: _logout,
              child: const Text('Log out', style: TextStyle(color: BusColors.textMuted)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String k, String v) {
    if (v.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 90, child: Text(k, style: const TextStyle(color: BusColors.textMuted, fontSize: 13))),
          Expanded(
            child: Text(v,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

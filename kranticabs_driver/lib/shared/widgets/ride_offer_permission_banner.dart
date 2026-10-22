import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/ride_offer_permission_flow.dart';

/// Names whatever is still blocking the full-screen ride-offer alert.
///
/// Persistent by design rather than a one-off prompt: each of these is a
/// Settings page the driver can leave without granting, and a driver who is
/// missing one silently stops seeing ride offers when their screen is off —
/// with nothing on screen to explain why.
class RideOfferPermissionBanner extends ConsumerStatefulWidget {
  const RideOfferPermissionBanner({super.key});

  @override
  ConsumerState<RideOfferPermissionBanner> createState() =>
      _RideOfferPermissionBannerState();
}

class _RideOfferPermissionBannerState
    extends ConsumerState<RideOfferPermissionBanner> {
  @override
  void initState() {
    super.initState();
    // The flow refreshes itself on every resume; this covers the first build,
    // which may happen before any resume event has fired.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(rideOfferPermissionFlowProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(rideOfferPermissionFlowProvider);
    if (status.allGranted) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final missing = status.missingLabels;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFD8A8)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.notifications_active_outlined,
              color: Color(0xFFB54708), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ride alerts may not reach you',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: const Color(0xFF93370D),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Still to allow: ${missing.join(', ')}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: const Color(0xFFB54708)),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => ref
                      .read(rideOfferPermissionFlowProvider.notifier)
                      .requestMissing(),
                  child: Text(
                    'Fix now',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF93370D),
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

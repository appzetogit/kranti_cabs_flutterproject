import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/services/location_service.dart';
import '../../home/application/home_providers.dart';
import 'widgets/pop_when_location_ready.dart';
import 'widgets/system_status_view.dart';

/// Shown when the device's location switch is off.
///
/// Re-checks on its own when the rider comes back from Settings, and has a
/// button for the same, so turning GPS on actually clears this screen.
class GpsDisabledScreen extends ConsumerStatefulWidget {
  const GpsDisabledScreen({super.key});

  @override
  ConsumerState<GpsDisabledScreen> createState() => _GpsDisabledScreenState();
}

class _GpsDisabledScreenState extends ConsumerState<GpsDisabledScreen> with WidgetsBindingObserver {
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _recheck();
  }

  Future<void> _recheck() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final issue = await ref.read(locationServiceProvider).diagnose();
      if (issue == LocationIssue.gpsOff || !mounted) return;
      // GPS is on (permission, if missing, is the other screen's job).
      ref.invalidate(currentPositionProvider);
      Navigator.of(context).maybePop();
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Closes itself as soon as the rider comes back with GPS on.
    return PopWhenLocationReady(
      isReady: (status) => status.serviceEnabled,
      child: SystemStatusView(
        icon: Icons.location_disabled_rounded,
        title: 'Turn on location services',
        message: 'Enable GPS on your device so we can find your pickup point and nearby drivers accurately.',
        primaryActionLabel: 'Open location settings',
        onPrimaryAction: () => Geolocator.openLocationSettings(),
        // A rider can still book by typing a pickup or picking it on the map,
        // so this is a prompt, not a wall.
        secondaryActionLabel: 'Enter pickup manually',
        onSecondaryAction: () => Navigator.of(context).maybePop(false),
      ),
    );
  }
}

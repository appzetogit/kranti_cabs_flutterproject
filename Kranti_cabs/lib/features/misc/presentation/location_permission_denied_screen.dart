import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/services/location_service.dart';
import '../../home/application/home_providers.dart';
import 'widgets/pop_when_location_ready.dart';
import 'widgets/system_status_view.dart';

/// Shown when the rider has not allowed location access.
///
/// While Android will still show its own prompt the main button asks again;
/// once the rider has chosen "don't ask again" only Settings can help, so it
/// opens those instead. Returning from Settings re-checks automatically.
class LocationPermissionDeniedScreen extends ConsumerStatefulWidget {
  const LocationPermissionDeniedScreen({super.key});

  @override
  ConsumerState<LocationPermissionDeniedScreen> createState() => _LocationPermissionDeniedScreenState();
}

class _LocationPermissionDeniedScreenState extends ConsumerState<LocationPermissionDeniedScreen>
    with WidgetsBindingObserver {
  bool _busy = false;
  bool _openSettings = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncMode();
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

  Future<void> _syncMode() async {
    final permission = await Geolocator.checkPermission();
    if (mounted) {
      setState(() => _openSettings = permission == LocationPermission.deniedForever);
    }
  }

  Future<void> _recheck() async {
    final issue = await ref.read(locationServiceProvider).diagnose();
    if (!mounted) return;
    if (issue == LocationIssue.none) {
      ref.invalidate(currentPositionProvider);
      Navigator.of(context).maybePop();
    } else {
      await _syncMode();
    }
  }

  Future<void> _primary() async {
    if (_openSettings) {
      await openAppSettings();
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(locationServiceProvider).ensurePermission();
      await _recheck();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Closes itself as soon as the rider comes back from Settings having
    // allowed location.
    return PopWhenLocationReady(
      isReady: (status) => status.granted,
      child: SystemStatusView(
        icon: Icons.location_off_rounded,
        title: 'Location permission needed',
        message: 'We need access to your location to show nearby drivers, calculate fares and get you picked up accurately.',
        primaryActionLabel: 'Open app settings',
        onPrimaryAction: _primary,
        secondaryActionLabel: 'Enter pickup manually',
        onSecondaryAction: () => Navigator.of(context).maybePop(false),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/services/location_service.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/application/auth_state.dart';
import '../application/home_providers.dart';

/// Keeps the rider's location from going stale or silently missing.
///
/// The position used to be read once, when the app first asked for it, and
/// remembered forever: allow location afterwards (or switch GPS on) and nothing
/// noticed until the app was killed and reopened. Now every return to the app
/// asks again, and when there is still no location the rider is shown the
/// screen that says what to fix - GPS off, or permission refused - instead of a
/// pickup field stuck on "Fetching location...".
class LocationGuard extends ConsumerStatefulWidget {
  final Widget child;

  const LocationGuard({super.key, required this.child});

  @override
  ConsumerState<LocationGuard> createState() => _LocationGuardState();
}

class _LocationGuardState extends ConsumerState<LocationGuard> with WidgetsBindingObserver {
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
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(currentPositionProvider);
      unawaited(_check());
    }
  }

  String get _path => appRouter.routerDelegate.currentConfiguration.uri.path;

  Future<void> _check() async {
    if (_checking) return;
    if (ref.read(authControllerProvider).status != AuthStatus.authenticated) return;

    _checking = true;
    try {
      // After a cold start the splash screen is still choosing where to go.
      for (var i = 0; i < 25 && !_path.startsWith('/home'); i++) {
        if (_path.startsWith('/system') || _path.startsWith('/auth')) return;
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }

      // Only interrupt the main screen. Mid-booking or mid-ride the rider
      // already chose where they are, and a full-screen detour would cost more
      // than it saves.
      if (_path != '/home' || !mounted) return;

      final position = await ref.read(currentPositionProvider.future);
      if (position != null || !mounted) return;

      final issue = await ref.read(locationServiceProvider).diagnose();
      if (!mounted || _path != '/home') return;

      switch (issue) {
        case LocationIssue.gpsOff:
          unawaited(appRouter.push('/system/gps-disabled'));
        case LocationIssue.permissionDenied:
          unawaited(appRouter.push('/system/location-permission-denied'));
        case LocationIssue.none:
          break;
      }
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authControllerProvider, (previous, next) {
      if (previous?.status != AuthStatus.authenticated && next.status == AuthStatus.authenticated) {
        unawaited(_check());
      }
    });
    return widget.child;
  }
}

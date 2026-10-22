import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import '../../core/navigation/navigator_key.dart';
import '../../core/providers/core_providers.dart';
import '../../core/services/ride_offer_channel.dart';
import '../ride/application/ride_providers.dart';

/// Watches connectivity and GPS status app-wide, pushing/popping the
/// No Internet and GPS Disabled overlay screens as conditions change.
///
/// Also drains answers given on the native full-screen ride-offer card, which
/// is answered while the app is backgrounded or killed and so has nowhere to
/// deliver to until the app is running again.
class SystemGate extends ConsumerStatefulWidget {
  final Widget child;
  const SystemGate({super.key, required this.child});

  @override
  ConsumerState<SystemGate> createState() => _SystemGateState();
}

class _SystemGateState extends ConsumerState<SystemGate>
    with WidgetsBindingObserver {
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  StreamSubscription<ServiceStatus>? _gpsSub;
  bool _offlineShown = false;
  bool _gpsShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _connectivitySub = Connectivity().onConnectivityChanged.listen(
      _onConnectivity,
    );
    if (!kIsWeb) {
      _gpsSub = ref
          .read(locationServiceProvider)
          .watchServiceStatus()
          .listen(_onGpsStatus);
    }

    RideOfferChannel.setPendingActionListener(_drainNativeOfferActions);
    // A cold start launched by Accept on the card has its answer waiting here.
    unawaited(_drainNativeOfferActions());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The card can be answered while the app sits in the background with no
    // engine listening, so resume is the reliable moment to collect.
    if (state == AppLifecycleState.resumed) {
      unawaited(_drainNativeOfferActions());
      // A stuck ringtone/offer card only ever clears on a message arriving;
      // if that message was lost, reopening the app is otherwise the first
      // chance to notice and correct it.
      unawaited(
        ref.read(rideProvider.notifier).reconcileIncomingRequestOnResume(),
      );
    }
  }

  Future<void> _drainNativeOfferActions() async {
    if (!mounted) return;
    await ref.read(rideProvider.notifier).consumeNativeOfferActions();
  }

  void _onConnectivity(List<ConnectivityResult> results) {
    final offline = results.every((r) => r == ConnectivityResult.none);
    final context = rootNavigatorKey.currentContext;
    if (context == null) return;
    final router = GoRouter.of(context);
    if (offline && !_offlineShown) {
      _offlineShown = true;
      router.push('/no-internet');
    } else if (!offline && _offlineShown) {
      _offlineShown = false;
      if (router.canPop()) router.pop();
    }
  }

  void _onGpsStatus(ServiceStatus status) {
    final disabled = status == ServiceStatus.disabled;
    final context = rootNavigatorKey.currentContext;
    if (context == null) return;
    final router = GoRouter.of(context);
    if (disabled && !_gpsShown) {
      _gpsShown = true;
      router.push('/gps-disabled');
    } else if (!disabled && _gpsShown) {
      _gpsShown = false;
      if (router.canPop()) router.pop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    RideOfferChannel.clearPendingActionListener();
    _connectivitySub?.cancel();
    _gpsSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

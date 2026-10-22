import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ride_offer_channel.dart';

/// Walks the driver through the three special permissions the full-screen ride
/// offer needs, **one at a time**.
///
/// None of them is a runtime dialog — each opens its own Settings page, and
/// Android ignores a second request while the first page is showing. Firing
/// them together means the driver only ever sees one, and the other two look
/// like they were silently denied. So each request waits for the app to come
/// back to the foreground before the next one is made.
class RideOfferPermissionFlow extends StateNotifier<RideOfferPermissionStatus>
    with WidgetsBindingObserver {
  RideOfferPermissionFlow() : super(RideOfferPermissionStatus.unknown) {
    WidgetsBinding.instance.addObserver(this);
  }

  /// Some OEM Settings screens return without ever producing a resume event.
  /// Without this the flow would stall on the first one forever.
  static const _resumeTimeout = Duration(seconds: 90);

  /// Breathing room after the resume before the next Settings page is opened,
  /// so the two screens do not visibly collide.
  static const _settleDelay = Duration(milliseconds: 600);

  Completer<void>? _resumeWaiter;
  bool _running = false;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;

    unawaited(refresh());

    final waiter = _resumeWaiter;
    if (waiter != null && !waiter.isCompleted) {
      waiter.complete();
    }
  }

  Future<RideOfferPermissionStatus> refresh() async {
    final next = await RideOfferChannel.permissions();
    if (mounted) state = next;
    return next;
  }

  /// Requests whatever is still missing, in order, pausing between each.
  ///
  /// Safe to call repeatedly — a run already in progress is left alone.
  Future<void> requestMissing() async {
    if (_running) return;
    _running = true;

    try {
      var status = await refresh();
      if (status.allGranted) return;

      if (!status.fullScreenIntent) {
        await _requestOne(RideOfferChannel.requestFullScreenIntent);
        status = await refresh();
      }

      if (!status.overlay) {
        await _requestOne(RideOfferChannel.requestOverlay);
        status = await refresh();
      }

      if (!status.batteryOptimizations) {
        await _requestOne(RideOfferChannel.requestIgnoreBatteryOptimizations);
        await refresh();
      }
    } finally {
      _running = false;
    }
  }

  /// Opens one Settings page and waits for the driver to come back.
  ///
  /// If nothing opened — several OEM builds throw on these intents — there is
  /// no resume coming, so the flow moves straight on to the next permission
  /// rather than burning the timeout on a page that was never shown.
  Future<void> _requestOne(Future<bool> Function() request) async {
    final waiter = Completer<void>();
    _resumeWaiter = waiter;

    final opened = await request();
    if (!opened) {
      _resumeWaiter = null;
      return;
    }

    await waiter.future.timeout(_resumeTimeout, onTimeout: () {});
    _resumeWaiter = null;
    await Future<void>.delayed(_settleDelay);
  }
}

/// The provider disposes the notifier itself, which removes the lifecycle
/// observer — no `ref.onDispose` here, that would dispose it twice.
final rideOfferPermissionFlowProvider =
    StateNotifierProvider<RideOfferPermissionFlow, RideOfferPermissionStatus>((ref) {
  return RideOfferPermissionFlow();
});

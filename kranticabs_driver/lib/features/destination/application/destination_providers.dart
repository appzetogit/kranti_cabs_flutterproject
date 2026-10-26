import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers/core_providers.dart';
import '../../auth/application/auth_providers.dart';
import '../data/destination_mode.dart';
import '../data/destination_repository.dart';

final destinationRepositoryProvider = Provider<DestinationRepository>((ref) {
  return DestinationRepository(ref.watch(apiClientProvider));
});

/// Destination mode ("Go Home") for the home-screen card and the home
/// location screen. Every action returns the server's new state, or throws an
/// [ApiException] whose message is ready to show (e.g. "You've used
/// destination mode 1/1 times today.").
class DestinationModeNotifier extends StateNotifier<AsyncValue<DestinationModeInfo>> {
  final DestinationRepository _repository;

  DestinationModeNotifier(this._repository) : super(const AsyncValue.loading()) {
    refresh();
  }

  bool _busy = false;
  bool get busy => _busy;

  /// While the mode is on the server can end it by itself (arrival, time
  /// limit), so the card re-checks every minute until it is off.
  Timer? _watch;

  void _set(DestinationModeInfo info) {
    state = AsyncValue.data(info);
    if (info.enabled) {
      _watch ??= Timer.periodic(const Duration(minutes: 1), (_) => refresh());
    } else {
      _watch?.cancel();
      _watch = null;
    }
  }

  Future<void> refresh() async {
    try {
      _set(await _repository.get());
    } catch (error, stack) {
      // Keep showing the last known state rather than an error card.
      if (!state.hasValue) state = AsyncValue.error(error, stack);
    }
  }

  Future<void> _run(Future<DestinationModeInfo> Function() action) async {
    if (_busy) return;
    _busy = true;
    try {
      _set(await action());
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    _watch?.cancel();
    super.dispose();
  }

  Future<void> goHome() => _run(_repository.goHome);

  Future<void> turnOff() => _run(_repository.turnOff);

  Future<void> setHome({required double lat, required double lng, required String address}) =>
      _run(() => _repository.setHome(lat: lat, lng: lng, address: address));
}

final destinationModeProvider =
    StateNotifierProvider<DestinationModeNotifier, AsyncValue<DestinationModeInfo>>((ref) {
  // Rebuilt for each signed-in driver. Without this the first driver's saved
  // home and "move again from <date>" lock stayed on screen after logging in
  // as someone new, because nothing else here changes at login.
  ref.watch(authProvider.select((a) => a.driver?.id));
  return DestinationModeNotifier(ref.watch(destinationRepositoryProvider));
});

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/services/socket_service.dart';
import '../../dashboard/application/dashboard_providers.dart';
import '../data/heatmap_repository.dart';
import '../data/opportunity_models.dart';

final heatmapRepositoryProvider = Provider<HeatmapRepository>((ref) {
  return HeatmapRepository(ref.watch(apiClientProvider));
});

class HeatmapState {
  final OpportunityMap map;
  final bool loading;
  final String? error;

  /// True only for the very first load. Later refreshes update in place so the
  /// map never flashes a spinner over areas the driver is already reading.
  final bool isInitial;

  const HeatmapState({
    required this.map,
    this.loading = false,
    this.error,
    this.isInitial = true,
  });

  HeatmapState copyWith({
    OpportunityMap? map,
    bool? loading,
    String? error,
    bool? isInitial,
    bool clearError = false,
  }) {
    return HeatmapState(
      map: map ?? this.map,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      isInitial: isInitial ?? this.isInitial,
    );
  }
}

/// Keeps the surge & demand map current.
///
/// Three things drive a refresh, deliberately in this order of cost:
///   * the driver opening the screen or moving far enough to change the view
///   * a `heatmap:update` nudge over the existing socket, debounced
///   * a timer at the interval the server asks for (never under 30 s)
///
/// Polling stops while the app is in the background: nobody is looking, and
/// a map refreshing every minute in a pocket is battery for nothing. It
/// refreshes straight away on return, since a surge may have started or ended.
class HeatmapController extends StateNotifier<HeatmapState> {
  final Ref ref;

  HeatmapController(this.ref) : super(HeatmapState(map: OpportunityMap.empty())) {
    _attachSocket();
    _lifecycle = AppLifecycleListener(
      onHide: _pause,
      onShow: () {
        if (_disposed) return;
        unawaited(refresh());
      },
    );
  }

  late final AppLifecycleListener _lifecycle;
  Timer? _pollTimer;
  Timer? _debounce;
  double? _lat;
  double? _lng;
  bool _fetching = false;
  bool _disposed = false;

  /// Refetch when the driver has moved at least this far, so panning a few
  /// hundred metres does not hammer the endpoint.
  static const double _refetchAfterMeters = 900;

  late final void Function(dynamic) _onZoneChanged = (_) {
    // Several rides can land at once; collapse them into one refetch.
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 3), () {
      if (!_disposed) unawaited(refresh());
    });
  };

  void _attachSocket() {
    try {
      ref.read(socketServiceProvider).on('heatmap:update', _onZoneChanged);
    } catch (_) {
      // No socket yet (signed out). The poll timer still keeps the map fresh.
    }
  }

  void _pause() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _debounce?.cancel();
  }

  /// Points the map at a location. Cheap to call on every position update —
  /// it only refetches when the driver has actually moved somewhere new.
  Future<void> setLocation(double lat, double lng, {bool force = false}) async {
    final movedFar = _lat == null ||
        _lng == null ||
        _distanceMeters(_lat!, _lng!, lat, lng) > _refetchAfterMeters;

    _lat = lat;
    _lng = lng;

    if (force || movedFar) await refresh();
  }

  Future<void> refresh() async {
    final lat = _lat;
    final lng = _lng;
    if (lat == null || lng == null || _fetching) return;

    _fetching = true;
    if (state.isInitial) state = state.copyWith(loading: true, clearError: true);

    try {
      final map = await ref.read(heatmapRepositoryProvider).getOpportunityMap(lat: lat, lng: lng);
      if (_disposed) return;

      state = HeatmapState(map: map, loading: false, isInitial: false);
      _restartPolling(map.refreshAfterSeconds);
    } catch (error) {
      if (_disposed) return;
      // The map itself must keep working on a bad network: the previous areas
      // stay on screen and only the freshness label changes.
      state = state.copyWith(
        loading: false,
        isInitial: false,
        error: 'Could not refresh the map',
      );
      _restartPolling(state.map.refreshAfterSeconds);
    } finally {
      _fetching = false;
    }
  }

  void _restartPolling(int seconds) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      Duration(seconds: seconds.clamp(30, 120)),
      (_) => unawaited(refresh()),
    );
  }

  static double _distanceMeters(double aLat, double aLng, double bLat, double bLng) {
    const earthRadius = 6371000.0;
    double rad(double d) => d * 3.141592653589793 / 180;
    final dLat = rad(bLat - aLat);
    final dLng = rad(bLng - aLng);
    final h = (1 - math.cos(dLat)) / 2 +
        math.cos(rad(aLat)) * math.cos(rad(bLat)) * (1 - math.cos(dLng)) / 2;
    return 2 * earthRadius * math.asin(math.sqrt(h).clamp(0.0, 1.0));
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    _debounce?.cancel();
    _lifecycle.dispose();
    try {
      // Our own handler only — omitting it would drop every listener for the
      // event, including any future one.
      ref.read(socketServiceProvider).off('heatmap:update', _onZoneChanged);
    } catch (_) {}
    super.dispose();
  }
}

final heatmapControllerProvider =
    StateNotifierProvider.autoDispose<HeatmapController, HeatmapState>((ref) {
  // autoDispose on purpose: the map is a screen the driver visits, and
  // polling should stop the moment they leave it.
  return HeatmapController(ref);
});

/// The single best place to go right now, for the card on Home.
///
/// Fetched once when Home shows it, and again at the server's suggested
/// interval while Home stays open. Uses the position the dashboard's tracking
/// loop already keeps, so it costs no extra location request. Null when the
/// driver's position is not known yet or nothing is surging or busy nearby.
final nearbyHotspotProvider = FutureProvider.autoDispose<Hotspot?>((ref) async {
  // Rounded to two decimals (~1 km): the tracking loop moves the position on
  // every fix, and watching it raw would refetch the map each time.
  final cell = ref.watch(dashboardProvider.select((d) => (
        d.lat == null ? null : (d.lat! * 100).round(),
        d.lng == null ? null : (d.lng! * 100).round(),
      )));
  if (cell.$1 == null || cell.$2 == null) return null;
  final lat = cell.$1! / 100;
  final lng = cell.$2! / 100;

  final map = await ref.read(heatmapRepositoryProvider).getOpportunityMap(lat: lat, lng: lng);

  final timer = Timer(Duration(seconds: map.refreshAfterSeconds.clamp(30, 120)), ref.invalidateSelf);
  ref.onDispose(timer.cancel);

  return map.best;
});

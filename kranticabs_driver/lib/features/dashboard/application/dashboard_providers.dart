import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers/core_providers.dart';
import '../../auth/application/auth_providers.dart';
import '../data/dashboard_repository.dart';
import 'dashboard_state.dart';

class SelfieRequiredException implements Exception {}

class LocationRequiredException implements Exception {
  final bool serviceDisabled;
  final bool permanentlyDenied;

  LocationRequiredException({
    required this.serviceDisabled,
    required this.permanentlyDenied,
  });
}

final dashboardRepositoryProvider = Provider<DashboardRepository>((ref) {
  return DashboardRepository(ref.watch(apiClientProvider));
});

class DashboardNotifier extends StateNotifier<DashboardState> {
  final Ref ref;

  DashboardNotifier(this.ref) : super(const DashboardState());

  /// Keeps `Driver.location` fresh for the whole online session, not just the
  /// moment "Go Online" was tapped.
  ///
  /// Without this, the server only ever learns where the driver was standing
  /// at go-online time — every rider's ETA and every dispatch-radius check
  /// for this driver keeps using that one frozen point for as long as the
  /// driver stays online, however far they actually drive. The distance
  /// filter (25m) matches the server's own write threshold
  /// (`DRIVER_LOCATION_WRITE_MIN_DISTANCE_METERS` in `socket/index.js`), so
  /// this emits about as often as the server would ever act on anyway.
  StreamSubscription<Position>? _idleLocationSub;

  /// A driver parked for minutes on end never crosses the 25m filter above,
  /// so without this the server (and every rider/dispatch read of this
  /// driver's position) would keep a location that's arbitrarily stale —
  /// correct when they stopped, silent about the fact that they're still
  /// there. This is a floor under the distance-filter stream, not a
  /// replacement for it: real movement still reports immediately via the
  /// filter above; this only fires when nothing has been sent in 30s.
  Timer? _idleHeartbeatTimer;
  Position? _lastIdlePosition;
  DateTime? _lastIdleLocationSentAt;
  static const _idleHeartbeatInterval = Duration(seconds: 30);

  void _startIdleLocationTracking() {
    if (_idleLocationSub != null) return;
    _idleLocationSub = ref
        .read(locationServiceProvider)
        // Kept alive in the background, so dispatch keeps an accurate position
        // for a driver who is online but has switched to another app.
        .watchPosition(distanceFilterMeters: 25, keepAliveInBackground: true)
        .listen(
          (position) {
            state = state.copyWith(
              lat: position.latitude,
              lng: position.longitude,
            );
            ref
                .read(socketServiceProvider)
                .sendLocationUpdate(position.latitude, position.longitude);
            _lastIdlePosition = position;
            _lastIdleLocationSentAt = DateTime.now();
          },
          onError: (Object error) {
            // A permission revoked mid-session (or a GPS/provider fault)
            // throws here. Without this handler the stream's error was
            // unhandled — on some devices that surfaced as an app crash, and
            // it always left the driver's location silently frozen with
            // nothing to explain why.
            developer.log('Idle location stream error: $error');
          },
        );

    _idleHeartbeatTimer?.cancel();
    _idleHeartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      final position = _lastIdlePosition;
      final lastSentAt = _lastIdleLocationSentAt;
      if (position == null || lastSentAt == null) return;
      if (DateTime.now().difference(lastSentAt) < _idleHeartbeatInterval)
        return;

      ref
          .read(socketServiceProvider)
          .sendLocationUpdate(position.latitude, position.longitude);
      _lastIdleLocationSentAt = DateTime.now();
    });
  }

  Future<void> _stopIdleLocationTracking() async {
    await _idleLocationSub?.cancel();
    _idleLocationSub = null;
    _idleHeartbeatTimer?.cancel();
    _idleHeartbeatTimer = null;
    _lastIdlePosition = null;
    _lastIdleLocationSentAt = null;
  }

  /// Resumes location tracking after a cold start if the driver was already
  /// online server-side.
  ///
  /// `goOnline()`/`goOffline()` only run when the driver actually taps the
  /// toggle in this session — a driver who force-closes the app mid-shift and
  /// reopens it is still online per the server, but this fresh
  /// `DashboardNotifier` has no subscription running for them. Called once
  /// from the home screen on load; safe to call repeatedly since
  /// `_startIdleLocationTracking` no-ops while already tracking.
  Future<void> resumeTrackingIfOnline() async {
    final isOnline = ref.read(authProvider).driver?.isOnline ?? false;
    if (!isOnline) return;
    state = state.copyWith(isOnline: true);

    // Unlike goOnline() (a direct user tap this app can react to), this path
    // runs silently on cold start — a driver who denied or later revoked
    // location access must not have `watchPosition()` throw an unhandled
    // exception here; they just stay marked online with tracking held off
    // until they toggle offline/online again through the normal flow.
    final permission = await ref.read(locationServiceProvider).ensurePermission();
    if (!permission.granted) {
      developer.log(
        'resumeTrackingIfOnline: location permission not granted, tracking held off',
      );
      return;
    }

    _startIdleLocationTracking();
  }

  @override
  void dispose() {
    _idleLocationSub?.cancel();
    _idleHeartbeatTimer?.cancel();
    super.dispose();
  }

  Future<void> goOnline({String? selfieDataUrl}) async {
    state = state.copyWith(busy: true);
    try {
      final locationService = ref.read(locationServiceProvider);
      final permission = await locationService.ensurePermission();
      if (!permission.granted) {
        throw LocationRequiredException(
          serviceDisabled: !permission.serviceEnabled,
          permanentlyDenied: permission.permanentlyDenied,
        );
      }
      final position = await locationService.getCurrentPosition();
      String? selfieUrl;
      if (selfieDataUrl != null) {
        selfieUrl = await ref
            .read(dashboardRepositoryProvider)
            .uploadSelfie(selfieDataUrl);
      }
      final driver = await ref
          .read(dashboardRepositoryProvider)
          .goOnline(
            position.latitude,
            position.longitude,
            selfieImageUrl: selfieUrl,
          );
      ref.read(authProvider.notifier).updateDriver(driver);
      state = state.copyWith(
        isOnline: true,
        busy: false,
        lat: position.latitude,
        lng: position.longitude,
      );
      ref
          .read(socketServiceProvider)
          .sendLocationUpdate(position.latitude, position.longitude);
      _startIdleLocationTracking();
    } on ApiException catch (e) {
      state = state.copyWith(busy: false);
      if (e.statusCode == 400 && e.message.toLowerCase().contains('selfie')) {
        throw SelfieRequiredException();
      }
      rethrow;
    } catch (_) {
      state = state.copyWith(busy: false);
      rethrow;
    }
  }

  Future<void> goOffline() async {
    state = state.copyWith(busy: true);
    try {
      final driver = await ref.read(dashboardRepositoryProvider).goOffline();
      ref.read(authProvider.notifier).updateDriver(driver);
      state = state.copyWith(isOnline: false, busy: false);
      await _stopIdleLocationTracking();
    } catch (_) {
      state = state.copyWith(busy: false);
      rethrow;
    }
  }
}

final dashboardProvider =
    StateNotifierProvider<DashboardNotifier, DashboardState>((ref) {
      return DashboardNotifier(ref);
    });

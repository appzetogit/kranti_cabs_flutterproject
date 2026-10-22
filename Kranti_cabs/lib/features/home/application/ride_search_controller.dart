import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/services/socket_events.dart';
import '../../../core/services/socket_service.dart';
import '../../ride/application/ride_providers.dart';
import '../../ride/data/models/ride_model.dart';
import 'booking_controller.dart';
import 'ride_search_state.dart';

/// Owns the window between "rider tapped Book" and "a driver has the trip".
///
/// It is created once at sign-in (see `AuthController._persistSession`) rather
/// than when the search screen mounts, because dispatch can match a driver
/// within a second of the ride being created — a listener bound at screen-mount
/// time would race the `rideAccepted` event and lose.
class RideSearchController extends StateNotifier<RideSearchState> {
  final Ref ref;
  late final SocketService _socket;
  Timer? _activeRideCheckTimer;

  RideSearchController(this.ref) : super(const RideSearchState()) {
    _socket = ref.read(socketServiceProvider);
    _bindSocketListeners();
  }

  /// One registration per event name. The constants and the literal strings
  /// used to be listed side by side, and where they were the same name the
  /// handler ran twice per event (SocketService.on does not deduplicate).
  /// The literals kept here are genuinely different names.
  void _bindSocketListeners() {
    _socket.on(SocketEvents.rideSearchUpdate, _handleSearchUpdate);
    _socket.on('ride:search:update', _handleSearchUpdate);

    _socket.on(SocketEvents.rideAccepted, _handleAccepted);
    _socket.on('ride:accepted', _handleAccepted);
    _socket.on('ride_accepted', _handleAccepted);

    _socket.on(SocketEvents.rideStatusUpdated, _handleStatusUpdated);

    _socket.on(SocketEvents.rideState, _handleStateUpdated);

    _socket.on(SocketEvents.rideCancelled, _handleCancelled);
    _socket.on('ride:cancelled', _handleCancelled);

    _socket.on(SocketEvents.rideBiddingUpdated, _handleBiddingUpdated);
  }

  Map<String, dynamic>? _asMap(dynamic data) =>
      data is Map ? Map<String, dynamic>.from(data) : null;

  /// Dispatch events arrive on the rider's own room, so anything we receive is
  /// necessarily for this rider. We still match on id once we know it, to
  /// ignore stragglers from a previous booking.
  bool _isForCurrentSearch(Map<String, dynamic> map) {
    final id = state.rideId;
    if (id == null || id.isEmpty) return state.isSearching;
    final mapId = (map['rideId'] ?? map['_id'] ?? map['id'] ?? '').toString();
    if (mapId.isEmpty) return true;
    return mapId == id;
  }

  /// Called before the create-ride request goes out so no event is missed
  /// while the POST is in flight.
  void beginCreating() {
    state = const RideSearchState(phase: RideSearchPhase.creating);
  }

  /// Called once the backend has assigned a ride id. Joining the ride room is
  /// what makes chat, driver location and `ride:state` start flowing.
  void attachRide(RideModel ride) {
    if (state.phase == RideSearchPhase.accepted) return;
    state = state.copyWith(
      phase: RideSearchPhase.searching,
      rideId: ride.rideId,
    );
    _socket.joinRide(ride.rideId);
    _startActiveRidePolling();
  }

  void _startActiveRidePolling() {
    _activeRideCheckTimer?.cancel();
    _activeRideCheckTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!state.isSearching || state.rideId == null) {
        _activeRideCheckTimer?.cancel();
        return;
      }
      try {
        final searchingId = state.rideId!;
        final repository = ref.read(rideRepositoryProvider);
        final activeRide = await repository.getMyActiveRide();
        if (activeRide != null && activeRide.rideId == searchingId) {
          final s = activeRide.status.toLowerCase();
          if (s == 'accepted' || s == 'arriving' || s == 'started' || s == 'arrived') {
            _activeRideCheckTimer?.cancel();
            state = state.copyWith(
              phase: RideSearchPhase.accepted,
              rideId: activeRide.rideId,
              clearMessage: true,
            );
          }
          return;
        }
        // No active ride, or a different one: this search is over on the
        // server. If the `rideCancelled` event was missed (a socket blip)
        // nothing else would ever leave the "Finding driver" screen, so
        // confirm against the ride itself and end the search the way the
        // socket handler would.
        final ride = await repository.getRideById(searchingId);
        if (!mounted || !state.isSearching || state.rideId != searchingId) return;
        if (ride.isCancelled) _handleCancelled({'rideId': searchingId});
      } catch (_) {}
    });
  }

  void failCreate(String message) {
    state = state.copyWith(phase: RideSearchPhase.failed, message: message);
  }

  void _handleSearchUpdate(dynamic data) {
    final map = _asMap(data);
    if (map == null || !_isForCurrentSearch(map)) return;

    state = state.copyWith(
      phase: RideSearchPhase.searching,
      rideId: (map['rideId'] ?? map['_id'] ?? state.rideId)?.toString(),
      attempt: (map['attempt'] as num?)?.toInt() ?? state.attempt,
      maxAttempts: (map['maxAttempts'] as num?)?.toInt() ?? state.maxAttempts,
      radiusMeters:
          (map['radius'] as num?)?.toDouble() ?? state.radiusMeters,
      matchedDrivers:
          (map['matchedDrivers'] as num?)?.toInt() ?? state.matchedDrivers,
      totalNotifiedDrivers: (map['totalNotifiedDrivers'] as num?)?.toInt() ??
          state.totalNotifiedDrivers,
      maxSearchSeconds: (map['maxSearchSeconds'] as num?)?.toInt() ??
          state.maxSearchSeconds,
    );
  }

  void _handleAccepted(dynamic data) {
    final map = _asMap(data);
    if (map == null || !_isForCurrentSearch(map)) return;

    _activeRideCheckTimer?.cancel();
    state = state.copyWith(
      phase: RideSearchPhase.accepted,
      rideId: (map['rideId'] ?? map['_id'] ?? map['id'] ?? state.rideId)?.toString(),
      clearMessage: true,
    );
  }

  void _handleStatusUpdated(dynamic data) {
    final map = _asMap(data);
    if (map == null || !_isForCurrentSearch(map)) return;
    final status = (map['status'] ?? '').toString().toLowerCase();
    if (status == 'accepted' || status == 'arriving' || status == 'started' || status == 'arrived') {
      _handleAccepted(map);
    }
  }

  void _handleStateUpdated(dynamic data) {
    final map = _asMap(data);
    if (map == null || !_isForCurrentSearch(map)) return;
    final status = (map['status'] ?? '').toString().toLowerCase();
    if (status == 'accepted' || status == 'arriving' || status == 'started' || status == 'arrived') {
      _handleAccepted(map);
    }
  }

  void _handleCancelled(dynamic data) {
    final map = _asMap(data);
    if (map == null || !_isForCurrentSearch(map)) return;

    _activeRideCheckTimer?.cancel();
    final reasonCode = (map['reasonCode'] ?? '').toString();
    state = state.copyWith(
      phase: reasonCode == 'no_drivers'
          ? RideSearchPhase.noDrivers
          : RideSearchPhase.cancelled,
      message: map['reason']?.toString(),
    );
  }

  /// The fare or negotiation mode changed on the server without the rider
  /// tapping anything here — dispatch auto-raising a stuck search is the
  /// current source, but this also covers any future case. The payload
  /// itself only carries the bidding fields (see `notifyRideBiddingUpdated`
  /// server-side), so the full ride is re-fetched rather than patched
  /// piecemeal — `booking.createdRide` is what `RaiseFareCard` and the
  /// "See driver offers" button both read, and a partial merge here would
  /// risk drifting from what the server actually holds.
  void _handleBiddingUpdated(dynamic data) {
    final map = _asMap(data);
    if (map == null || !_isForCurrentSearch(map) || !state.isSearching) return;
    unawaited(_refreshCreatedRide(map['rideId']?.toString() ?? state.rideId));
  }

  Future<void> _refreshCreatedRide(String? rideId) async {
    if (rideId == null || rideId.isEmpty) return;
    try {
      final ride = await ref.read(rideRepositoryProvider).getRideById(rideId);
      ref.read(bookingControllerProvider.notifier).replaceCreatedRide(ride);
    } catch (_) {
      // Best-effort: the rider still sees the last fare that loaded, and the
      // next update (or a manual raise, which refreshes it itself) catches up.
    }
  }

  /// Cancels over REST rather than the socket so the rider gets a definitive
  /// success/failure, and so the ride is really released server-side (the
  /// dispatch loop keeps running otherwise).
  Future<bool> cancelSearch({String? reason, String? reasonId, String? note}) async {
    _activeRideCheckTimer?.cancel();
    final rideId = state.rideId;
    if (rideId == null) {
      reset();
      return true;
    }
    try {
      await ref.read(rideRepositoryProvider).cancelRide(
            rideId,
            reason: reason,
            reasonId: reasonId,
            note: note,
          );
      // Home's ongoing-ride card polls on a 15s cycle; refetch now so the
      // cancelled trip is gone by the time the rider gets back there.
      ref.invalidate(myActiveRideProvider);
      state = state.copyWith(phase: RideSearchPhase.cancelled);
      return true;
    } catch (e) {
      state = state.copyWith(message: e.toString());
      return false;
    }
  }

  void reset() {
    _activeRideCheckTimer?.cancel();
    state = const RideSearchState();
  }

  @override
  void dispose() {
    _activeRideCheckTimer?.cancel();
    _socket.off(SocketEvents.rideSearchUpdate, _handleSearchUpdate);
    _socket.off('ride:search:update', _handleSearchUpdate);
    _socket.off(SocketEvents.rideAccepted, _handleAccepted);
    _socket.off('ride:accepted', _handleAccepted);
    _socket.off('ride_accepted', _handleAccepted);
    _socket.off(SocketEvents.rideStatusUpdated, _handleStatusUpdated);
    _socket.off(SocketEvents.rideState, _handleStateUpdated);
    _socket.off(SocketEvents.rideCancelled, _handleCancelled);
    _socket.off('ride:cancelled', _handleCancelled);
    _socket.off(SocketEvents.rideBiddingUpdated, _handleBiddingUpdated);
    super.dispose();
  }
}

final rideSearchControllerProvider =
    StateNotifierProvider<RideSearchController, RideSearchState>((ref) {
  return RideSearchController(ref);
});

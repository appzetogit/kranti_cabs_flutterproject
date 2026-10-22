import 'dart:async';
import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/services/audio_service.dart';
import '../../../core/services/socket_events.dart';
import '../../../core/services/socket_service.dart';
import '../data/models/ride_message_model.dart';
import '../voice/services/ride_eta_service.dart';
import '../voice/application/ride_voice_providers.dart';
import '../data/models/ride_model.dart';
import 'ride_providers.dart';
import 'ride_tracking_state.dart';

class RideTrackingController extends StateNotifier<RideTrackingState> {
  final Ref ref;
  final String rideId;
  late final SocketService _socket;
  Timer? _pollingTimer;

  /// The most recent position the socket delivered, and when it arrived.
  ///
  /// REST is polled every few seconds for status, but the position it carries
  /// is only written when the server's persist throttle fires - up to fifteen
  /// seconds behind. Merging a poll wholesale therefore replaced a fresh fix
  /// with an older one on a fixed cadence, and the marker jumped backwards and
  /// re-drove the same stretch of road. That was the stutter, not the map.
  LatLngPoint? _liveDriverLocation;
  double? _liveDriverHeading;
  double? _liveDriverAccuracy;
  DateTime? _liveDriverAt;

  /// How long a socket fix keeps precedence over a polled one. Past this the
  /// driver app has most likely stopped sending, and a stale marker held in
  /// place would be a worse lie than the server's last known position.
  static const Duration _liveLocationTtl = Duration(seconds: 30);

  /// Ordering signal from the driver app's `sequence`/`timestamp` fields
  /// (see socket_service.dart on the driver side) — a packet is only
  /// accepted if it's newer than the last one, so a fix delayed by network
  /// jitter can never move the marker backward. Null until the first tagged
  /// packet arrives; an older driver build that sends neither field is
  /// unaffected — see [_isNewerThanLastAccepted].
  int? _lastAcceptedSequence;
  int? _lastAcceptedTimestampMs;

  /// A fix implying the driver travelled faster than this since the last
  /// accepted one is almost certainly a GPS glitch (a multi-km "teleport"),
  /// not a real vehicle. Generous on purpose — this must never reject
  /// genuine fast driving, only obvious nonsense.
  static const double _implausibleSpeedMetersPerSecond = 55; // ~198 km/h

  /// The ETA is a routed answer, so it is refreshed on a timer rather than on
  /// every fix - the car moves further than this is worth recomputing for.
  static const Duration _etaRefreshInterval = Duration(seconds: 30);
  DateTime? _etaRefreshedAt;
  bool _etaInFlight = false;
  String _lastEtaStatus = '';

  /// Removes this controller's reconnect listener on dispose.
  late final void Function() _removeConnectionListener;

  RideTrackingController(this.ref, this.rideId)
    : super(const RideTrackingState()) {
    _socket = ref.read(socketServiceProvider);
    _registerListeners();

    _removeConnectionListener = _socket.addConnectionListener(
      _handleReconnected,
    );

    _socket.joinRide(rideId);
    _loadRide();
    _startPolling();
  }

  void _handleReconnected() {
    _socket.joinRide(rideId);
    _loadRide();
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      final r = state.ride;
      if (r != null && (r.isCompleted || r.isCancelled)) {
        _pollingTimer?.cancel();
        return;
      }
      _loadRideSilently();
    });
  }

  /// Hands each ride update to the voice scheduler.
  ///
  /// Sits alongside the existing audio cue rather than inside it: the cue is a
  /// short sound tied to a status change, the announcements are a separate
  /// timeline driven by elapsed time and ETA. Wrapped because nothing about
  /// the voice feature may ever surface on the trip.
  void _notifyVoiceScheduler(RideModel? ride) {
    try {
      ref.read(rideVoiceSchedulerProvider).onRideUpdate(ride);
    } catch (_) {}
  }

  void _checkAudioTrigger(RideModel? ride) {
    if (ride == null) return;
    // A status change can flip which leg the ETA describes, so it is
    // recomputed straight away rather than waiting out the interval.
    if (_lastEtaStatus != '${ride.status}/${ride.liveStatus}') {
      _lastEtaStatus = '${ride.status}/${ride.liveStatus}';
      _etaRefreshedAt = null;
      unawaited(_refreshEta());
    }
    _notifyVoiceScheduler(ride);
    final status = ride.status.toLowerCase();
    final liveStatus = ride.liveStatus.toLowerCase();

    // No sound when the trip starts. The recorded "your ride has started,
    // wishing you a happy journey" clip was removed on request — the spoken
    // welcome announcement covers that moment instead, and stacking a jingle on
    // top of it meant two alerts for one event.
    if (status == 'completed' || liveStatus == 'completed') {
      AudioService.playRideEnded();
    }
  }

  /// Recomputes the ETA, at most once per [_etaRefreshInterval].
  ///
  /// Never awaited by its callers: an ETA arriving a moment late is fine,
  /// blocking a location frame on a network round trip is not.
  Future<void> _refreshEta() async {
    final ride = state.ride;
    if (ride == null || ride.isCompleted || ride.isCancelled) return;
    if (_etaInFlight) return;

    final last = _etaRefreshedAt;
    if (last != null && DateTime.now().difference(last) < _etaRefreshInterval) {
      return;
    }

    _etaInFlight = true;
    try {
      final minutes = await RideEtaService.remainingMinutes(ride);
      if (!mounted) return;
      _etaRefreshedAt = DateTime.now();
      state = minutes == null
          ? state.copyWith(clearEta: true)
          : state.copyWith(etaMinutes: minutes);
    } catch (_) {
      // No ETA is a valid thing to show; a wrong one is not.
    } finally {
      _etaInFlight = false;
    }
  }

  /// Re-applies the newest socket fix over a ride fetched from REST.
  ///
  /// The poll is authoritative about status and fare; the socket is
  /// authoritative about where the driver is right now.
  RideModel _withLiveLocation(RideModel ride) {
    final at = _liveDriverAt;
    final location = _liveDriverLocation;
    if (at == null || location == null) return ride;
    if (DateTime.now().difference(at) > _liveLocationTtl) return ride;
    return ride.copyWith(
      lastDriverLocation: location,
      lastDriverHeading: _liveDriverHeading,
      lastDriverAccuracy: _liveDriverAccuracy,
    );
  }

  Future<void> _loadRide() async {
    try {
      final ride = _withLiveLocation(
        await ref.read(rideRepositoryProvider).getRideById(rideId),
      );
      // The provider is autoDispose, so the rider can leave the screen while
      // this fetch is in flight; writing state after dispose throws.
      if (!mounted) return;
      state = state.copyWith(ride: ride, isLoading: false);
      _checkAudioTrigger(ride);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Re-reads the ride now - after the rider pays, say - without a spinner.
  Future<void> refresh() => _loadRideSilently();

  Future<void> _loadRideSilently() async {
    try {
      final ride = _withLiveLocation(
        await ref.read(rideRepositoryProvider).getRideById(rideId),
      );
      if (mounted) {
        state = state.copyWith(ride: ride);
        _checkAudioTrigger(ride);
      }
    } catch (_) {}
  }

  void _registerListeners() {
    // One registration per event. These used to be listed twice over - once
    // by constant, once by the identical string literal - and SocketService.on
    // does not deduplicate, so every location frame ran the handler twice and
    // restarted the marker's animation halfway through its own tween.
    // 'ride_status_updated' is a genuinely different name and stays.
    _socket.on(SocketEvents.rideState, _handleRideState);

    _socket.on(SocketEvents.rideStatusUpdated, _handleStatusUpdated);
    _socket.on('ride_status_updated', _handleStatusUpdated);
    _socket.on('driver_arrived', _handleDriverArrived);
    _socket.on('trip_started', _handleTripStarted);

    _socket.on(
      SocketEvents.rideDriverLocationUpdated,
      _handleDriverLocationUpdated,
    );

    _socket.on(SocketEvents.rideMessageNew, _handleNewMessage);
    _socket.on(SocketEvents.error, _handleSocketError);
  }

  void _handleRideState(dynamic data) {
    final map = _asMap(data);
    if (map == null) return;
    final payload = map['ride'] is Map
        ? Map<String, dynamic>.from(map['ride'])
        : map;
    if ((payload['rideId'] ?? payload['_id'] ?? payload['id'] ?? '')
            .toString() !=
        rideId)
      return;
    final ride = _withLiveLocation(RideModel.fromJson(payload));
    state = state.copyWith(ride: ride, isLoading: false);
    _checkAudioTrigger(ride);
  }

  void _handleDriverArrived(dynamic data) {
    final map = _asMap(data);
    if (map != null && (map['rideId'] ?? '').toString() != rideId) return;
    final ride = state.ride;
    if (ride != null) {
      // Only the live axis moves here. The server keeps `status` at
      // 'accepted' through arrival, so writing 'arrived' to it hid the Cancel
      // button until the next poll put it back.
      final updated = ride.copyWith(liveStatus: 'arrived');
      state = state.copyWith(ride: updated);
      _checkAudioTrigger(updated);
    }
    _loadRideSilently();
  }

  void _handleTripStarted(dynamic data) {
    final map = _asMap(data);
    if (map != null && (map['rideId'] ?? '').toString() != rideId) return;
    final ride = state.ride;
    if (ride != null) {
      // Live axis only, as in _handleDriverArrived; the next poll brings the
      // server's own `status`.
      final updated = ride.copyWith(liveStatus: 'started');
      state = state.copyWith(ride: updated);
      _checkAudioTrigger(updated);
    }
    _loadRideSilently();
  }

  void _handleStatusUpdated(dynamic data) {
    final map = _asMap(data);
    if (map == null) return;
    final id = (map['rideId'] ?? map['_id'] ?? map['id'] ?? '').toString();
    if (id.isNotEmpty && id != rideId) return;

    final ride = state.ride;
    if (ride == null) {
      _loadRide();
      return;
    }

    DateTime? parseDate(dynamic v) =>
        v == null ? null : DateTime.tryParse(v.toString());
    final updated = ride.copyWith(
      status: map['status']?.toString() ?? ride.status,
      liveStatus:
          map['liveStatus']?.toString() ??
          map['status']?.toString() ??
          ride.liveStatus,
      acceptedAt: parseDate(map['acceptedAt']) ?? ride.acceptedAt,
      arrivedAt: parseDate(map['arrivedAt']) ?? ride.arrivedAt,
      startedAt: parseDate(map['startedAt']) ?? ride.startedAt,
      completedAt: parseDate(map['completedAt']) ?? ride.completedAt,
      driver: map['driver'] is Map && (map['driver'] as Map).isNotEmpty
          ? RideDriverInfo.fromJson(Map<String, dynamic>.from(map['driver']))
          : ride.driver,
    );
    state = state.copyWith(ride: updated);
    _checkAudioTrigger(updated);
  }

  void _handleDriverLocationUpdated(dynamic data) {
    final map = _asMap(data);
    final ride = state.ride;
    if (map == null || ride == null) return;
    final id = (map['rideId'] ?? map['_id'] ?? map['id'] ?? '').toString();
    if (id.isNotEmpty && id != rideId) return;

    final coords = map['coordinates'];
    final double? lat;
    final double? lng;
    if (coords is List && coords.length >= 2) {
      lng = double.tryParse('${coords[0]}');
      lat = double.tryParse('${coords[1]}');
    } else {
      lat = double.tryParse('${map['lat'] ?? map['latitude'] ?? ''}');
      lng = double.tryParse('${map['lng'] ?? map['longitude'] ?? ''}');
    }
    if (lat == null || lng == null) return;

    final sequence = int.tryParse('${map['sequence'] ?? ''}');
    final timestampMs = int.tryParse('${map['timestamp'] ?? ''}');
    final accuracy = double.tryParse('${map['accuracy'] ?? ''}');
    final incoming = LatLngPoint(lat: lat, lng: lng);

    // LOCATION VALIDATION gate: a stale/out-of-order packet, or one
    // implying an impossible jump, is ignored outright rather than ever
    // being handed to the marker/route layers below.
    if (!_isNewerThanLastAccepted(
      sequence: sequence,
      timestampMs: timestampMs,
    )) {
      return;
    }
    if (_impliesImplausibleJump(incoming, timestampMs)) {
      return;
    }

    if (sequence != null) _lastAcceptedSequence = sequence;
    if (timestampMs != null) _lastAcceptedTimestampMs = timestampMs;

    _liveDriverLocation = incoming;
    _liveDriverHeading = double.tryParse('${map['heading'] ?? ''}');
    _liveDriverAccuracy = accuracy;
    _liveDriverAt = DateTime.now();

    state = state.copyWith(
      ride: ride.copyWith(
        lastDriverLocation: _liveDriverLocation,
        lastDriverHeading: _liveDriverHeading,
        lastDriverAccuracy: accuracy,
      ),
    );

    unawaited(_refreshEta());
  }

  /// True when [sequence] (preferred) or [timestampMs] is strictly greater
  /// than the last accepted value — the "latest valid location always wins"
  /// rule. A packet carrying neither (an older driver build) is always
  /// accepted, exactly as before this existed: there is nothing to compare
  /// it against.
  bool _isNewerThanLastAccepted({int? sequence, int? timestampMs}) {
    if (sequence != null && _lastAcceptedSequence != null) {
      return sequence > _lastAcceptedSequence!;
    }
    if (timestampMs != null && _lastAcceptedTimestampMs != null) {
      return timestampMs > _lastAcceptedTimestampMs!;
    }
    return true;
  }

  /// A fix that would require the driver to have travelled faster than
  /// [_implausibleSpeedMetersPerSecond] since the last accepted one is
  /// treated as a GPS glitch rather than a real position. The elapsed time
  /// is floored at one second so two fixes arriving close together in real
  /// time (a heartbeat resend right after a real fix) can't be misread as
  /// an extreme speed purely from a near-zero divisor.
  bool _impliesImplausibleJump(LatLngPoint incoming, int? timestampMs) {
    final previous = _liveDriverLocation;
    final previousAt = _liveDriverAt;
    if (previous == null || previousAt == null) return false;

    final elapsedSeconds =
        timestampMs != null && _lastAcceptedTimestampMs != null
        ? (timestampMs - _lastAcceptedTimestampMs!) / 1000
        : DateTime.now().difference(previousAt).inMilliseconds / 1000;
    final safeElapsedSeconds = elapsedSeconds < 1 ? 1.0 : elapsedSeconds;

    final distanceMeters = _distanceMetersBetween(previous, incoming);
    return (distanceMeters / safeElapsedSeconds) >
        _implausibleSpeedMetersPerSecond;
  }

  /// Small local haversine rather than importing the Google-Maps-flavoured
  /// one from route_geometry.dart — this controller has no Maps dependency
  /// by design (it's pure Riverpod/socket state), and pulling one in just
  /// for this would be a bigger change than the few lines of math below.
  double _distanceMetersBetween(LatLngPoint a, LatLngPoint b) {
    const earthRadiusMeters = 6371000.0;
    final lat1 = a.lat * math.pi / 180;
    final lat2 = b.lat * math.pi / 180;
    final dLat = (b.lat - a.lat) * math.pi / 180;
    final dLng = (b.lng - a.lng) * math.pi / 180;
    final h =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * earthRadiusMeters * math.asin(math.sqrt(h.clamp(0.0, 1.0)));
  }

  void _handleNewMessage(dynamic data) {
    final map = _asMap(data);
    final ride = state.ride;
    if (map == null || ride == null) return;
    if ((map['rideId'] ?? '').toString() != rideId) return;

    final message = RideMessageModel.fromJson(map);
    state = state.copyWith(
      ride: ride.copyWith(messages: [...ride.messages, message]),
    );
  }

  void _handleSocketError(dynamic data) {
    final map = _asMap(data);
    state = state.copyWith(
      error: map?['message']?.toString() ?? 'Something went wrong',
    );
  }

  Map<String, dynamic>? _asMap(dynamic data) {
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }

  /// Returns false when the socket is down. socket.io drops an emit made while
  /// disconnected, so the caller keeps the text instead of clearing it and
  /// pretending it was sent. A reconnect is kicked off either way.
  bool sendMessage(String message) {
    if (message.trim().isEmpty) return false;
    if (!_socket.isConnected) {
      _socket.ensureConnected();
      return false;
    }
    _socket.sendRideMessage(rideId, message.trim());
    return true;
  }

  /// Sends a chat message carrying an image (e.g. the rider's current-location
  /// photo), with an optional text caption.
  void sendImageMessage(String imageUrl, {String text = ''}) {
    if (imageUrl.trim().isEmpty) return;
    _socket.sendRideMessage(rideId, text.trim(), imageUrl: imageUrl.trim());
  }

  Future<bool> cancelRide({
    String? reason,
    String? reasonId,
    String? note,
  }) async {
    state = state.copyWith(isCancelling: true, clearError: true);
    try {
      await ref
          .read(rideRepositoryProvider)
          .cancelRide(rideId, reason: reason, reasonId: reasonId, note: note);
      // The home screen's ongoing-ride card is polled on a 15s cycle, so
      // without this the rider lands back on Home and still sees the trip they
      // just cancelled sitting there. Invalidating refetches straight away.
      ref.invalidate(myActiveRideProvider);
      try {
        ref
            .read(rideVoiceSchedulerProvider)
            .stopFor(rideId, reason: 'cancelled');
      } catch (_) {}
      state = state.copyWith(isCancelling: false);
      return true;
    } catch (e) {
      state = state.copyWith(isCancelling: false, error: e.toString());
      return false;
    }
  }

  Future<bool> submitReview({
    required int rating,
    String? comment,
    double tipAmount = 0,
  }) async {
    try {
      await ref
          .read(rideRepositoryProvider)
          .submitReview(
            rideId,
            rating: rating,
            comment: comment,
            tipAmount: tipAmount,
          );
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _socket.off(SocketEvents.rideState, _handleRideState);
    _socket.off(SocketEvents.rideStatusUpdated, _handleStatusUpdated);
    _socket.off('ride_status_updated', _handleStatusUpdated);
    _socket.off('driver_arrived', _handleDriverArrived);
    _socket.off('trip_started', _handleTripStarted);
    _socket.off(
      SocketEvents.rideDriverLocationUpdated,
      _handleDriverLocationUpdated,
    );
    _socket.off(SocketEvents.rideMessageNew, _handleNewMessage);
    _socket.off(SocketEvents.error, _handleSocketError);
    _removeConnectionListener();
    super.dispose();
  }
}

/// autoDispose because this controller owns a repeating timer and a set of
/// socket listeners. Without it, every ride ever tracked kept polling the API
/// for the rest of the session.
final rideTrackingControllerProvider = StateNotifierProvider.autoDispose
    .family<RideTrackingController, RideTrackingState, String>((ref, rideId) {
      return RideTrackingController(ref, rideId);
    });

import 'dart:developer' as developer;

import 'package:socket_io_client/socket_io_client.dart' as io;
import '../constants/api_constants.dart';
import 'socket_events.dart';

class SocketService {
  io.Socket? _socket;

  /// Retained so the socket can be rebuilt without going back through auth —
  /// [ensureConnected] is called from the FCM handler, which has no session
  /// context of its own.
  String? _token;

  /// Every handler registered through [on], replayed on each [connect].
  /// [disconnect] disposes the underlying socket, so without this a logout /
  /// login cycle would leave long-lived listeners (dispatch, active ride)
  /// attached to a dead socket and silently receiving nothing.
  final List<MapEntry<String, void Function(dynamic)>> _pendingHandlers = [];

  /// Fired after the transport comes back up, so callers can resync state that
  /// was pushed while the socket was down (pending ride offers, active trip).
  void Function()? onReconnected;

  bool get isConnected => _socket?.connected ?? false;

  void connect(String token) {
    if (_socket != null && _socket!.connected && _token == token) return;

    // A non-null but dead socket still owns its listeners and reconnect timers.
    // Replacing it without disposing leaked a socket per reconnect attempt, and
    // the orphans kept firing handlers against stale state.
    _socket?.dispose();

    _token = token;
    _socket = io.io(
      ApiConstants.socketUrl,
      io.OptionBuilder()
          // Polling is kept as a fallback, not removed as dead weight.
          // Websocket-only means one blocked Upgrade — a proxy, a captive
          // portal, some mobile carriers — leaves the driver with no socket at
          // all, and therefore no ride offers. Socket.IO opens on polling and
          // upgrades to websocket by itself the moment it can.
          .setTransports(['websocket', 'polling'])
          .disableAutoConnect()
          .enableReconnection()
          // Doubles each attempt from 1s up to a 30s ceiling (1, 2, 4, 8,
          // 16, 30, 30, ...), with +/-50% jitter so a mass reconnect after a
          // server restart doesn't land every driver's retry in the same
          // instant. Retries are unbounded on purpose — a driver mid-shift
          // should keep trying for as long as the app is open, not give up.
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(30000)
          .setRandomizationFactor(0.5)
          .setAuth({'token': token})
          .build(),
    );
    for (final entry in _pendingHandlers) {
      _socket!.on(entry.key, entry.value);
    }
    _socket!.onConnect((_) {
      developer.log('Socket connected', name: 'SocketService');
      onReconnected?.call();
    });

    // A silent handshake failure is what made a missing ride offer impossible
    // to diagnose: the REST calls all succeeded, so the app looked healthy
    // while the only channel carrying ride requests was never up.
    _socket!.onConnectError((error) {
      developer.log('Socket connect error: $error', name: 'SocketService');
    });
    _socket!.onError((error) {
      developer.log('Socket error: $error', name: 'SocketService');
    });
    _socket!.onDisconnect((reason) {
      developer.log('Socket disconnected: $reason', name: 'SocketService');
    });

    _socket!.connect();
  }

  /// Brings the transport back up if it has dropped. Safe to call repeatedly —
  /// a live socket is left untouched.
  ///
  /// Returns false when there is no session to reconnect with (logged out), so
  /// callers can skip any follow-up resync.
  bool ensureConnected() {
    final token = _token;
    if (token == null || token.isEmpty) return false;
    if (isConnected) return true;

    // `connect()` on a socket that is merely idle reuses it; one that was
    // disposed or is mid-backoff gets rebuilt by the token check above.
    if (_socket != null) {
      _socket!.connect();
    } else {
      connect(token);
    }
    return true;
  }

  /// Waits for the transport to actually come up after [ensureConnected].
  ///
  /// `ensureConnected` only starts the handshake. Emitting straight after it is
  /// usually fine — the client buffers packets until the socket opens — but an
  /// accept made from a cold start is the one emit that must not sit in that
  /// buffer while the offer expires, so callers wait for a real connection
  /// first. Returns false on timeout; the caller may still emit and rely on the
  /// buffer.
  Future<bool> waitUntilConnected({
    Duration timeout = const Duration(seconds: 6),
  }) async {
    if (isConnected) return true;

    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (isConnected) return true;
    }

    return false;
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _token = null;
  }

  /// Throttled by the server (~25m / 15s) — call while online but not on a ride.
  void sendLocationUpdate(double lat, double lng) {
    _socket?.emit(SocketEvents.locationUpdate, {
      'coordinates': [lng, lat],
    });
  }

  void acceptRide(String rideId) {
    _socket?.emit(SocketEvents.acceptRide, {'rideId': rideId});
  }

  void rejectRide(String rideId) {
    _socket?.emit(SocketEvents.rejectRide, {'rideId': rideId});
  }

  void submitRideBid(String rideId, num bidFare) {
    _socket?.emit(SocketEvents.submitRideBid, {
      'rideId': rideId,
      'bidFare': bidFare,
    });
  }

  void joinRide(String rideId) {
    _socket?.emit(SocketEvents.rideJoin, {'rideId': rideId});
  }

  void rejoinCurrentRide() {
    _socket?.emit(SocketEvents.rideRejoinCurrent);
  }

  /// Throttled by the server (~12m / 4s) — call while on an active ride.
  ///
  /// [timestampMs] is the GPS fix's own device time (not send time) and
  /// [sequence] a monotonically increasing counter for this ride — together
  /// they're what let the rider app tell a delayed/out-of-order packet apart
  /// from a genuinely newer one and refuse to let the marker jump backward.
  /// Both optional so this stays wire-compatible with anything still on an
  /// older payload shape.
  void sendRideLocationUpdate(
    String rideId,
    double lat,
    double lng, {
    double? heading,
    double? speed,
    double? accuracy,
    int? timestampMs,
    int? sequence,
  }) {
    _socket?.emit(SocketEvents.rideDriverLocationUpdate, {
      'rideId': rideId,
      'coordinates': [lng, lat],
      if (heading != null) 'heading': heading,
      if (speed != null) 'speed': speed,
      if (accuracy != null) 'accuracy': accuracy,
      if (timestampMs != null) 'timestamp': timestampMs,
      if (sequence != null) 'sequence': sequence,
    });
  }

  /// [otp] is required by the server when moving to `started` — it is the
  /// pickup code the rider reads out, and the server rejects the transition if
  /// it doesn't match.
  void updateRideStatus(
    String rideId,
    String status, {
    String? paymentMethod,
    String? otp,
    String? collectedVia,
  }) {
    _socket?.emit(SocketEvents.rideStatusUpdate, {
      'rideId': rideId,
      'status': status,
      if (paymentMethod != null) 'paymentMethod': paymentMethod,
      if (otp != null) 'otp': otp,
      if (collectedVia != null) 'collectedVia': collectedVia,
    });
  }

  void sendRideMessage(String rideId, String message, {String? imageUrl}) {
    _socket?.emit(SocketEvents.rideMessageSend, {
      'rideId': rideId,
      'message': message,
      if (imageUrl != null && imageUrl.isNotEmpty) 'imageUrl': imageUrl,
    });
  }

  void on(String event, void Function(dynamic data) handler) {
    _pendingHandlers.add(MapEntry(event, handler));
    _socket?.on(event, handler);
  }

  /// Pass the handler you registered — omitting it drops *every* listener for
  /// [event], which would unsubscribe unrelated controllers.
  void off(String event, [void Function(dynamic data)? handler]) {
    if (handler == null) {
      _pendingHandlers.removeWhere((entry) => entry.key == event);
      _socket?.off(event);
      return;
    }
    _pendingHandlers.removeWhere(
      (entry) => entry.key == event && entry.value == handler,
    );
    _socket?.off(event, handler);
  }
}

import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/services/route_api.dart';
import '../../data/models/ride_model.dart';
import '../data/ride_voice_log.dart';

/// How long the rider still has to go, in minutes.
///
/// Reuses the same server-side routing the map draws with, asking it for the
/// leg the driver is currently on. No second routing vendor, no extra key.
class RideEtaService {
  RideEtaService._();

  /// Short-lived memo so a burst of ETA checks (the tracking screen polls every
  /// 3s) does not hammer the router. Keyed on the rounded driver position, so
  /// it naturally expires as the car moves.
  static final Map<String, _CachedEta> _cache = {};
  static const Duration _cacheTtl = Duration(seconds: 45);

  /// Minutes until whatever the rider is currently waiting for.
  ///
  /// Which leg that is depends on the trip: before pickup it is the driver
  /// arriving, afterwards it is the rider reaching the drop. Routing to the
  /// drop the whole time - which this used to do - answered a question nobody
  /// was asking while the car was still on its way.
  ///
  /// Order of preference:
  ///  1. A live route from where the driver actually is.
  ///  2. The booking's own estimate, less the time already elapsed. Only
  ///     meaningful once the trip is running, so it is not offered before.
  ///
  /// Returning null is a real answer and the caller must honour it: showing or
  /// speaking a wrong number is worse than saying nothing.
  static Future<double?> remainingMinutes(RideModel ride) async {
    final target = ride.isUnderway
        ? LatLng(ride.drop.lat, ride.drop.lng)
        : LatLng(ride.pickup.lat, ride.pickup.lng);
    final driver = ride.lastDriverLocation;

    if (driver != null && (driver.lat != 0 || driver.lng != 0)) {
      final live = await _routeDurationMinutes(LatLng(driver.lat, driver.lng), target);
      if (live != null) return live;
    }

    return ride.isUnderway ? _estimateFromBooking(ride) : null;
  }

  /// Falls back to the distance/duration agreed at booking, wound forward by
  /// however long the trip has been running.
  static double? _estimateFromBooking(RideModel ride) {
    final total = ride.estimatedDurationMinutes;
    final startedAt = ride.startedAt;
    if (total <= 0 || startedAt == null) return null;

    final elapsed = DateTime.now().difference(startedAt).inSeconds / 60;
    final remaining = total - elapsed;

    // A trip running past its estimate is normal; a *negative* remaining time
    // is not something to announce, so clamp to a floor of one minute rather
    // than say "in -3 minutes".
    if (remaining <= 0) return null;
    return remaining;
  }

  static Future<double?> _routeDurationMinutes(LatLng from, LatLng to) async {
    final key = '${from.latitude.toStringAsFixed(3)},${from.longitude.toStringAsFixed(3)}'
        '_${to.latitude.toStringAsFixed(3)},${to.longitude.toStringAsFixed(3)}';

    final cached = _cache[key];
    if (cached != null && DateTime.now().difference(cached.at) < _cacheTtl) {
      return cached.minutes;
    }

    final result = await RouteApi.fetch(origin: from, destination: to);
    final minutes = result?.durationMinutes;

    if (minutes == null || minutes <= 0) {
      rideVoiceLog('Live ETA lookup failed, falling back to the booking estimate');
      return null;
    }

    _cache[key] = _CachedEta(minutes: minutes, at: DateTime.now());

    // Bounded so a long session cannot grow this without limit.
    if (_cache.length > 30) _cache.remove(_cache.keys.first);

    return minutes;
  }
}

class _CachedEta {
  final double minutes;
  final DateTime at;

  const _CachedEta({required this.minutes, required this.at});
}

import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../utils/polyline_decoder.dart';
import 'route_api.dart';

class RoutePolylineService {
  RoutePolylineService._();

  /// Decoded routes, so the same leg is not fetched twice.
  ///
  /// Bounded, and keyed on coordinates rounded to about a hundred metres. At
  /// full precision every driver position during a trip minted a new entry
  /// holding a whole polyline, and nothing ever evicted them.
  static final Map<String, List<LatLng>> _cache = {};
  static const int _cacheLimit = 40;

  static String _cacheKey(LatLng pickup, LatLng drop, List<LatLng> stops) {
    String at(LatLng p) =>
        '${p.latitude.toStringAsFixed(3)},${p.longitude.toStringAsFixed(3)}';
    return '${at(pickup)}_${stops.map(at).join('_')}_${at(drop)}';
  }

  static void _remember(String key, List<LatLng> points) {
    // Oldest out first; insertion order is what Dart's Map preserves.
    if (_cache.length >= _cacheLimit) _cache.remove(_cache.keys.first);
    _cache[key] = points;
  }

  /// Fetches an accurate road-following polyline for the given pickup, dropoff,
  /// and optional intermediate stops.
  static Future<List<LatLng>> getRoutePoints({
    required LatLng pickup,
    required LatLng drop,
    List<LatLng> stops = const [],
  }) async {
    final cacheKey = _cacheKey(pickup, drop, stops);

    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey]!;
    }

    final result = await RouteApi.fetch(
      origin: pickup,
      destination: drop,
      waypoints: stops,
    );

    if (result != null) {
      final points = PolylineDecoder.decode(result.polyline);
      if (points.isNotEmpty) {
        _remember(cacheKey, points);
        return points;
      }
    }

    // Nothing usable came back. A straight line is the honest placeholder:
    // it reads as provisional, where the old grid-shaped "road" path looked
    // like a real route and quietly put the driver marker on streets that do
    // not exist, because the marker is projected onto whatever is drawn.
    //
    // Deliberately NOT cached, so the next call retries the real route rather
    // than pinning this for the session.
    return _straightLine(pickup, drop, stops);
  }

  /// Cached points if the route has already been fetched, otherwise a straight
  /// line — used for the first frame, before the network call returns.
  static List<LatLng> getRoutePointsSync(LatLng pickup, LatLng drop, [List<LatLng> stops = const []]) {
    final cacheKey = _cacheKey(pickup, drop, stops);
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey]!;
    }
    return _straightLine(pickup, drop, stops);
  }

  /// Pickup, any stops, drop — joined directly. No invented turns.
  static List<LatLng> _straightLine(
    LatLng pickup,
    LatLng drop,
    List<LatLng> stops,
  ) => <LatLng>[pickup, ...stops, drop];
}

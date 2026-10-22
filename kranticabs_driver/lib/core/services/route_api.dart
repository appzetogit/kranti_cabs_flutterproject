import 'package:dio/dio.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../constants/api_constants.dart';
import '../storage/secure_storage_service.dart';

/// One road route, as the backend resolved it.
class RouteResult {
  final String polyline;
  final double distanceMeters;
  final double durationMinutes;

  /// Which provider answered — 'google' normally, 'osrm' if the Directions
  /// key lapses. Worth logging when a route looks wrong.
  final String provider;

  const RouteResult({
    required this.polyline,
    required this.distanceMeters,
    required this.durationMinutes,
    required this.provider,
  });
}

/// Road routes, resolved by our own backend.
///
/// This app used to call `router.project-osrm.org` directly — the public OSRM
/// demo server. It is unauthenticated, heavily rate-limited, and its usage
/// policy forbids production traffic. When it throttled us the map fell back
/// to drawing a synthetic path that follows no road at all, and because the
/// rider app fetched separately the two apps could end up drawing different
/// routes for the same trip.
///
/// The backend answers from the account's own Google Directions key, keeps
/// OSRM only as a fallback, and caches on coordinates rounded to about a
/// hundred metres — the same endpoint the rider app calls (`authenticate`
/// accepts both `user` and `driver` roles), so both apps draw one route.
class RouteApi {
  RouteApi._();

  /// Deliberately separate from the app's main client: routing is best-effort
  /// and must never trip the global 401 handler that signs the driver out.
  static final Dio _dio = Dio(
    BaseOptions(
      baseUrl: ApiConstants.baseUrl,
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 12),
    ),
  );

  /// Reads the same keychain entry the main client does, so this carries the
  /// driver's token without needing a `ref` at every call site.
  static final SecureStorageService _storage = SecureStorageService();

  static String _latLng(LatLng point) =>
      '${point.latitude.toStringAsFixed(6)},${point.longitude.toStringAsFixed(6)}';

  /// The road route between two points, or null when none could be resolved.
  ///
  /// Null is a real answer: the caller should keep whatever line it already
  /// has, or draw none, rather than invent one.
  static Future<RouteResult?> fetch({
    required LatLng origin,
    required LatLng destination,
    List<LatLng> waypoints = const [],
  }) async {
    try {
      final token = await _storage.readToken();

      final response = await _dio.get(
        ApiConstants.route,
        queryParameters: {
          'origin': _latLng(origin),
          'destination': _latLng(destination),
          if (waypoints.isNotEmpty) 'waypoints': waypoints.map(_latLng).join('|'),
        },
        options: Options(
          headers: {
            if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
          },
        ),
      );

      final body = response.data;
      final data = body is Map ? body['data'] : null;
      if (data is! Map) return null;

      final polyline = data['polyline']?.toString() ?? '';
      if (polyline.isEmpty) return null;

      return RouteResult(
        polyline: polyline,
        distanceMeters: (data['distanceMeters'] as num?)?.toDouble() ?? 0,
        durationMinutes: (data['durationMinutes'] as num?)?.toDouble() ?? 0,
        provider: data['provider']?.toString() ?? 'unknown',
      );
    } catch (_) {
      // Offline, rate limited, or both providers down. The caller decides what
      // to show; guessing a route here would be worse than showing none.
      return null;
    }
  }
}

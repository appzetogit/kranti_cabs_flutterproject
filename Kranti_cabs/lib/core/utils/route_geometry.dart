import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Great-circle distance in meters between two points.
double haversineMeters(LatLng a, LatLng b) {
  const earthRadiusMeters = 6371000.0;
  final lat1 = a.latitude * math.pi / 180;
  final lat2 = b.latitude * math.pi / 180;
  final dLat = (b.latitude - a.latitude) * math.pi / 180;
  final dLng = (b.longitude - a.longitude) * math.pi / 180;
  final h =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1) * math.cos(lat2) * math.sin(dLng / 2) * math.sin(dLng / 2);
  return 2 * earthRadiusMeters * math.asin(math.sqrt(h.clamp(0.0, 1.0)));
}

/// Compass bearing in degrees from [a] to [b] — 0 is north, clockwise.
double bearingBetween(LatLng a, LatLng b) {
  final lat1 = a.latitude * math.pi / 180;
  final lat2 = b.latitude * math.pi / 180;
  final dLng = (b.longitude - a.longitude) * math.pi / 180;
  final y = math.sin(dLng) * math.cos(lat2);
  final x =
      math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
  final bearing = math.atan2(y, x) * 180 / math.pi;
  return (bearing + 360) % 360;
}

/// Where a raw GPS fix actually sits relative to a route polyline.
class RouteProjection {
  /// The nearest point that is actually on the polyline.
  final LatLng point;

  /// How far [point] is from the start of the polyline, walking along it.
  /// This is what a marker's position "along the road" is animated against.
  final double distanceAlongRouteMeters;

  /// How far the raw fix itself is from the polyline — near zero while the
  /// driver is following the drawn road, growing if they turn off it.
  final double distanceFromRouteMeters;

  const RouteProjection({
    required this.point,
    required this.distanceAlongRouteMeters,
    required this.distanceFromRouteMeters,
  });
}

/// Finds the closest point on [polyline] to [fix] and how far along the route
/// (from its start) that point is.
///
/// Each segment is checked with a flat-earth projection local to that
/// segment — OSRM polyline segments are short enough (tens of metres) that
/// curvature is negligible, so this avoids real geodesic math per segment for
/// what is ultimately just picking the closest one and where on it.
RouteProjection? projectOntoPolyline(LatLng fix, List<LatLng> polyline) {
  if (polyline.length < 2) return null;

  double bestDistance = double.infinity;
  LatLng bestPoint = polyline.first;
  double bestDistanceAlong = 0;
  double walked = 0;

  for (var i = 0; i < polyline.length - 1; i++) {
    final segStart = polyline[i];
    final segEnd = polyline[i + 1];
    final segLength = haversineMeters(segStart, segEnd);

    final projection = _projectOntoSegment(fix, segStart, segEnd);
    if (projection.distanceMeters < bestDistance) {
      bestDistance = projection.distanceMeters;
      bestPoint = projection.point;
      bestDistanceAlong = walked + (projection.t * segLength);
    }
    walked += segLength;
  }

  return RouteProjection(
    point: bestPoint,
    distanceAlongRouteMeters: bestDistanceAlong,
    distanceFromRouteMeters: bestDistance,
  );
}

class _SegmentProjection {
  final LatLng point;
  final double t;
  final double distanceMeters;
  const _SegmentProjection(this.point, this.t, this.distanceMeters);
}

_SegmentProjection _projectOntoSegment(
  LatLng point,
  LatLng segStart,
  LatLng segEnd,
) {
  // Local metre-scale plane centred on segStart — fine at segment scale.
  final latRad = segStart.latitude * math.pi / 180;
  const metersPerDegreeLat = 111320.0;
  final metersPerDegreeLng = metersPerDegreeLat * math.cos(latRad);

  double toX(LatLng p) =>
      (p.longitude - segStart.longitude) * metersPerDegreeLng;
  double toY(LatLng p) => (p.latitude - segStart.latitude) * metersPerDegreeLat;

  final ex = toX(segEnd);
  final ey = toY(segEnd);
  final px = toX(point);
  final py = toY(point);

  final segLenSq = (ex * ex) + (ey * ey);
  final t = segLenSq <= 0
      ? 0.0
      : (((px * ex) + (py * ey)) / segLenSq).clamp(0.0, 1.0);

  final closestX = ex * t;
  final closestY = ey * t;
  final dx = px - closestX;
  final dy = py - closestY;
  final distanceMeters = math.sqrt((dx * dx) + (dy * dy));

  final closestLat = segStart.latitude + (closestY / metersPerDegreeLat);
  final closestLng = segStart.longitude + (closestX / metersPerDegreeLng);

  return _SegmentProjection(LatLng(closestLat, closestLng), t, distanceMeters);
}

/// Walks [polyline] to find the point [distanceMeters] along it from the
/// start, clamping to either end.
LatLng pointAtDistanceAlongPolyline(
  List<LatLng> polyline,
  double distanceMeters,
) {
  if (polyline.isEmpty) return const LatLng(0, 0);
  if (polyline.length == 1 || distanceMeters <= 0) return polyline.first;

  double walked = 0;
  for (var i = 0; i < polyline.length - 1; i++) {
    final segStart = polyline[i];
    final segEnd = polyline[i + 1];
    final segLength = haversineMeters(segStart, segEnd);
    if (walked + segLength >= distanceMeters) {
      final t = segLength <= 0
          ? 0.0
          : ((distanceMeters - walked) / segLength).clamp(0.0, 1.0);
      return LatLng(
        segStart.latitude + (segEnd.latitude - segStart.latitude) * t,
        segStart.longitude + (segEnd.longitude - segStart.longitude) * t,
      );
    }
    walked += segLength;
  }
  return polyline.last;
}

import 'package:google_maps_flutter/google_maps_flutter.dart';

/// How busy an area is, as the server judged it.
///
/// Thresholds stay on the server; the app only colours what it is told.
enum DemandIntensity { normal, high, veryHigh }

DemandIntensity demandIntensityFrom(String? raw) {
  switch ((raw ?? '').toLowerCase()) {
    case 'very_high':
      return DemandIntensity.veryHigh;
    case 'high':
      return DemandIntensity.high;
    default:
      return DemandIntensity.normal;
  }
}

double _d(dynamic v, [double fallback = 0]) => double.tryParse('${v ?? ''}') ?? fallback;
int _i(dynamic v) => int.tryParse('${v ?? ''}') ?? 0;
double? _dOrNull(dynamic v) => v == null ? null : double.tryParse('$v');

LatLng? _latLng(dynamic raw) {
  if (raw is! Map) return null;
  final lat = double.tryParse('${raw['lat']}');
  final lng = double.tryParse('${raw['lng']}');
  if (lat == null || lng == null) return null;
  return LatLng(lat, lng);
}

/// One hexagon that is surging, busy, or both.
///
/// The multiplier is the very value rider quotes use - it is shown as sent and
/// never recomputed or rounded differently here.
class OpportunityCell {
  final String hex;
  final LatLng center;
  final List<LatLng> boundary;
  final double multiplier;
  final DateTime? surgeEndsAt;
  final int surgeEndsInMinutes;
  final DemandIntensity demand;
  final int riders;
  final int freeDrivers;
  final double? distanceKm;
  final String label;

  const OpportunityCell({
    required this.hex,
    required this.center,
    required this.boundary,
    required this.multiplier,
    required this.surgeEndsAt,
    required this.surgeEndsInMinutes,
    required this.demand,
    required this.riders,
    required this.freeDrivers,
    required this.distanceKm,
    required this.label,
  });

  bool get isSurging => multiplier > 1;

  /// Null for a cell that cannot be drawn, so one bad entry is skipped rather
  /// than losing the whole map.
  static OpportunityCell? fromJson(Map<String, dynamic> json) {
    final center = _latLng(json['center']);
    final ring = (json['boundary'] as List?)?.map(_latLng).whereType<LatLng>().toList() ?? const <LatLng>[];
    if (center == null || ring.length < 3) return null;

    return OpportunityCell(
      hex: '${json['hex'] ?? ''}',
      center: center,
      boundary: ring,
      multiplier: _d(json['multiplier'], 1),
      surgeEndsAt: DateTime.tryParse('${json['surge_ends_at'] ?? ''}'),
      surgeEndsInMinutes: _i(json['surge_ends_in_minutes']),
      demand: demandIntensityFrom(json['demand_level']?.toString()),
      riders: _i(json['demand']),
      freeDrivers: _i(json['free_drivers']),
      distanceKm: _dOrNull(json['distance_km']),
      label: '${json['label'] ?? ''}'.trim(),
    );
  }
}

/// What a typical trip pays in this driver's own vehicle, normally and now.
class ExampleFare {
  final double km;
  final int normal;
  final int now;
  final String vehicle;

  const ExampleFare({required this.km, required this.normal, required this.now, required this.vehicle});

  int get extra => now - normal;

  static ExampleFare? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final normal = _i(raw['normal']);
    if (normal <= 0) return null;
    return ExampleFare(
      km: _d(raw['km'], 5),
      normal: normal,
      now: _i(raw['now']),
      vehicle: '${raw['vehicle'] ?? ''}',
    );
  }
}

/// One of the few best places to go - drives "Go to".
class Hotspot {
  final String hex;
  final String title;
  final LatLng center;
  final double multiplier;
  final int surgeEndsInMinutes;
  final DemandIntensity demand;
  final double? distanceKm;
  final ExampleFare? exampleFare;

  const Hotspot({
    required this.hex,
    required this.title,
    required this.center,
    required this.multiplier,
    required this.surgeEndsInMinutes,
    required this.demand,
    required this.distanceKm,
    required this.exampleFare,
  });

  bool get isSurging => multiplier > 1;

  static Hotspot? fromJson(Map<String, dynamic> json) {
    final center = _latLng(json['center']);
    if (center == null) return null;
    return Hotspot(
      hex: '${json['hex'] ?? ''}',
      title: '${json['title'] ?? ''}'.trim(),
      center: center,
      multiplier: _d(json['multiplier'], 1),
      surgeEndsInMinutes: _i(json['surge_ends_in_minutes']),
      demand: demandIntensityFrom(json['demand_level']?.toString()),
      distanceKm: _dOrNull(json['distance_km']),
      exampleFare: ExampleFare.fromJson(json['example_fare']),
    );
  }
}

/// Demand at an airport, shown even when it is far away: airport queues are a
/// common reason to relocate.
class AirportDemand {
  final String name;
  final LatLng position;
  final DemandIntensity demand;
  final double multiplier;
  final double? distanceKm;

  const AirportDemand({
    required this.name,
    required this.position,
    required this.demand,
    required this.multiplier,
    required this.distanceKm,
  });

  static AirportDemand? fromJson(Map<String, dynamic> json) {
    final lat = double.tryParse('${json['lat']}');
    final lng = double.tryParse('${json['lng']}');
    if (lat == null || lng == null) return null;
    return AirportDemand(
      name: '${json['name'] ?? 'Airport'}',
      position: LatLng(lat, lng),
      demand: demandIntensityFrom(json['demand_level']?.toString()),
      multiplier: _d(json['multiplier'], 1),
      distanceKm: _dOrNull(json['distance_km']),
    );
  }
}

/// One response from GET /drivers/opportunity-map.
class OpportunityMap {
  final List<OpportunityCell> cells;
  final List<Hotspot> hotspots;
  final List<AirportDemand> airports;
  final bool surgeEnabled;
  final double maxMultiplier;
  final int refreshAfterSeconds;

  /// When the server built this, and when the phone received it. Countdowns
  /// use the difference so a phone clock that is off does not make a surge
  /// look longer or shorter than it is.
  final DateTime serverTime;
  final DateTime receivedAt;

  const OpportunityMap({
    required this.cells,
    required this.hotspots,
    required this.airports,
    required this.surgeEnabled,
    required this.maxMultiplier,
    required this.refreshAfterSeconds,
    required this.serverTime,
    required this.receivedAt,
  });

  static OpportunityMap empty() {
    final now = DateTime.now();
    return OpportunityMap(
      cells: const [],
      hotspots: const [],
      airports: const [],
      surgeEnabled: false,
      maxMultiplier: 1,
      refreshAfterSeconds: 60,
      serverTime: now,
      receivedAt: now,
    );
  }

  factory OpportunityMap.fromJson(Map<String, dynamic> json) {
    List<T> list<T>(String key, T? Function(Map<String, dynamic>) parse) =>
        (json[key] as List?)
            ?.whereType<Map>()
            .map((e) => parse(Map<String, dynamic>.from(e)))
            .whereType<T>()
            .toList() ??
        <T>[];

    final received = DateTime.now();
    return OpportunityMap(
      cells: list<OpportunityCell>('cells', OpportunityCell.fromJson),
      hotspots: list<Hotspot>('hotspots', Hotspot.fromJson),
      airports: list<AirportDemand>('airports', AirportDemand.fromJson),
      surgeEnabled: json['surge_enabled'] == true,
      maxMultiplier: _d(json['max_multiplier'], 1),
      refreshAfterSeconds: _i(json['refresh_after_seconds']) == 0 ? 60 : _i(json['refresh_after_seconds']),
      serverTime: DateTime.tryParse('${json['refreshed_at'] ?? ''}') ?? received,
      receivedAt: received,
    );
  }

  /// The phone's own time for a server timestamp.
  DateTime toLocalClock(DateTime serverInstant) => serverInstant.add(receivedAt.difference(serverTime));

  Hotspot? get best => hotspots.isEmpty ? null : hotspots.first;
}

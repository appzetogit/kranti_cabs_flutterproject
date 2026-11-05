import '../../../core/network/api_client.dart';
import 'hourly_rental.dart';

class HourlyRentalRepository {
  final ApiClient api;
  HourlyRentalRepository(this.api);

  /// Packages and their cabs for a pickup (city prices can differ). Needs no
  /// login. The list is `results` at the top level, or inside `data`.
  Future<List<HourlyRentalPackage>> packages({double? lat, double? lng}) async {
    final data = await api.get('/users/hourly-rental-packages', query: {
      if (lat != null && lng != null) 'lat': lat.toStringAsFixed(4),
      if (lat != null && lng != null) 'lng': lng.toStringAsFixed(4),
    });
    final map = data is Map ? data : const {};
    final raw = map['results'] ?? (map['data'] is Map ? (map['data'] as Map)['results'] : null);
    return ((raw as List?) ?? const [])
        .whereType<Map>()
        .map((p) => HourlyRentalPackage.fromJson(Map<String, dynamic>.from(p)))
        .where((p) => p.id.isNotEmpty && p.vehicles.isNotEmpty)
        .toList();
  }
}

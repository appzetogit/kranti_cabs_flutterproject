import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import 'opportunity_models.dart';

/// Reads the surge & demand map for the area around the driver.
///
/// Uses the app's existing [ApiClient], so authentication, base URL and error
/// unwrapping all come from the same place as every other call.
///
/// This used to read /drivers/heatmap, which showed demand on a square grid
/// and never the fare hike. /drivers/opportunity-map puts both on the surge
/// engine's own hexagons, so a "1.3x" drawn here is exactly what riders in
/// that area are quoted. The old endpoint stays up for older app builds.
class HeatmapRepository {
  final ApiClient _api;

  HeatmapRepository(this._api);

  Future<OpportunityMap> getOpportunityMap({
    required double lat,
    required double lng,
    double radiusKm = 8,
  }) async {
    final data = await _api.get(ApiConstants.driverOpportunityMap, query: {
      'lat': lat,
      'lng': lng,
      'radius_km': radiusKm,
    });

    final map = data is Map ? Map<String, dynamic>.from(data) : const <String, dynamic>{};
    return OpportunityMap.fromJson(map);
  }
}

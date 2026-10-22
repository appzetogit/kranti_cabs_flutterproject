import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import 'models/promo_model.dart';

class PromoRepository {
  final ApiClient api;

  PromoRepository(this.api);

  Future<List<PromoModel>> getAvailablePromos() async {
    final data = await api.get(ApiConstants.promoAvailable);
    final results = (data is Map ? (data['results'] ?? data['promos']) : data) as List? ?? [];
    return results.map((e) => PromoModel.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  /// Asks the server whether [code] applies to a ride of [fare] starting at
  /// the pickup. The pickup lets the server work out which city's offers
  /// count, since the app has no service-location id of its own.
  Future<Map<String, dynamic>> validatePromo({
    required String code,
    required double fare,
    double? lat,
    double? lng,
  }) async {
    final data = await api.post(ApiConstants.promoValidate, data: {
      'code': code,
      'fare': fare,
      'transport_type': 'taxi',
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
    });
    return Map<String, dynamic>.from(data as Map);
  }
}

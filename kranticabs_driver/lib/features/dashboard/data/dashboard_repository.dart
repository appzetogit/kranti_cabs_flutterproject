import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../../auth/data/driver_model.dart';

class DashboardRepository {
  final ApiClient _api;

  DashboardRepository(this._api);

  Future<String> uploadSelfie(String dataUrl) async {
    final data = await _api.post(ApiConstants.uploadImage, data: {
      'image': dataUrl,
      'folder': 'driver-selfies',
    });
    return Map<String, dynamic>.from(data as Map)['url'] as String;
  }

  Future<DriverModel> goOnline(double lat, double lng, {String? selfieImageUrl}) async {
    final data = await _api.patch(ApiConstants.goOnline, data: {
      'location': [lng, lat],
      if (selfieImageUrl != null) 'selfieImageUrl': selfieImageUrl,
    });
    return DriverModel.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<DriverModel> goOffline() async {
    final data = await _api.patch(ApiConstants.goOffline);
    return DriverModel.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<Map<String, dynamic>?> getActiveRide() async {
    final data = await _api.get(ApiConstants.activeRide);
    if (data == null) return null;
    return Map<String, dynamic>.from(data as Map);
  }
}

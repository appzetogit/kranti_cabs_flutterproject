import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import 'destination_mode.dart';

class DestinationRepository {
  final ApiClient _api;

  DestinationRepository(this._api);

  DestinationModeInfo _parse(dynamic data) =>
      data is Map ? DestinationModeInfo.fromJson(Map<String, dynamic>.from(data)) : DestinationModeInfo.none;

  Future<DestinationModeInfo> get() async => _parse(await _api.get(ApiConstants.destinationMode));

  /// Turns Go Home on. The server plans the route from the driver's live
  /// location, so the driver should be online with GPS on.
  Future<DestinationModeInfo> goHome() async =>
      _parse(await _api.put(ApiConstants.destinationMode, data: {'enabled': true, 'useHome': true}));

  /// Heads somewhere other than home.
  Future<DestinationModeInfo> goTo({required double lat, required double lng, String label = ''}) async =>
      _parse(await _api.put(ApiConstants.destinationMode, data: {'enabled': true, 'lat': lat, 'lng': lng, 'label': label}));

  Future<DestinationModeInfo> turnOff() async =>
      _parse(await _api.put(ApiConstants.destinationMode, data: {'enabled': false}));

  /// Saves home. Any time, unless the admin set a waiting period
  /// (`HOME_CHANGE_TOO_SOON`).
  Future<DestinationModeInfo> setHome({required double lat, required double lng, required String address}) async =>
      _parse(await _api.put(ApiConstants.homeLocation, data: {'lat': lat, 'lng': lng, 'address': address}));
}

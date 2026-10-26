import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import 'scheduled_ride.dart';

class ScheduledRidesRepository {
  final ApiClient _api;

  ScheduledRidesRepository(this._api);

  /// Open scheduled rides for this driver's vehicle and city, and their own,
  /// soonest first.
  Future<List<ScheduledRide>> list() async {
    final data = await _api.get(ApiConstants.scheduledRides, query: {'limit': 50});
    final results = data is Map ? (data['results'] as List? ?? const []) : const [];
    return results
        .whereType<Map>()
        .map((e) => ScheduledRide.fromJson(Map<String, dynamic>.from(e)))
        .where((ride) => ride.rideId.isNotEmpty && ride.scheduledAt != null)
        .toList()
      ..sort((a, b) => a.scheduledAt!.compareTo(b.scheduledAt!));
  }

  /// Takes an open scheduled ride now. Refused if another driver took it
  /// first ("Ride is no longer available for acceptance") or it clashes with
  /// one of this driver's other scheduled rides.
  Future<void> accept(String rideId) => _api.post(ApiConstants.acceptRideOffer(rideId));

  /// Gives back one of the driver's own scheduled rides; the rider is told.
  Future<void> cancel(String rideId) => _api.post(ApiConstants.cancelScheduledRide(rideId));
}

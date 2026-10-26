import 'dart:convert';
import 'dart:io';
import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import 'models/cancellation_reason_model.dart';
import '../../../core/utils/json_safe.dart';
import 'models/bidding_settings_model.dart';
import 'models/ride_bid_model.dart';
import 'models/ride_model.dart';

class RideRepository {
  final ApiClient api;

  RideRepository(this.api);

  /// Uploads a chat image (e.g. the rider's current-location photo) and returns
  /// the hosted URL to attach to a chat message.
  Future<String> uploadChatImage(File file) async {
    final bytes = await file.readAsBytes();
    final data = await api.post(
      ApiConstants.uploadImage,
      data: {
        'image': 'data:image/jpeg;base64,${base64Encode(bytes)}',
        'folder': 'ride-chat',
      },
    );
    final result = asMap(data);
    final url = asText(result['url']);
    return url.isNotEmpty ? url : asText(result['secureUrl']);
  }

  Future<RideModel> createRide({
    required List<double> pickup,
    required List<double> drop,
    required String pickupAddress,
    required String dropAddress,
    List<Map<String, dynamic>> stops = const [],
    required double fare,
    required double estimatedDistanceMeters,
    required double estimatedDurationMinutes,
    required String vehicleTypeId,
    String paymentMethod = 'cash',
    String serviceType = 'ride',
    String? promoCode,
    String? zoneId,
    String? serviceLocationId,
    DateTime? scheduledAt,
    /// Intercity details for an outstation booking  `tripType`, `fromCity`,
    /// `toCity` and friends, stored on `Ride.intercity` by the backend.
    Map<String, dynamic>? intercity,
    /// 'bidding' to open the ride for negotiation, anything else for a fixed
    /// fare. The server ignores it unless the chosen vehicle allows bidding.
    String? bookingMode,
    /// The most the rider is willing to pay. Only meaningful for an outstation
    /// bidding ride, where it caps what drivers may ask; the server clamps it
    /// into the admin-configured band regardless.
    double? userMaxBidFare,
    /// The platform fee included in [fare], paid to admin at settlement.
    double? platformFee,
    /// The demand surge [fare] was priced under; already included in it.
    double? surgeMultiplier,
  }) async {
    final data = await api.post(ApiConstants.rides, data: {
      'pickup': pickup,
      'drop': drop,
      'pickupAddress': pickupAddress,
      'dropAddress': dropAddress,
      if (stops.isNotEmpty) 'stops': stops,
      'fare': fare,
      if (platformFee != null && platformFee > 0) 'platformFee': platformFee,
      if (surgeMultiplier != null && surgeMultiplier > 1) 'surgeMultiplier': surgeMultiplier,
      'estimatedDistanceMeters': estimatedDistanceMeters,
      'estimatedDurationMinutes': estimatedDurationMinutes,
      'vehicleTypeId': vehicleTypeId,
      'paymentMethod': paymentMethod,
      'serviceType': serviceType,
      if (promoCode != null && promoCode.isNotEmpty) 'promo_code': promoCode,
      ?zoneId: zoneId,
      ?serviceLocationId: serviceLocationId,
      // Outstation rides are still taxi transport; `serviceType` is what marks
      // them as intercity.
      'transport_type': 'taxi',
      if (intercity != null && intercity.isNotEmpty) 'intercity': intercity,
      if (scheduledAt != null) 'scheduledAt': scheduledAt.toUtc().toIso8601String(),
      if (bookingMode != null && bookingMode.isNotEmpty) 'bookingMode': bookingMode,
      if (userMaxBidFare != null && userMaxBidFare > 0) 'userMaxBidFare': userMaxBidFare,
    });
    return RideModel.fromJson(Map<String, dynamic>.from(data['ride'] ?? {}));
  }

  /// The admin's negotiation bands.
  ///
  /// Needed before a ride exists, while the rider is still deciding whether to
  /// name their own price, which is why it is not read off the ride.
  Future<BiddingSettings> getBiddingSettings() async {
    final data = await api.get('${ApiConstants.rides}/app-settings/bidding');
    return BiddingSettings.fromJson(data);
  }

  /// Every bid drivers have placed on a bidding ride, cheapest first.
  ///
  /// Returns the ride too, because its ceiling moves as the rider raises it and
  /// the bid list is meaningless without the band it sits in.
  Future<({RideModel ride, List<RideBidModel> bids})> getRideBids(String rideId) async {
    final data = asMap(await api.get('${ApiConstants.rides}/$rideId/bids'));

    return (
      ride: RideModel.fromJson(asMap(data['ride'])),
      bids: asList(data['bids']).map(RideBidModel.fromJson).toList(growable: false),
    );
  }

  /// Raises what the rider will pay by [steps] increments.
  ///
  /// Serves both negotiation modes: for an outstation bidding ride it lifts the
  /// ceiling drivers may bid up to, and for a city ride it raises the fare
  /// itself and re-runs dispatch.
  Future<RideModel> raiseFare(String rideId, {int steps = 1}) async {
    final data = await api.patch(
      '${ApiConstants.rides}/$rideId/bids/ceiling',
      data: {'incrementSteps': steps},
    );
    return RideModel.fromJson(asMap(asMap(data)['ride'] ?? data));
  }

  /// Awards the ride to one driver's bid. The ride's fare becomes that bid.
  Future<RideModel> acceptBid({required String rideId, required String bidId}) async {
    final data = await api.post('${ApiConstants.rides}/$rideId/bids/$bidId/accept');
    return RideModel.fromJson(asMap(asMap(data)['ride'] ?? data));
  }

  Future<RideModel?> getMyActiveRide() async {
    final data = await api.get(ApiConstants.activeRide);
    if (data == null) return null;
    return RideModel.fromJson(Map<String, dynamic>.from(data));
  }

  Future<RideModel> getRideById(String rideId) async {
    final data = await api.get('${ApiConstants.rides}/$rideId');
    return RideModel.fromJson(Map<String, dynamic>.from(data));
  }

  Future<Map<String, dynamic>> listMyRides({int page = 1, int limit = 20, String? category}) async {
    final data = await api.get(ApiConstants.rides, query: {
      'page': page,
      'limit': limit,
      ?category: category,
    });
    return Map<String, dynamic>.from(data);
  }

  Future<void> cancelRide(
    String rideId, {
    String? reason,
    String? reasonId,
    String? note,
  }) {
    String? nonEmpty(String? v) => (v ?? '').trim().isEmpty ? null : v!.trim();
    // "Other" carries only the typed note; the server records that as the reason.
    final isOther = reasonId == 'other';
    return api.patch('${ApiConstants.rides}/$rideId/cancel', data: <String, dynamic>{
      'reasonId': ?nonEmpty(reasonId),
      if (!isOther) 'reason': ?nonEmpty(reason),
      'note': ?nonEmpty(note),
    });
  }

  /// Reasons the admin has configured for riders. Empty on failure — cancelling
  /// must never be blocked by the list failing to load.
  Future<List<CancellationReasonModel>> getCancellationReasons(String stage) async {
    try {
      final data = await api.get(ApiConstants.cancellationReasons, query: {'audience': 'user', 'stage': stage});
      final map = data is Map ? Map<String, dynamic>.from(data) : const <String, dynamic>{};
      final results = map['results'] as List? ?? const [];
      return results
          .map((e) => CancellationReasonModel.fromJson(Map<String, dynamic>.from(e as Map)))
          .where((e) => e.id.isNotEmpty && e.title.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> submitReview(String rideId, {required int rating, String? comment, double tipAmount = 0}) {
    return api.patch('${ApiConstants.rides}/$rideId/feedback', data: {
      'rating': rating,
      ?comment: comment,
      'tipAmount': tipAmount,
    });
  }

  Future<List<Map<String, dynamic>>> getAvailableDrivers({
    required double lat,
    required double lng,
    double? maxDistance,
  }) async {
    final data = await api.get(ApiConstants.availableDrivers, query: {
      'lat': lat,
      'lng': lng,
      if (maxDistance != null) 'maxDistance': maxDistance,
    });
    // The endpoint returns `{ totalDrivers, drivers: [...] }`  reading
    // `results` here silently yielded an empty list.
    final results = (data is Map ? (data['drivers'] ?? data['results']) : data) as List? ?? [];
    return results.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<Map<String, dynamic>> createTipOrder(String rideId, double amount) async {
    final data = await api.post('${ApiConstants.rides}/$rideId/tip/razorpay/order', data: {'amount': amount});
    return Map<String, dynamic>.from(data);
  }

  Future<void> verifyTipPayment(String rideId, Map<String, dynamic> payload) {
    return api.post('${ApiConstants.rides}/$rideId/tip/razorpay/verify', data: payload);
  }

  /// Pays a cash ride's fare online (Razorpay) instead of the driver's UPI.
  Future<Map<String, dynamic>> createFareOrder(String rideId) async {
    final data = await api.post('${ApiConstants.rides}/$rideId/fare-payment/razorpay/order');
    return Map<String, dynamic>.from(data);
  }

  Future<void> verifyFarePayment(String rideId, Map<String, dynamic> payload) {
    return api.post('${ApiConstants.rides}/$rideId/fare-payment/razorpay/verify', data: payload);
  }

  Future<Map<String, dynamic>> createCompletionOrder(String rideId) async {
    final data = await api.post('${ApiConstants.rides}/$rideId/complete-payment/razorpay/order');
    return Map<String, dynamic>.from(data);
  }

  Future<void> verifyCompletionPayment(String rideId, Map<String, dynamic> payload) {
    return api.post('${ApiConstants.rides}/$rideId/complete-payment/razorpay/verify', data: payload);
  }

  Future<void> payCompletionWithWallet(String rideId) {
    return api.post('${ApiConstants.rides}/$rideId/complete-payment/wallet');
  }
}

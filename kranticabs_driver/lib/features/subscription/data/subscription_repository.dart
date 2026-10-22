import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import 'subscription_model.dart';

class SubscriptionRepository {
  final ApiClient _api;

  SubscriptionRepository(this._api);

  Future<SubscriptionStatus> getStatus() async {
    final data = await _api.get(ApiConstants.subscriptionStatus);
    return SubscriptionStatus.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<SubscriptionPurchaseResult> purchase({
    required String planId,
    required String paymentMethod,
  }) async {
    final data = await _api.post(ApiConstants.subscriptionPurchase, data: {
      'planId': planId,
      'paymentMethod': paymentMethod,
    });
    return SubscriptionPurchaseResult.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<List<SubscriptionHistoryItem>> getHistory({int limit = 30}) async {
    final data = await _api.get(ApiConstants.subscriptionHistory, query: {'limit': limit});
    final list = data is List
        ? data
        : (data is Map && data['history'] is List)
            ? data['history'] as List
            : const [];
    return list
        .map((e) => SubscriptionHistoryItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }
}

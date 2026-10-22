import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import 'models/subscription_plan_model.dart';

class SubscriptionRepository {
  final ApiClient api;

  SubscriptionRepository(this.api);

  Future<List<SubscriptionPlanModel>> getPlans() async {
    final data = await api.get(ApiConstants.subscriptionPlans);
    final results = (data['results'] as List? ?? []);
    return results.map((e) => SubscriptionPlanModel.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<SubscriptionSummaryModel> getMySummary() async {
    final data = await api.get(ApiConstants.mySubscriptions);
    return SubscriptionSummaryModel.fromJson(Map<String, dynamic>.from(data));
  }

  Future<UserSubscriptionModel> purchase(String planId) async {
    final data = await api.post(ApiConstants.buySubscription, data: {'planId': planId});
    return UserSubscriptionModel.fromJson(Map<String, dynamic>.from(data['subscription'] ?? {}));
  }
}

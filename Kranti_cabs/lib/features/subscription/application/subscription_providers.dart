import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/core_providers.dart';
import '../data/models/subscription_plan_model.dart';
import '../data/subscription_repository.dart';

final subscriptionRepositoryProvider = Provider<SubscriptionRepository>((ref) {
  return SubscriptionRepository(ref.watch(apiClientProvider));
});

final subscriptionPlansProvider = FutureProvider.autoDispose<List<SubscriptionPlanModel>>((ref) {
  return ref.watch(subscriptionRepositoryProvider).getPlans();
});

final mySubscriptionSummaryProvider = FutureProvider.autoDispose<SubscriptionSummaryModel>((ref) {
  return ref.watch(subscriptionRepositoryProvider).getMySummary();
});

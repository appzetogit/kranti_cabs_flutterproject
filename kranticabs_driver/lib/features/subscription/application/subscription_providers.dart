import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/core_providers.dart';
import '../data/subscription_model.dart';
import '../data/subscription_repository.dart';

final subscriptionRepositoryProvider = Provider<SubscriptionRepository>((ref) {
  return SubscriptionRepository(ref.watch(apiClientProvider));
});

/// Holds the subscription screen's status so a purchase can update it
/// straight from `POST /subscription/purchase`'s response — the backend
/// hands back the refreshed status, so a follow-up GET would just be a
/// wasted round-trip.
class SubscriptionStatusNotifier extends StateNotifier<AsyncValue<SubscriptionStatus>> {
  SubscriptionStatusNotifier(this._repo) : super(const AsyncValue.loading()) {
    refresh();
  }

  final SubscriptionRepository _repo;

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repo.getStatus());
  }

  void applyStatus(SubscriptionStatus status) {
    state = AsyncValue.data(status);
  }
}

final subscriptionStatusProvider =
    StateNotifierProvider.autoDispose<SubscriptionStatusNotifier, AsyncValue<SubscriptionStatus>>((ref) {
  return SubscriptionStatusNotifier(ref.watch(subscriptionRepositoryProvider));
});

final subscriptionHistoryProvider = FutureProvider.autoDispose<List<SubscriptionHistoryItem>>((ref) {
  return ref.watch(subscriptionRepositoryProvider).getHistory();
});

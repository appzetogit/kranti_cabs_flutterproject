import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/core_providers.dart';
import '../data/models/promo_model.dart';
import '../data/promo_repository.dart';

final promoRepositoryProvider = Provider<PromoRepository>((ref) {
  return PromoRepository(ref.watch(apiClientProvider));
});

final availablePromosProvider = FutureProvider<List<PromoModel>>((ref) {
  return ref.watch(promoRepositoryProvider).getAvailablePromos();
});

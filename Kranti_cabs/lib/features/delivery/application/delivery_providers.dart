import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/core_providers.dart';
import '../data/delivery_repository.dart';
import '../data/models/delivery_model.dart';

final deliveryRepositoryProvider = Provider<DeliveryRepository>((ref) {
  return DeliveryRepository(ref.watch(apiClientProvider));
});

final myDeliveriesProvider = FutureProvider.autoDispose<List<DeliveryModel>>((ref) {
  return ref.watch(deliveryRepositoryProvider).listMyDeliveries();
});

const parcelCategories = ['Documents', 'Food', 'Electronics', 'Clothes', 'Gift', 'Other'];

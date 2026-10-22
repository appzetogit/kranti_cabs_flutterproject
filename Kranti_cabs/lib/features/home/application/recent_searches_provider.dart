import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/core_providers.dart';
import '../data/models/saved_address_model.dart';

class RecentSearchesNotifier extends StateNotifier<List<SavedAddressModel>> {
  final Ref ref;
  static const _maxItems = 8;

  RecentSearchesNotifier(this.ref) : super([]) {
    _load();
  }

  void _load() {
    final box = ref.read(localStorageServiceProvider).recentSearches;
    state = box.values
        .map((e) => SavedAddressModel.fromJson(Map<dynamic, dynamic>.from(e)))
        .toList()
        .reversed
        .toList();
  }

  Future<void> add({
    required String address,
    required double lat,
    required double lng,
  }) async {
    final box = ref.read(localStorageServiceProvider).recentSearches;
    final id = '${lat}_$lng';
    await box.put(id, SavedAddressModel(id: id, label: address, address: address, lat: lat, lng: lng).toJson());
    if (box.length > _maxItems) {
      await box.deleteAt(0);
    }
    _load();
  }
}

final recentSearchesProvider =
    StateNotifierProvider<RecentSearchesNotifier, List<SavedAddressModel>>((ref) {
  return RecentSearchesNotifier(ref);
});

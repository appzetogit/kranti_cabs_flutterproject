import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../core/providers/core_providers.dart';
import '../data/models/saved_address_model.dart';

class SavedPlacesNotifier extends StateNotifier<List<SavedAddressModel>> {
  final Ref ref;
  static const _uuid = Uuid();

  SavedPlacesNotifier(this.ref) : super([]) {
    _load();
  }

  void _load() {
    final box = ref.read(localStorageServiceProvider).savedAddresses;
    state = box.values
        .map((e) => SavedAddressModel.fromJson(Map<dynamic, dynamic>.from(e)))
        .toList();
  }

  Future<void> add({
    required String label,
    required String address,
    required double lat,
    required double lng,
    String type = 'other',
  }) async {
    final box = ref.read(localStorageServiceProvider).savedAddresses;
    final model = SavedAddressModel(
      id: _uuid.v4(),
      label: label,
      address: address,
      lat: lat,
      lng: lng,
      type: type,
    );
    await box.put(model.id, model.toJson());
    _load();
  }

  Future<void> saveHomeOrWork({
    required String type,
    required String address,
    required double lat,
    required double lng,
  }) async {
    final box = ref.read(localStorageServiceProvider).savedAddresses;
    dynamic existingKey;
    for (final k in box.keys) {
      final val = box.get(k);
      if (val != null && (val['type'] == type || (val['label'] ?? '').toString().toLowerCase() == type.toLowerCase())) {
        existingKey = k;
        break;
      }
    }

    final id = existingKey != null ? existingKey.toString() : _uuid.v4();
    final model = SavedAddressModel(
      id: id,
      label: type.toLowerCase() == 'home' ? 'Home' : 'Work',
      address: address,
      lat: lat,
      lng: lng,
      type: type.toLowerCase(),
    );
    await box.put(id, model.toJson());
    _load();
  }

  Future<void> remove(String id) async {
    final box = ref.read(localStorageServiceProvider).savedAddresses;
    await box.delete(id);
    _load();
  }
}

final savedPlacesProvider =
    StateNotifierProvider<SavedPlacesNotifier, List<SavedAddressModel>>((ref) {
  return SavedPlacesNotifier(ref);
});

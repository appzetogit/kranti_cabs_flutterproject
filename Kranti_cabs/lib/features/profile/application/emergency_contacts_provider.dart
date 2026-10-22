import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../core/providers/core_providers.dart';
import '../../support/application/support_providers.dart';
import '../data/models/emergency_contact_model.dart';

class EmergencyContactsNotifier extends StateNotifier<List<EmergencyContactModel>> {
  final Ref ref;
  static const _uuid = Uuid();

  EmergencyContactsNotifier(this.ref) : super([]) {
    _load();
    // A fresh install (new phone, reinstall) has none on the device: bring
    // back the ones saved on the server.
    if (state.isEmpty) {
      unawaited(_restoreFromServer());
    } else {
      // Contacts added before they were kept on the server reach it here.
      unawaited(_syncToServer());
    }
  }

  /// What the server and the SOS alert carry: name, phone and relation.
  List<Map<String, String>> asPayload() => state
      .map((c) => {'name': c.name, 'phone': c.phone, 'relation': c.relation})
      .toList();

  Future<void> _restoreFromServer() async {
    try {
      final remote = await ref.read(supportRepositoryProvider).getEmergencyContacts();
      if (remote.isEmpty || state.isNotEmpty) return;
      final box = ref.read(localStorageServiceProvider).emergencyContacts;
      for (final contact in remote) {
        final model = EmergencyContactModel(
          id: _uuid.v4(),
          name: (contact['name'] ?? '').toString(),
          phone: (contact['phone'] ?? '').toString(),
          relation: (contact['relation'] ?? 'Other').toString(),
        );
        await box.put(model.id, model.toJson());
      }
      if (mounted) _load();
    } catch (_) {
      // Offline or signed out: the device list stays as it is.
    }
  }

  /// Keeps the server's copy in step, so a driver-pressed SOS and a new phone
  /// both see the same contacts. Best effort: the device list is what counts.
  Future<void> _syncToServer() async {
    try {
      await ref.read(supportRepositoryProvider).saveEmergencyContacts(asPayload());
    } catch (_) {}
  }

  void _load() {
    final box = ref.read(localStorageServiceProvider).emergencyContacts;
    state = box.values
        .map((e) => EmergencyContactModel.fromJson(Map<dynamic, dynamic>.from(e)))
        .toList();
  }

  Future<void> add({required String name, required String phone, String relation = 'Other'}) async {
    final box = ref.read(localStorageServiceProvider).emergencyContacts;
    final model = EmergencyContactModel(id: _uuid.v4(), name: name, phone: phone, relation: relation);
    await box.put(model.id, model.toJson());
    _load();
    unawaited(_syncToServer());
  }

  Future<void> remove(String id) async {
    final box = ref.read(localStorageServiceProvider).emergencyContacts;
    await box.delete(id);
    _load();
    unawaited(_syncToServer());
  }
}

final emergencyContactsProvider =
    StateNotifierProvider<EmergencyContactsNotifier, List<EmergencyContactModel>>((ref) {
  return EmergencyContactsNotifier(ref);
});

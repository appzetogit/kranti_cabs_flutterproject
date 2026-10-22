import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/core_providers.dart';
import '../../auth/application/signup_providers.dart';
import '../../auth/data/document_template.dart';
import '../data/emergency_contact.dart';
import '../data/profile_repository.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(ref.watch(apiClientProvider));
});

/// The admin's vehicle-type catalog — the same one the registration flow's
/// vehicle picker uses. Resolving the profile's own read-only "Vehicle type"
/// field against this (by `driver.vehicleTypeId`) is what guarantees the
/// name shown there ("Kranti Mini Truck", "Sedan", …) is the real, current
/// catalog name rather than whatever a flat `driver.vehicleType` string
/// happens to hold.
final vehicleTypeCatalogProvider =
    FutureProvider.autoDispose<List<VehicleTypeOption>>((ref) {
      return ref.watch(signupRepositoryProvider).getVehicleTypes();
    });

final emergencyContactsProvider =
    StateNotifierProvider.autoDispose<
      EmergencyContactsNotifier,
      AsyncValue<List<EmergencyContact>>
    >((ref) {
      return EmergencyContactsNotifier(ref.watch(profileRepositoryProvider));
    });

class EmergencyContactsNotifier
    extends StateNotifier<AsyncValue<List<EmergencyContact>>> {
  final ProfileRepository _repository;

  EmergencyContactsNotifier(this._repository)
    : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final contacts = await _repository.getEmergencyContacts();
      state = AsyncValue.data(contacts);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> add(String name, String phone) async {
    final contacts = await _repository.addEmergencyContact(
      name: name,
      phone: phone,
    );
    state = AsyncValue.data(contacts);
  }

  Future<void> remove(String contactId) async {
    final contacts = await _repository.deleteEmergencyContact(contactId);
    state = AsyncValue.data(contacts);
  }
}

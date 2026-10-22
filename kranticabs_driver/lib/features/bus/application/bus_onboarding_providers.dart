import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/bus_driver_repository.dart';
import '../data/models/bus_driver_models.dart';
import 'bus_auth_providers.dart';

/// Carries the registration id + entered details across the bus-driver signup
/// steps (phone → OTP → personal → bus → complete).
class BusOnboardingState {
  final String registrationId;
  final String phone;
  final String fullName;
  final String email;
  final String gender;

  const BusOnboardingState({
    this.registrationId = '',
    this.phone = '',
    this.fullName = '',
    this.email = '',
    this.gender = 'Male',
  });

  BusOnboardingState copyWith({
    String? registrationId,
    String? phone,
    String? fullName,
    String? email,
    String? gender,
  }) =>
      BusOnboardingState(
        registrationId: registrationId ?? this.registrationId,
        phone: phone ?? this.phone,
        fullName: fullName ?? this.fullName,
        email: email ?? this.email,
        gender: gender ?? this.gender,
      );
}

class BusOnboardingNotifier extends StateNotifier<BusOnboardingState> {
  final Ref ref;
  BusOnboardingNotifier(this.ref) : super(const BusOnboardingState());

  BusDriverRepository get _repo => ref.read(busDriverRepositoryProvider);

  Future<BusOnbStart> startOtp(String phone) async {
    final result = await _repo.onbSendOtp(phone);
    state = state.copyWith(registrationId: result.registrationId, phone: phone);
    return result;
  }

  Future<void> verifyOtp(String otp) async {
    await _repo.onbVerifyOtp(
      registrationId: state.registrationId,
      phone: state.phone,
      otp: otp,
    );
  }

  Future<void> savePersonal({
    required String fullName,
    required String email,
    required String gender,
  }) async {
    await _repo.onbSavePersonal(
      registrationId: state.registrationId,
      phone: state.phone,
      fullName: fullName,
      email: email,
      gender: gender,
    );
    state = state.copyWith(fullName: fullName, email: email, gender: gender);
  }

  Future<void> joinBus(String busServiceId, {String note = ''}) {
    return _repo.onbSaveRoleDetailsJoin(
      registrationId: state.registrationId,
      phone: state.phone,
      busServiceId: busServiceId,
      requestNote: note,
    );
  }

  Future<void> createBus({
    required String operatorName,
    required String busName,
    required String originCity,
    required String destinationCity,
    String serviceNumber = '',
    String note = '',
  }) {
    return _repo.onbSaveRoleDetailsCreate(
      registrationId: state.registrationId,
      phone: state.phone,
      operatorName: operatorName,
      busName: busName,
      originCity: originCity,
      destinationCity: destinationCity,
      serviceNumber: serviceNumber,
      requestNote: note,
    );
  }

  /// Completes signup and establishes the bus session (token already issued).
  /// Returns the driver's profile.
  Future<BusDriverProfile> complete() async {
    final token = await _repo.onbComplete(
      registrationId: state.registrationId,
      phone: state.phone,
    );
    if (token.isEmpty) {
      throw Exception('Could not complete registration. Please try again.');
    }
    return ref.read(busAuthProvider.notifier).completeSignup(token);
  }

  void reset() => state = const BusOnboardingState();
}

final busOnboardingProvider =
    StateNotifierProvider<BusOnboardingNotifier, BusOnboardingState>((ref) {
  return BusOnboardingNotifier(ref);
});

/// The buses a new driver can join (status active/paused).
final busSignupOptionsProvider =
    FutureProvider.autoDispose<List<BusSignupOption>>((ref) {
  return ref.watch(busDriverRepositoryProvider).onbSignupOptions();
});

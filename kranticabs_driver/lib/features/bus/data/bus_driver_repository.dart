import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import 'models/bus_driver_models.dart';
import 'models/bus_operate_models.dart';

/// Result of an onboarding send-otp: a registration id to carry through the
/// steps, plus whether the phone already has an account (switch to login).
class BusOnbStart {
  final String registrationId;
  final String? debugOtp;
  final bool loginMode;
  const BusOnbStart({required this.registrationId, this.debugOtp, this.loginMode = false});
}

class BusLoginVerify {
  final String? token;
  final bool needsRoleSelection;
  const BusLoginVerify({this.token, this.needsRoleSelection = false});
}

/// Every network call for the bus-driver flow (login, self-registration and the
/// operate screens). All hit `/drivers/...` on the shared backend; the backend
/// mints a `bus_driver` role token.
class BusDriverRepository {
  final ApiClient _api;
  BusDriverRepository(this._api);

  // ---- Login (phone + OTP, role bus_driver) --------------------------------

  Future<String?> sendLoginOtp(String phone) async {
    final data = await _api.post(ApiConstants.sendOtp, data: {
      'phone': phone,
      'role': 'bus_driver',
    });
    final map = data is Map ? Map<String, dynamic>.from(data) : const {};
    final session = map['session'] is Map ? Map<String, dynamic>.from(map['session']) : const {};
    return session['debugOtp']?.toString();
  }

  Future<BusLoginVerify> verifyLoginOtp(String phone, String otp) async {
    final data = await _api.post(ApiConstants.verifyOtp, data: {
      'phone': phone,
      'otp': otp,
      'role': 'bus_driver',
    });
    final map = data is Map ? Map<String, dynamic>.from(data) : const {};
    if (map['needsRoleSelection'] == true && map['token'] == null) {
      return const BusLoginVerify(needsRoleSelection: true);
    }
    return BusLoginVerify(token: map['token']?.toString());
  }

  Future<BusDriverProfile> getProfile() async {
    final data = await _api.get(ApiConstants.me);
    return BusDriverProfile.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<BusApprovalStatus> getApprovalStatus(String phone) async {
    final data = await _api.get(ApiConstants.approvalStatus, query: {'phone': phone});
    return BusApprovalStatus.fromJson(Map<String, dynamic>.from(data as Map));
  }

  // ---- Self-registration (onboarding) --------------------------------------

  Future<BusOnbStart> onbSendOtp(String phone) async {
    final data = await _api.post(ApiConstants.onboardingSendOtp, data: {
      'phone': phone,
      'role': 'bus_driver',
    });
    final map = data is Map ? Map<String, dynamic>.from(data) : const {};
    final session = map['session'] is Map ? Map<String, dynamic>.from(map['session']) : const {};
    return BusOnbStart(
      registrationId: _str(session['registrationId'] ?? map['registrationId']),
      debugOtp: session['debugOtp']?.toString(),
      loginMode: map['loginMode'] == true || map['existingAccount'] == true,
    );
  }

  Future<void> onbVerifyOtp({
    required String registrationId,
    required String phone,
    required String otp,
  }) async {
    await _api.post(ApiConstants.onboardingVerifyOtp, data: {
      'registrationId': registrationId,
      'phone': phone,
      'otp': otp,
    });
  }

  Future<void> onbSavePersonal({
    required String registrationId,
    required String phone,
    required String fullName,
    required String email,
    required String gender,
  }) async {
    await _api.patch(ApiConstants.onboardingPersonal, data: {
      'registrationId': registrationId,
      'phone': phone,
      'fullName': fullName,
      'email': email,
      'gender': gender,
    });
  }

  Future<List<BusSignupOption>> onbSignupOptions() async {
    final data = await _api.get(ApiConstants.onboardingSignupOptions);
    final map = data is Map ? Map<String, dynamic>.from(data) : const {};
    final list = (map['busServices'] as List? ?? const []);
    return list
        .whereType<Map>()
        .map((e) => BusSignupOption.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> onbSaveRoleDetailsJoin({
    required String registrationId,
    required String phone,
    required String busServiceId,
    String requestNote = '',
  }) async {
    await _api.patch(ApiConstants.onboardingRoleDetails, data: {
      'registrationId': registrationId,
      'phone': phone,
      'roleDetails': {
        'busServiceId': busServiceId,
        if (requestNote.isNotEmpty) 'requestNote': requestNote,
      },
    });
  }

  Future<void> onbSaveRoleDetailsCreate({
    required String registrationId,
    required String phone,
    required String operatorName,
    required String busName,
    required String originCity,
    required String destinationCity,
    String serviceNumber = '',
    String requestNote = '',
  }) async {
    await _api.patch(ApiConstants.onboardingRoleDetails, data: {
      'registrationId': registrationId,
      'phone': phone,
      'roleDetails': {
        'createNewBus': true,
        'operatorName': operatorName,
        'busName': busName,
        'originCity': originCity,
        'destinationCity': destinationCity,
        if (serviceNumber.isNotEmpty) 'serviceNumber': serviceNumber,
        if (requestNote.isNotEmpty) 'requestNote': requestNote,
      },
    });
  }

  /// Completes signup. Returns the issued `bus_driver` token.
  Future<String> onbComplete({required String registrationId, required String phone}) async {
    final data = await _api.post(ApiConstants.onboardingComplete, data: {
      'registrationId': registrationId,
      'phone': phone,
    });
    final map = data is Map ? Map<String, dynamic>.from(data) : const {};
    return _str(map['token']);
  }

  // ---- Operate (approved bus drivers) --------------------------------------

  Future<BusDriverSeatLayout> getSeats({required String scheduleId, required DateTime date}) async {
    final data = await _api.get(ApiConstants.busSeats, query: {
      'scheduleId': scheduleId,
      'date': _ymd(date),
    });
    return BusDriverSeatLayout.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<List<BusDriverBooking>> getBookings({
    required String scheduleId,
    required DateTime date,
    String? status,
  }) async {
    final data = await _api.get(ApiConstants.busBookings, query: {
      'scheduleId': scheduleId,
      'date': _ymd(date),
      if (status != null && status.isNotEmpty) 'status': status,
    });
    final map = data is Map ? Map<String, dynamic>.from(data) : const {};
    final list = (map['results'] as List? ?? const []);
    return list
        .whereType<Map>()
        .map((e) => BusDriverBooking.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<BusDriverBooking> createReservation({
    required String scheduleId,
    required DateTime travelDate,
    required List<String> seatIds,
    required String name,
    required int age,
    required String gender,
    required String phone,
    String email = '',
    String notes = '',
  }) async {
    final data = await _api.post(ApiConstants.busReservations, data: {
      'scheduleId': scheduleId,
      'travelDate': _ymd(travelDate),
      'seatIds': seatIds,
      'passenger': {
        'name': name,
        'age': age,
        'gender': gender,
        'phone': phone,
        'email': email,
      },
      if (notes.isNotEmpty) 'notes': notes,
    });
    return BusDriverBooking.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<BusLiveTrip> getLiveTrip() async {
    final data = await _api.get(ApiConstants.busLiveTrip);
    return BusLiveTrip.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<BusLiveTrip> startLiveTrip({
    required String scheduleId,
    required DateTime travelDate,
    double? lat,
    double? lng,
  }) async {
    final data = await _api.post(ApiConstants.busLiveTripStart, data: {
      'scheduleId': scheduleId,
      'travelDate': _ymd(travelDate),
      if (lat != null && lng != null) 'location': {'lat': lat, 'lng': lng},
    });
    return BusLiveTrip.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<BusLiveTrip> updateLiveLocation({
    required double lat,
    required double lng,
    double? speedKmph,
    String? scheduleId,
    DateTime? travelDate,
  }) async {
    final data = await _api.patch(ApiConstants.busLiveTripLocation, data: {
      'location': {
        'lat': lat,
        'lng': lng,
        if (speedKmph != null) 'speedKmph': speedKmph,
      },
      if (scheduleId != null) 'scheduleId': scheduleId,
      if (travelDate != null) 'travelDate': _ymd(travelDate),
    });
    return BusLiveTrip.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<BusLiveTrip> updateLiveStatus(String action) async {
    final data = await _api.patch(ApiConstants.busLiveTripStatus, data: {'action': action});
    return BusLiveTrip.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<List<BusSchedule>> updateSchedules(List<BusSchedule> schedules) async {
    final data = await _api.patch(ApiConstants.busSchedules, data: {
      'schedules': schedules.map((s) => s.toJson()).toList(),
    });
    final map = data is Map ? Map<String, dynamic>.from(data) : const {};
    return BusSchedule.listFrom(map['schedules']);
  }

  static String _ymd(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  static String _str(dynamic v) => (v ?? '').toString();
}

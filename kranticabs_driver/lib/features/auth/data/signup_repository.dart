import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import 'document_template.dart';
import 'driver_model.dart';

class SignupSession {
  final String registrationId;
  final String phone;
  final bool loginMode;

  SignupSession({
    required this.registrationId,
    required this.phone,
    this.loginMode = false,
  });
}

class SignupRepository {
  final ApiClient _api;

  SignupRepository(this._api);

  Future<SignupSession> sendOtp(String phone) async {
    final data = await _api.post(
      ApiConstants.onboardingSendOtp,
      data: {'phone': phone, 'role': 'driver'},
    );
    final map = data as Map;
    final session = map['session'] as Map? ?? {};
    return SignupSession(
      registrationId: (session['registrationId'] ?? '').toString(),
      phone: (session['phone'] ?? phone).toString(),
      loginMode: map['loginMode'] == true,
    );
  }

  Future<void> verifyOtp({
    required String registrationId,
    required String phone,
    required String otp,
  }) {
    return _api.post(
      ApiConstants.onboardingVerifyOtp,
      data: {'registrationId': registrationId, 'phone': phone, 'otp': otp},
    );
  }

  Future<void> savePersonal({
    required String registrationId,
    required String phone,
    required String fullName,
    required String email,
    required String gender,
  }) {
    // No password: drivers sign in with an OTP, so one was never used for
    // anything and only added a field to the signup form.
    return _api.patch(
      ApiConstants.onboardingPersonal,
      data: {
        'registrationId': registrationId,
        'phone': phone,
        'fullName': fullName,
        'email': email,
        'gender': gender,
      },
    );
  }

  Future<void> saveReferral({
    required String registrationId,
    required String phone,
    String referralCode = '',
    String employeeCode = '',
  }) {
    return _api.patch(
      ApiConstants.onboardingReferral,
      data: {
        'registrationId': registrationId,
        'phone': phone,
        'referralCode': referralCode,
        'employeeCode': employeeCode,
      },
    );
  }

  Future<List<ServiceLocationOption>> getSignupOptions() async {
    final data = await _api.get(ApiConstants.onboardingSignupOptions);
    final map = data as Map;
    final locations = (map['serviceLocations'] as List? ?? [])
        .map(
          (e) => ServiceLocationOption.fromJson(
            Map<String, dynamic>.from(e as Map),
          ),
        )
        .toList();
    return locations;
  }

  Future<List<VehicleTypeOption>> getVehicleTypes() async {
    final data = await _api.get(ApiConstants.vehicleTypes);
    final map = data as Map;
    final list = (map['results'] as List? ?? []);
    return list
        .map(
          (e) =>
              VehicleTypeOption.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .where((option) => option.id.isNotEmpty)
        .toList();
  }

  Future<List<VehicleFieldTemplate>> getVehicleFieldTemplates() async {
    final data = await _api.get(ApiConstants.vehicleFieldTemplates);
    final map = data as Map;
    final list = (map['results'] as List? ?? []);
    return list
        .map(
          (e) => VehicleFieldTemplate.fromJson(
            Map<String, dynamic>.from(e as Map),
          ),
        )
        .toList();
  }

  Future<List<DocumentTemplate>> getDocumentTemplates() async {
    final data = await _api.get(ApiConstants.documentTemplates);
    final map = data as Map;
    final groups = (map['results'] as List? ?? []);
    final templates = <DocumentTemplate>[];
    for (final g in groups) {
      final group = Map<String, dynamic>.from(g as Map);
      final fields = (group['fields'] as List? ?? []);
      for (final f in fields) {
        final field = Map<String, dynamic>.from(f as Map);
        final template = DocumentTemplate.fromField(group, field);
        if (template.key.isNotEmpty) templates.add(template);
      }
    }
    return templates;
  }

  Future<void> saveVehicle({
    required String registrationId,
    required String phone,
    required String locationId,
    required List<String> serviceCategories,
    required List<String> vehicleTypeIds,
    required String rcNumber,
    required String make,
    required String model,
    required String year,
    required String number,
    required String color,
    required String fuelType,
    Map<String, dynamic> customFields = const {},
  }) {
    return _api.patch(
      ApiConstants.onboardingVehicle,
      data: {
        'registrationId': registrationId,
        'phone': phone,
        'locationId': locationId,
        'serviceCategories': serviceCategories,
        'registerFor': serviceCategories.first,
        // The backend folds a legacy singular `vehicleTypeId` in too (older
        // builds only ever sent that), so sending the first selection under
        // both keys keeps this call compatible either way.
        'vehicleTypeId': vehicleTypeIds.isNotEmpty ? vehicleTypeIds.first : '',
        'vehicleTypeIds': vehicleTypeIds,
        'rcNumber': rcNumber,
        'make': make,
        'model': model,
        'year': year,
        'number': number,
        'color': color,
        'fuelType': fuelType,
        'customFields': customFields,
      },
    );
  }

  Future<void> saveDocuments({
    required String registrationId,
    required String phone,
    required Map<String, dynamic> documents,
  }) {
    return _api.patch(
      ApiConstants.onboardingDocuments,
      data: {
        'registrationId': registrationId,
        'phone': phone,
        'documents': documents,
      },
    );
  }

  Future<Map<String, dynamic>> complete({
    required String registrationId,
    required String phone,
  }) async {
    final data = await _api.post(
      ApiConstants.onboardingComplete,
      data: {'registrationId': registrationId, 'phone': phone},
    );
    return Map<String, dynamic>.from(data as Map);
  }
}

class SignupCompleteResult {
  final String? token;
  final DriverModel? driver;

  SignupCompleteResult({this.token, this.driver});

  factory SignupCompleteResult.fromJson(Map<String, dynamic> json) {
    final driverJson = json['driver'];
    return SignupCompleteResult(
      token: json['token']?.toString(),
      driver: driverJson is Map
          ? DriverModel.fromJson(Map<String, dynamic>.from(driverJson))
          : null,
    );
  }
}

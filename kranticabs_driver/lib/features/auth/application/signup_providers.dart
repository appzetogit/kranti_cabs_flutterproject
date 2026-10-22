import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/providers/core_providers.dart';
import '../data/document_template.dart';
import '../data/signup_repository.dart';
import 'auth_providers.dart';

final signupRepositoryProvider = Provider<SignupRepository>((ref) {
  return SignupRepository(ref.watch(apiClientProvider));
});

class SignupData {
  String registrationId = '';
  String phone = '';
  String fullName = '';
  String email = '';
  String gender = 'male';
  String locationId = '';
  List<String> serviceCategories = ['taxi'];
  List<String> vehicleTypeIds = const [];
  String rcNumber = '';
  String make = '';
  String model = '';
  String year = '';
  String number = '';
  String color = '';
  String fuelType = '';
  final Map<String, String> documentDataUrls = {};

  /// Where each picked document photo is on disk, so a restored signup can
  /// read it back instead of asking for it again.
  final Map<String, String> documentPaths = {};

  /// The step to resume at: '/signup-profile', '/vehicle-info' or
  /// '/documents-upload'.
  String resumeRoute = '';

  Map<String, dynamic> toJson() => {
        'registrationId': registrationId,
        'phone': phone,
        'fullName': fullName,
        'email': email,
        'gender': gender,
        'locationId': locationId,
        'serviceCategories': serviceCategories,
        'vehicleTypeIds': vehicleTypeIds,
        'rcNumber': rcNumber,
        'make': make,
        'model': model,
        'year': year,
        'number': number,
        'color': color,
        'fuelType': fuelType,
        'documentPaths': documentPaths,
        'resumeRoute': resumeRoute,
      };

  static SignupData fromJson(Map<String, dynamic> json) {
    List<String> strings(dynamic value) => value is List ? value.map((e) => '$e').toList() : const [];
    final data = SignupData()
      ..registrationId = '${json['registrationId'] ?? ''}'
      ..phone = '${json['phone'] ?? ''}'
      ..fullName = '${json['fullName'] ?? ''}'
      ..email = '${json['email'] ?? ''}'
      ..gender = '${json['gender'] ?? 'male'}'
      ..locationId = '${json['locationId'] ?? ''}'
      ..serviceCategories = strings(json['serviceCategories'])
      ..vehicleTypeIds = strings(json['vehicleTypeIds'])
      ..rcNumber = '${json['rcNumber'] ?? ''}'
      ..make = '${json['make'] ?? ''}'
      ..model = '${json['model'] ?? ''}'
      ..year = '${json['year'] ?? ''}'
      ..number = '${json['number'] ?? ''}'
      ..color = '${json['color'] ?? ''}'
      ..fuelType = '${json['fuelType'] ?? ''}'
      ..resumeRoute = '${json['resumeRoute'] ?? ''}';
    if (data.serviceCategories.isEmpty) data.serviceCategories = ['taxi'];
    final paths = json['documentPaths'];
    if (paths is Map) {
      paths.forEach((key, value) => data.documentPaths['$key'] = '$value');
    }
    return data;
  }
}

/// Signup progress kept on the phone between launches.
///
/// Some phones (Vivo in particular) kill the app in the background while the
/// camera is open to photograph a document. Signup lived only in memory, so
/// the driver came back to the login screen and had to start again from the
/// phone number - "it goes back to step zero". Saving after each step lets the
/// splash screen put them back where they were.
class SignupProgressStore {
  static const _key = 'driver_signup_progress_v1';
  static const _savedAtKey = 'driver_signup_progress_saved_at';

  /// Older than this and the server-side registration is likely gone too.
  static const maxAge = Duration(hours: 24);

  static Future<void> save(SignupData data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(data.toJson()));
    await prefs.setInt(_savedAtKey, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<SignupData?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    final savedAt = prefs.getInt(_savedAtKey) ?? 0;
    if (raw == null) return null;
    final age = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(savedAt));
    if (age > maxAge) {
      await clear();
      return null;
    }
    try {
      final data = SignupData.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
      return data.registrationId.isEmpty || data.resumeRoute.isEmpty ? null : data;
    } catch (_) {
      await clear();
      return null;
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    await prefs.remove(_savedAtKey);
  }
}

class SignupNotifier extends StateNotifier<SignupData> {
  final Ref ref;

  SignupNotifier(this.ref) : super(SignupData());

  /// Puts a signup saved before the app was killed back in place, re-reading
  /// any document photos that are still on disk. Returns the route to resume
  /// at, or null when there is nothing to resume.
  Future<String?> restoreSaved() async {
    final saved = await SignupProgressStore.load();
    if (saved == null) return null;
    for (final entry in saved.documentPaths.entries.toList()) {
      final file = File(entry.value);
      if (await file.exists()) {
        saved.documentDataUrls[entry.key] = 'data:image/jpeg;base64,${base64Encode(await file.readAsBytes())}';
      } else {
        saved.documentPaths.remove(entry.key);
      }
    }
    state = saved;
    return saved.resumeRoute;
  }

  Future<void> _checkpoint(String resumeRoute) {
    state.resumeRoute = resumeRoute;
    return SignupProgressStore.save(state);
  }

  Future<bool> sendOtp(String phone) async {
    final session = await ref.read(signupRepositoryProvider).sendOtp(phone);
    state.phone = session.phone;
    state.registrationId = session.registrationId;
    return session.loginMode;
  }

  Future<void> verifyOtp(String otp) async {
    await ref
        .read(signupRepositoryProvider)
        .verifyOtp(
          registrationId: state.registrationId,
          phone: state.phone,
          otp: otp,
        );
    await _checkpoint('/signup-profile');
  }

  Future<void> savePersonal({
    required String fullName,
    required String email,
    required String gender,
  }) {
    state.fullName = fullName;
    state.email = email;
    state.gender = gender;
    return ref
        .read(signupRepositoryProvider)
        .savePersonal(
          registrationId: state.registrationId,
          phone: state.phone,
          fullName: fullName,
          email: email,
          gender: gender,
        )
        .then((_) => _checkpoint('/vehicle-info'));
  }

  Future<List<ServiceLocationOption>> getSignupOptions() {
    return ref.read(signupRepositoryProvider).getSignupOptions();
  }

  Future<List<DocumentTemplate>> getDocumentTemplates() {
    return ref.read(signupRepositoryProvider).getDocumentTemplates();
  }

  Future<List<VehicleFieldTemplate>> getVehicleFieldTemplates() {
    return ref.read(signupRepositoryProvider).getVehicleFieldTemplates();
  }

  Future<List<VehicleTypeOption>> getVehicleTypes() {
    return ref.read(signupRepositoryProvider).getVehicleTypes();
  }

  Future<void> saveVehicle({
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
    state.locationId = locationId;
    state.serviceCategories = serviceCategories;
    state.vehicleTypeIds = vehicleTypeIds;
    state.rcNumber = rcNumber;
    state.make = make;
    state.model = model;
    state.year = year;
    state.number = number;
    state.color = color;
    state.fuelType = fuelType;
    return ref
        .read(signupRepositoryProvider)
        .saveVehicle(
          registrationId: state.registrationId,
          phone: state.phone,
          locationId: locationId,
          serviceCategories: serviceCategories,
          vehicleTypeIds: vehicleTypeIds,
          rcNumber: rcNumber,
          make: make,
          model: model,
          year: year,
          number: number,
          color: color,
          fuelType: fuelType,
          customFields: customFields,
        )
        .then((_) => _checkpoint('/documents-upload'));
  }

  /// [path] is kept so the photo survives the app being killed.
  void setDocument(String key, String dataUrl, {String? path}) {
    state.documentDataUrls[key] = dataUrl;
    if (path != null) {
      state.documentPaths[key] = path;
      SignupProgressStore.save(state);
    }
  }

  Future<void> saveDocuments() {
    final documents = state.documentDataUrls.map(
      (key, value) => MapEntry(key, {'dataUrl': value}),
    );
    return ref
        .read(signupRepositoryProvider)
        .saveDocuments(
          registrationId: state.registrationId,
          phone: state.phone,
          documents: documents,
        );
  }

  Future<void> complete() async {
    final result = await ref
        .read(signupRepositoryProvider)
        .complete(registrationId: state.registrationId, phone: state.phone);
    final parsed = SignupCompleteResult.fromJson(result);
    // Registered: nothing left to resume.
    await SignupProgressStore.clear();
    if (parsed.token != null && parsed.driver != null) {
      await ref.read(secureStorageServiceProvider).saveToken(parsed.token!);
      ref.read(authProvider.notifier).authenticateWithDriver(parsed.driver!);
      ref.read(authProvider.notifier).onAuthenticated(parsed.token!);
    }
  }
}

final signupProvider = StateNotifierProvider<SignupNotifier, SignupData>((ref) {
  return SignupNotifier(ref);
});

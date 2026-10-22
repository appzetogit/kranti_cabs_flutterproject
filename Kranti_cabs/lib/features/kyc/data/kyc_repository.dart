import '../../../core/network/api_client.dart';
import 'kyc_models.dart';

class KycRepository {
  final ApiClient api;
  KycRepository(this.api);

  Map<String, dynamic> _map(dynamic d) => Map<String, dynamic>.from(d as Map);

  Future<KycStatus> status() async => KycStatus.fromJson(_map(await api.get('/users/kyc/status')));

  Future<Map<String, dynamic>> sendAadhaarOtp(String aadhaar) async =>
      _map(await api.post('/users/kyc/aadhaar/otp', data: {'aadhaarNumber': aadhaar}));

  Future<KycStatus> verifyAadhaarOtp(String otp) async =>
      KycStatus.fromJson(_map(await api.post('/users/kyc/aadhaar/verify', data: {'otp': otp})));

  Future<KycStatus> verifyDocument(String type, String number, {String? dob}) async =>
      KycStatus.fromJson(_map(await api.post('/users/kyc/document',
          data: {'documentType': type, 'number': number, if (dob != null) 'dob': dob})));
}

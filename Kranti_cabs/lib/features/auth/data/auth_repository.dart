import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import 'models/user_model.dart';

class OtpSendResult {
  final bool exists;
  final String? debugOtp;

  OtpSendResult({required this.exists, this.debugOtp});
}

class OtpVerifyResult {
  final bool exists;
  final String? token;
  final UserModel? user;

  OtpVerifyResult({required this.exists, this.token, this.user});
}

class AuthSession {
  final String token;
  final UserModel user;

  AuthSession({required this.token, required this.user});
}

class AuthRepository {
  final ApiClient api;

  AuthRepository(this.api);

  Future<OtpSendResult> sendOtp(String phone) async {
    final data = await api.post(ApiConstants.sendOtp, data: {'phone': phone});
    final session = data['session'] as Map<String, dynamic>?;
    return OtpSendResult(
      exists: data['exists'] == true,
      debugOtp: session?['debugOtp']?.toString(),
    );
  }

  Future<OtpVerifyResult> verifyOtp({required String phone, required String otp}) async {
    final data = await api.post(
      ApiConstants.verifyOtp,
      data: {'phone': phone, 'otp': otp},
    );
    final exists = data['exists'] == true;
    if (exists) {
      return OtpVerifyResult(
        exists: true,
        token: data['token']?.toString(),
        user: UserModel.fromJson(Map<String, dynamic>.from(data['user'] ?? {})),
      );
    }
    return OtpVerifyResult(exists: false);
  }

  Future<AuthSession> signup({
    required String phone,
    required String name,
    String? email,
    String? gender,
    String? referralCode,
  }) async {
    final data = await api.post(ApiConstants.signup, data: {
      'phone': phone,
      'name': name,
      if (email != null && email.isNotEmpty) 'email': email,
      if (gender != null && gender.isNotEmpty) 'gender': gender,
      if (referralCode != null && referralCode.isNotEmpty) 'referralCode': referralCode,
    });
    return AuthSession(
      token: data['token'].toString(),
      user: UserModel.fromJson(Map<String, dynamic>.from(data['user'] ?? {})),
    );
  }

  Future<UserModel> getCurrentUser() async {
    final data = await api.get(ApiConstants.me);
    return UserModel.fromJson(Map<String, dynamic>.from(data['user'] ?? data));
  }

  Future<UserModel> updateProfile(Map<String, dynamic> fields) async {
    final data = await api.patch(ApiConstants.me, data: fields);
    return UserModel.fromJson(Map<String, dynamic>.from(data['user'] ?? data));
  }

  Future<String> uploadProfileImage(String dataUrl) async {
    final data = await api.post(ApiConstants.profileImage, data: {'dataUrl': dataUrl});
    return (data['secureUrl'] ?? '').toString();
  }

  Future<void> saveFcmToken(String token, {required String platform}) {
    return api.post(ApiConstants.fcmToken, data: {'token': token, 'platform': platform});
  }

  Future<void> requestAccountDeletion(String reason) {
    return api.post(ApiConstants.deleteRequest, data: {'reason': reason});
  }
}

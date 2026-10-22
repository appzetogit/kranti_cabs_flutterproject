import 'dart:convert';
import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import 'driver_model.dart';

class OtpSendResult {
  final String message;
  final String? debugOtp;

  OtpSendResult({required this.message, this.debugOtp});
}

class OtpVerifyResult {
  final String? token;
  final DriverModel? driver;

  OtpVerifyResult({this.token, this.driver});
}

class AuthRepository {
  final ApiClient _api;

  AuthRepository(this._api);

  Future<OtpSendResult> sendLoginOtp(String phone) async {
    final data = await _api.post(ApiConstants.sendOtp, data: {
      'phone': phone,
      'role': 'driver',
    });
    final map = data as Map;
    final session = map['session'] as Map?;
    return OtpSendResult(
      message: (map['message'] ?? 'OTP sent').toString(),
      debugOtp: session?['debugOtp']?.toString(),
    );
  }

  Future<OtpVerifyResult> verifyLoginOtp(String phone, String otp) async {
    final data = await _api.post(ApiConstants.verifyOtp, data: {
      'phone': phone,
      'otp': otp,
      'role': 'driver',
    });
    final map = data as Map;
    final token = map['token']?.toString();
    final driverJson = map['driver'];
    return OtpVerifyResult(
      token: token,
      driver: driverJson is Map ? DriverModel.fromJson(Map<String, dynamic>.from(driverJson)) : null,
    );
  }

  Future<DriverModel> getCurrentDriver() async {
    final data = await _api.get(ApiConstants.me);
    return DriverModel.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<DriverModel> updateBankDetails(BankDetails details) async {
    final data = await _api.patch(ApiConstants.me, data: {
      'bankDetails': {
        'accountHolderName': details.accountHolderName,
        'accountNumber': details.accountNumber,
        'ifsc': details.ifsc,
        'branchName': details.branchName,
        'upiId': details.upiId,
      },
    });
    return DriverModel.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<Map<String, dynamic>> getApprovalStatus(String phone) async {
    final data = await _api.get(ApiConstants.approvalStatus, query: {'phone': phone});
    return Map<String, dynamic>.from(data as Map);
  }

  String encodeDriver(DriverModel driver) => jsonEncode(driver.toJson());

  DriverModel decodeDriver(String raw) => DriverModel.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
}

import '../constants/app_constants.dart';

class Validators {
  Validators._();

  static String? phone(String? value) {
    if (value == null || value.trim().isEmpty) return 'Phone number is required';
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length != AppConstants.phoneLength) {
      return 'Enter a valid ${AppConstants.phoneLength}-digit phone number';
    }
    return null;
  }

  static String? otp(String? value) {
    if (value == null || value.trim().isEmpty) return 'OTP is required';
    if (value.trim().length != AppConstants.otpLength) {
      return 'Enter the ${AppConstants.otpLength}-digit OTP';
    }
    return null;
  }

  static String? required(String? value, {String field = 'This field'}) {
    if (value == null || value.trim().isEmpty) return '$field is required';
    return null;
  }

  static String? email(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final regex = RegExp(r'^[\w\.\-]+@([\w\-]+\.)+[\w\-]{2,4}$');
    if (!regex.hasMatch(value.trim())) return 'Enter a valid email address';
    return null;
  }

  static String? vehicleNumber(String? value) {
    if (value == null || value.trim().isEmpty) return 'Vehicle number is required';
    if (value.trim().length < 4) return 'Enter a valid vehicle number';
    return null;
  }

  static String? panNumber(String? value) {
    if (value == null || value.trim().isEmpty) return 'PAN number is required';
    final regex = RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]{1}$');
    if (!regex.hasMatch(value.trim().toUpperCase())) return 'Enter a valid PAN number';
    return null;
  }

  static String? ifsc(String? value) {
    if (value == null || value.trim().isEmpty) return 'IFSC code is required';
    final regex = RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$');
    if (!regex.hasMatch(value.trim().toUpperCase())) return 'Enter a valid IFSC code';
    return null;
  }

  static String? accountNumber(String? value) {
    if (value == null || value.trim().isEmpty) return 'Account number is required';
    if (value.trim().length < 6) return 'Enter a valid account number';
    return null;
  }
}

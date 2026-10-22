import 'package:dio/dio.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final List<String>? errors;

  /// Machine-readable `details.code` (e.g. KYC_REQUIRED), when the server sent one.
  final String? code;

  ApiException(this.message, {this.statusCode, this.errors, this.code});

  factory ApiException.fromDioError(DioException error) {
    final response = error.response;
    if (response != null && response.data is Map) {
      final data = response.data as Map;
      final message = data['message']?.toString();
      final errorsList = data['errors'];
      return ApiException(
        message ?? _fallbackMessage(error),
        statusCode: response.statusCode,
        code: data['details'] is Map ? (data['details'] as Map)['code']?.toString() : null,
        errors: errorsList is List
            ? errorsList.map((e) => e.toString()).toList()
            : null,
      );
    }
    return ApiException(_fallbackMessage(error), statusCode: response?.statusCode);
  }

  static String _fallbackMessage(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'The connection timed out. Please try again.';
      case DioExceptionType.connectionError:
        return 'Unable to reach the server. Check your internet connection.';
      case DioExceptionType.cancel:
        return 'Request was cancelled.';
      default:
        return error.message ?? 'Something went wrong. Please try again.';
    }
  }

  @override
  String toString() => message;
}

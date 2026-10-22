import 'package:dio/dio.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final List<String>? errors;

  ApiException(this.message, {this.statusCode, this.errors});

  factory ApiException.fromDioError(DioException error) {
    final response = error.response;
    if (response != null && response.data is Map) {
      final data = response.data as Map;
      final message = data['message']?.toString();
      final errorsList = data['errors'];
      return ApiException(
        message ?? _fallbackMessage(error),
        statusCode: response.statusCode,
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

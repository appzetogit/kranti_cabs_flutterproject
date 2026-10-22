import 'package:dio/dio.dart';
import '../constants/api_constants.dart';
import '../storage/secure_storage_service.dart';

typedef UnauthorizedCallback = void Function();

class DioClient {
  final Dio dio;
  final SecureStorageService secureStorage;
  UnauthorizedCallback? onUnauthorized;

  DioClient(this.secureStorage)
      : dio = Dio(
          BaseOptions(
            baseUrl: ApiConstants.baseUrl,
            connectTimeout: const Duration(seconds: 20),
            receiveTimeout: const Duration(seconds: 20),
            sendTimeout: const Duration(seconds: 20),
            headers: {'Content-Type': 'application/json'},
          ),
        ) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await secureStorage.readToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) {
          // Only a request that actually carried a session can have had one
          // expire. A 401 on a call with no token means the driver is simply
          // not signed in yet — treating that as an expiry hijacks navigation
          // on a fresh install, stranding it on the session-expired screen
          // whose only button lands straight back on it.
          final sentWithSession =
              (error.requestOptions.headers['Authorization'] as String?)?.isNotEmpty ?? false;

          if (error.response?.statusCode == 401 && sentWithSession) {
            onUnauthorized?.call();
          }
          handler.next(error);
        },
      ),
    );
  }
}

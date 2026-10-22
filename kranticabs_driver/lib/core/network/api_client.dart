import 'package:dio/dio.dart';
import 'api_exception.dart';

/// Thin wrapper around Dio that unwraps this backend's standard
/// `{ success, data }` / `{ success, message }` envelope and converts
/// failures into [ApiException].
class ApiClient {
  final Dio dio;

  ApiClient(this.dio);

  Future<dynamic> _unwrap(Future<Response> Function() call) async {
    try {
      final response = await call();
      final body = response.data;
      if (body is Map && body.containsKey('data')) {
        return body['data'];
      }
      return body;
    } on DioException catch (error) {
      throw ApiException.fromDioError(error);
    }
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) {
    return _unwrap(() => dio.get(path, queryParameters: query));
  }

  Future<dynamic> post(String path, {Object? data, Map<String, dynamic>? query}) {
    return _unwrap(() => dio.post(path, data: data, queryParameters: query));
  }

  Future<dynamic> patch(String path, {Object? data, Map<String, dynamic>? query}) {
    return _unwrap(() => dio.patch(path, data: data, queryParameters: query));
  }

  Future<dynamic> delete(String path, {Object? data, Map<String, dynamic>? query}) {
    return _unwrap(() => dio.delete(path, data: data, queryParameters: query));
  }
}

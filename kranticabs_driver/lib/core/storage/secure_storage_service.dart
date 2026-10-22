import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants/storage_keys.dart';

class SecureStorageService {
  final FlutterSecureStorage _storage;

  SecureStorageService()
      : _storage = const FlutterSecureStorage(
          aOptions: AndroidOptions(encryptedSharedPreferences: true),
        );

  Future<void> saveToken(String token) => _storage.write(key: StorageKeys.authToken, value: token);

  Future<String?> readToken() => _storage.read(key: StorageKeys.authToken);

  Future<void> deleteToken() => _storage.delete(key: StorageKeys.authToken);

  Future<void> clearAll() => _storage.deleteAll();
}

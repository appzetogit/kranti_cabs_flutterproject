import 'dart:convert';

import '../../../../core/constants/storage_keys.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/storage/local_storage_service.dart';
import 'ride_voice_config.dart';
import 'ride_voice_log.dart';

/// Fetches the admin-managed voice configuration, and remembers the last good
/// answer.
///
/// Announcements are an enhancement — never a dependency of the trip — so every
/// path here ends in a usable config rather than an exception: live answer,
/// then last cached answer, then silence.
class RideVoiceRepository {
  final ApiClient api;
  final LocalStorageService storage;

  RideVoiceRepository(this.api, this.storage);

  /// Endpoint path. Lives here rather than in `ApiConstants` alongside the
  /// hand-written list because it is just the generic settings route with this
  /// feature's category.
  static const String _path = '/users/settings/ride-voice';

  Future<RideVoiceConfig> fetchConfig() async {
    try {
      final data = await api.get(_path);
      if (data is! Map) throw const FormatException('Unexpected voice config payload');

      final config = RideVoiceConfig.fromJson(Map<String, dynamic>.from(data));
      _cache(config);
      rideVoiceLog('Voice config loaded (enabled: ${config.enabled})');
      return config;
    } catch (error) {
      final cached = readCachedConfig();
      rideVoiceLog(
        cached == null
            ? 'Voice config unavailable and nothing cached — staying silent ($error)'
            : 'Voice config fetch failed, using the cached copy ($error)',
      );
      return cached ?? RideVoiceConfig.silent;
    }
  }

  RideVoiceConfig? readCachedConfig() {
    try {
      final raw = storage.settings.get(StorageKeys.rideVoiceConfig);
      if (raw is! String || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return RideVoiceConfig.fromJson(Map<String, dynamic>.from(decoded));
    } catch (error) {
      rideVoiceLog('Cached voice config could not be read ($error)');
      return null;
    }
  }

  void _cache(RideVoiceConfig config) {
    try {
      storage.settings.put(StorageKeys.rideVoiceConfig, jsonEncode(config.toJson()));
    } catch (error) {
      rideVoiceLog('Voice config could not be cached ($error)');
    }
  }
}

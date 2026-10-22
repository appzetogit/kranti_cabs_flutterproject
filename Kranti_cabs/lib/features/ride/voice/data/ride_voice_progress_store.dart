import 'dart:convert';

import '../../../../core/constants/storage_keys.dart';
import '../../../../core/storage/local_storage_service.dart';
import 'ride_voice_log.dart';

/// What has already been said on one trip.
class RideVoiceProgress {
  final bool welcomePlayed;
  final bool comfortPlayed;
  final bool arrivalPlayed;

  const RideVoiceProgress({
    this.welcomePlayed = false,
    this.comfortPlayed = false,
    this.arrivalPlayed = false,
  });

  RideVoiceProgress copyWith({
    bool? welcomePlayed,
    bool? comfortPlayed,
    bool? arrivalPlayed,
  }) {
    return RideVoiceProgress(
      welcomePlayed: welcomePlayed ?? this.welcomePlayed,
      comfortPlayed: comfortPlayed ?? this.comfortPlayed,
      arrivalPlayed: arrivalPlayed ?? this.arrivalPlayed,
    );
  }

  Map<String, dynamic> toJson() => {
        'welcome': welcomePlayed,
        'comfort': comfortPlayed,
        'arrival': arrivalPlayed,
      };

  factory RideVoiceProgress.fromJson(Map<String, dynamic> json) {
    return RideVoiceProgress(
      welcomePlayed: json['welcome'] == true,
      comfortPlayed: json['comfort'] == true,
      arrivalPlayed: json['arrival'] == true,
    );
  }
}

/// Remembers, per ride, which announcements have already been spoken.
///
/// This is what makes "at most once per ride" survive the app being killed,
/// swiped away or restarted mid-trip. An in-memory flag would be reset by any
/// of those and the rider would hear the welcome a second time.
class RideVoiceProgressStore {
  final LocalStorageService storage;

  RideVoiceProgressStore(this.storage);

  /// Records are tiny, but a rider who takes trips every day would otherwise
  /// accumulate them forever. Keeping the most recent handful is enough: the
  /// only entry that ever matters is the trip in progress.
  static const int _maxTrackedRides = 20;

  RideVoiceProgress read(String rideId) {
    final all = _readAll();
    final entry = all[rideId];
    if (entry is Map) {
      return RideVoiceProgress.fromJson(Map<String, dynamic>.from(entry));
    }
    return const RideVoiceProgress();
  }

  void write(String rideId, RideVoiceProgress progress) {
    final all = _readAll();
    all.remove(rideId); // re-inserted at the end so ordering stays recency-based
    all[rideId] = progress.toJson();

    while (all.length > _maxTrackedRides) {
      all.remove(all.keys.first);
    }

    try {
      storage.settings.put(StorageKeys.rideVoiceProgress, jsonEncode(all));
    } catch (error) {
      rideVoiceLog('Could not persist announcement progress ($error)');
    }
  }

  void clear(String rideId) {
    final all = _readAll();
    if (all.remove(rideId) == null) return;
    try {
      storage.settings.put(StorageKeys.rideVoiceProgress, jsonEncode(all));
    } catch (error) {
      rideVoiceLog('Could not clear announcement progress ($error)');
    }
  }

  Map<String, dynamic> _readAll() {
    try {
      final raw = storage.settings.get(StorageKeys.rideVoiceProgress);
      if (raw is! String || raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return Map<String, dynamic>.from(decoded);
    } catch (error) {
      rideVoiceLog('Could not read announcement progress ($error)');
      return {};
    }
  }
}

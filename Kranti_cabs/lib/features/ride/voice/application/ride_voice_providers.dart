import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/storage_keys.dart';
import '../../../../core/providers/core_providers.dart';
import '../../../profile/application/locale_provider.dart';
import '../../application/ride_providers.dart';
import '../data/ride_voice_log.dart';
import '../data/ride_voice_progress_store.dart';
import '../data/ride_voice_repository.dart';
import '../services/ride_tts_service.dart';
import 'ride_voice_scheduler.dart';

/// The rider's own switch for in-ride announcements.
///
/// Defaults to on — the feature is the product decision; this exists so a rider
/// who does not want a voice in their car can turn it off without losing the
/// app language they chose.
class RideVoiceEnabledNotifier extends StateNotifier<bool> {
  final Ref ref;

  RideVoiceEnabledNotifier(this.ref) : super(true) {
    final box = ref.read(localStorageServiceProvider).settings;
    state = box.get(StorageKeys.rideVoiceEnabled) != false;
  }

  void setEnabled(bool enabled) {
    state = enabled;
    ref.read(localStorageServiceProvider).settings.put(StorageKeys.rideVoiceEnabled, enabled);
    if (!enabled) {
      // Stop mid-sentence rather than finish reading something the rider just
      // asked not to hear.
      RideTtsService.instance.stop();
    }
    rideVoiceLog('Rider set voice announcements ${enabled ? 'on' : 'off'}');
  }
}

final rideVoiceEnabledProvider =
    StateNotifierProvider<RideVoiceEnabledNotifier, bool>((ref) {
  return RideVoiceEnabledNotifier(ref);
});

final rideVoiceRepositoryProvider = Provider<RideVoiceRepository>((ref) {
  return RideVoiceRepository(
    ref.watch(apiClientProvider),
    ref.watch(localStorageServiceProvider),
  );
});

final rideVoiceProgressStoreProvider = Provider<RideVoiceProgressStore>((ref) {
  return RideVoiceProgressStore(ref.watch(localStorageServiceProvider));
});

/// App-scoped, deliberately.
///
/// The scheduler outlives the tracking screen: a rider who backs out to Home
/// mid-trip must still hear their announcements, and a screen-scoped instance
/// would be disposed the moment they navigated away.
final rideVoiceSchedulerProvider = Provider<RideVoiceScheduler>((ref) {
  final scheduler = RideVoiceScheduler(
    progressStore: ref.watch(rideVoiceProgressStoreProvider),
    readLanguage: () => ref.read(localeProvider),
    readEnabled: () => ref.read(rideVoiceEnabledProvider),
    loadConfig: () => ref.read(rideVoiceRepositoryProvider).fetchConfig(),
    refreshRide: (rideId) async {
      try {
        return await ref.read(rideRepositoryProvider).getRideById(rideId);
      } catch (error) {
        rideVoiceLog('Could not refresh the ride for the voice scheduler ($error)');
        return null;
      }
    },
    loadActiveRide: () async {
      try {
        return await ref.read(rideRepositoryProvider).getMyActiveRide();
      } catch (_) {
        // Signed out, offline, or simply no trip running — all ordinary.
        return null;
      }
    },
  );

  ref.onDispose(scheduler.dispose);
  return scheduler;
});

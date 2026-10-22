import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/core_providers.dart';
import '../data/models/bidding_settings_model.dart';
import '../data/models/ride_model.dart';
import '../data/ride_repository.dart';

/// The admin's bidding bands, fetched once and shared.
///
/// Falls back to the backend's own defaults rather than surfacing an error: a
/// rider should not be blocked from booking because a settings lookup failed.
final biddingSettingsProvider = FutureProvider<BiddingSettings>((ref) async {
  try {
    return await ref.read(rideRepositoryProvider).getBiddingSettings();
  } catch (_) {
    return BiddingSettings.fallback;
  }
});

final rideRepositoryProvider = Provider<RideRepository>((ref) {
  return RideRepository(ref.watch(apiClientProvider));
});

/// The rider's in-progress ride, so any screen can surface an "ongoing ride"
/// entry point. Yields null once the trip ends.
///
/// Polled rather than fetched once: a ride can finish or be cancelled while the
/// rider sits on another screen, and a one-shot fetch would leave a stale entry
/// point on screen indefinitely. `autoDispose` stops the polling as soon as
/// nothing is listening.
final myActiveRideProvider = StreamProvider.autoDispose<RideModel?>((ref) async* {
  final repository = ref.watch(rideRepositoryProvider);

  Future<RideModel?> fetch() async {
    try {
      return await repository.getMyActiveRide();
    } catch (_) {
      // A failed poll should never break the screen hosting this.
      return null;
    }
  }

  yield await fetch();

  await for (final _ in Stream<void>.periodic(const Duration(seconds: 15))) {
    yield await fetch();
  }
});

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/core_providers.dart';
import '../data/scheduled_ride.dart';
import '../data/scheduled_rides_repository.dart';

final scheduledRidesRepositoryProvider = Provider<ScheduledRidesRepository>((ref) {
  return ScheduledRidesRepository(ref.watch(apiClientProvider));
});

/// The Scheduled Rides list. `ref.invalidate(scheduledRidesProvider)` after
/// accepting or cancelling to reload it.
final scheduledRidesProvider = FutureProvider.autoDispose<List<ScheduledRide>>((ref) {
  return ref.watch(scheduledRidesRepositoryProvider).list();
});

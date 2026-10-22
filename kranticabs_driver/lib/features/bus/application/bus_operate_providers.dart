import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/bus_operate_models.dart';
import 'bus_auth_providers.dart';

typedef BusManifestQuery = ({String scheduleId, String date});

/// Passenger manifest for a schedule + date.
final busManifestProvider =
    FutureProvider.autoDispose.family<List<BusDriverBooking>, BusManifestQuery>((ref, q) {
  final date = DateTime.tryParse(q.date) ?? DateTime.now();
  return ref.watch(busDriverRepositoryProvider).getBookings(
        scheduleId: q.scheduleId,
        date: date,
      );
});

/// Seat layout for a schedule + date (for the manual-booking seat picker).
final busDriverSeatsProvider =
    FutureProvider.autoDispose.family<BusDriverSeatLayout, BusManifestQuery>((ref, q) {
  final date = DateTime.tryParse(q.date) ?? DateTime.now();
  return ref.watch(busDriverRepositoryProvider).getSeats(
        scheduleId: q.scheduleId,
        date: date,
      );
});

/// Current live-trip state for the assigned bus.
final busLiveTripProvider = FutureProvider.autoDispose<BusLiveTrip>((ref) {
  return ref.watch(busDriverRepositoryProvider).getLiveTrip();
});

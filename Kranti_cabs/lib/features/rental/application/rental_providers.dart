import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/core_providers.dart';
import '../data/models/rental_booking_model.dart';
import '../data/models/rental_vehicle_model.dart';
import '../data/hourly_rental.dart';
import '../data/hourly_rental_repository.dart';
import '../data/rental_repository.dart';

final rentalRepositoryProvider = Provider<RentalRepository>((ref) {
  return RentalRepository(ref.watch(apiClientProvider));
});

final rentalVehiclesProvider = FutureProvider.autoDispose<List<RentalVehicleModel>>((ref) {
  return ref.watch(rentalRepositoryProvider).getRentalVehicles();
});

final activeRentalBookingProvider = FutureProvider.autoDispose<RentalBookingModel?>((ref) {
  return ref.watch(rentalRepositoryProvider).getActiveBooking();
});

final myRentalBookingsProvider = FutureProvider.autoDispose<List<RentalBookingModel>>((ref) {
  return ref.watch(rentalRepositoryProvider).listMyBookings();
});

final hourlyRentalRepositoryProvider = Provider<HourlyRentalRepository>((ref) {
  return HourlyRentalRepository(ref.watch(apiClientProvider));
});

/// Hourly-rental packages for a pickup, keyed "lat,lng" at ~1 km (4-decimal
/// precision is not needed and would refetch on every nudge of the pin).
final hourlyPackagesProvider = FutureProvider.autoDispose.family<List<HourlyRentalPackage>, String>((ref, key) {
  final parts = key.split(',');
  final lat = parts.length == 2 ? double.tryParse(parts[0]) : null;
  final lng = parts.length == 2 ? double.tryParse(parts[1]) : null;
  return ref.watch(hourlyRentalRepositoryProvider).packages(lat: lat, lng: lng);
});

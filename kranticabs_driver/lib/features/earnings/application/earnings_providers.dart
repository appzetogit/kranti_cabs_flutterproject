import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/core_providers.dart';
import '../../ride/application/ride_providers.dart';
import '../../ride/data/ride_history_item.dart';
import '../data/earnings_repository.dart';
import '../data/incentive_model.dart';
import '../data/wallet_model.dart';

final earningsRepositoryProvider = Provider<EarningsRepository>((ref) {
  return EarningsRepository(ref.watch(apiClientProvider));
});

final walletSnapshotProvider = FutureProvider.autoDispose<WalletSnapshot>((ref) {
  return ref.watch(earningsRepositoryProvider).getWallet();
});

final incentiveSnapshotProvider = FutureProvider.autoDispose<IncentiveSnapshot>((ref) {
  return ref.watch(earningsRepositoryProvider).getIncentives();
});

/// Every completed trip the driver has ever done.
///
/// Read from the history endpoint's own `total` rather than by counting the
/// rides fetched for the earnings tabs — that list is capped at 100, so
/// counting it would quietly under-report a long-serving driver's total.
final lifetimeRideCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final page = await ref.watch(rideRepositoryProvider).listMyRides(limit: 1);
  return page.total;
});

/// Backs the Today/Week/Month earnings tabs and the recent-trips list — the
/// backend has no dedicated weekly/monthly aggregate endpoint, so this is
/// computed client-side from the driver's recent ride history.
final recentRidesProvider = FutureProvider.autoDispose<List<RideHistoryItem>>((ref) async {
  final page = await ref.watch(rideRepositoryProvider).listMyRides(limit: 100);
  return page.results.where((ride) => ride.isCompleted).toList();
});

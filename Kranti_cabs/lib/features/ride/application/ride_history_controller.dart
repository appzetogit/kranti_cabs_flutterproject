import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/ride_model.dart';
import 'ride_history_state.dart';
import 'ride_providers.dart';

const _pageSize = 20;

class RideHistoryController extends StateNotifier<RideHistoryState> {
  final Ref ref;

  RideHistoryController(this.ref) : super(const RideHistoryState()) {
    loadFirstPage();
  }

  Future<void> loadFirstPage() async {
    state = state.copyWith(isLoading: true, clearError: true, page: 1);
    try {
      final data = await ref.read(rideRepositoryProvider).listMyRides(
            page: 1,
            limit: _pageSize,
            category: state.category == 'all' ? null : state.category,
          );
      final results = (data['results'] as List? ?? []);
      final rides = results.map((e) => RideModel.fromJson(Map<String, dynamic>.from(e))).toList();
      state = state.copyWith(
        rides: rides,
        isLoading: false,
        hasMore: rides.length >= _pageSize,
        page: 1,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> loadNextPage() async {
    if (state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true);
    try {
      final nextPage = state.page + 1;
      final data = await ref.read(rideRepositoryProvider).listMyRides(
            page: nextPage,
            limit: _pageSize,
            category: state.category == 'all' ? null : state.category,
          );
      final results = (data['results'] as List? ?? []);
      final rides = results.map((e) => RideModel.fromJson(Map<String, dynamic>.from(e))).toList();
      state = state.copyWith(
        rides: [...state.rides, ...rides],
        isLoadingMore: false,
        hasMore: rides.length >= _pageSize,
        page: nextPage,
      );
    } catch (e) {
      state = state.copyWith(isLoadingMore: false, error: e.toString());
    }
  }

  void setCategory(String category) {
    if (category == state.category) return;
    state = state.copyWith(category: category);
    loadFirstPage();
  }
}

final rideHistoryControllerProvider =
    StateNotifierProvider<RideHistoryController, RideHistoryState>((ref) {
  return RideHistoryController(ref);
});

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/ride_history_item.dart';
import 'ride_providers.dart';

class RideHistoryState {
  final List<RideHistoryItem> items;
  final int page;
  final bool hasNextPage;
  final bool loading;
  final bool loadingMore;
  final String? error;

  const RideHistoryState({
    this.items = const [],
    this.page = 1,
    this.hasNextPage = false,
    this.loading = false,
    this.loadingMore = false,
    this.error,
  });

  RideHistoryState copyWith({
    List<RideHistoryItem>? items,
    int? page,
    bool? hasNextPage,
    bool? loading,
    bool? loadingMore,
    String? error,
  }) {
    return RideHistoryState(
      items: items ?? this.items,
      page: page ?? this.page,
      hasNextPage: hasNextPage ?? this.hasNextPage,
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      error: error,
    );
  }
}

class RideHistoryNotifier extends StateNotifier<RideHistoryState> {
  final Ref _ref;
  static const _limit = 15;

  RideHistoryNotifier(this._ref) : super(const RideHistoryState()) {
    loadFirstPage();
  }

  Future<void> loadFirstPage() async {
    state = state.copyWith(loading: true, error: null);
    try {
      final page = await _ref.read(rideRepositoryProvider).listMyRides(page: 1, limit: _limit);
      state = RideHistoryState(items: page.results, page: 1, hasNextPage: page.hasNextPage, loading: false);
    } catch (e) {
      state = state.copyWith(loading: false, error: 'Could not load ride history');
    }
  }

  Future<void> loadMore() async {
    if (state.loadingMore || state.loading || !state.hasNextPage) return;
    state = state.copyWith(loadingMore: true);
    try {
      final nextPage = state.page + 1;
      final page = await _ref.read(rideRepositoryProvider).listMyRides(page: nextPage, limit: _limit);
      state = state.copyWith(
        items: [...state.items, ...page.results],
        page: nextPage,
        hasNextPage: page.hasNextPage,
        loadingMore: false,
      );
    } catch (e) {
      state = state.copyWith(loadingMore: false);
    }
  }
}

final rideHistoryProvider = StateNotifierProvider.autoDispose<RideHistoryNotifier, RideHistoryState>((ref) {
  return RideHistoryNotifier(ref);
});

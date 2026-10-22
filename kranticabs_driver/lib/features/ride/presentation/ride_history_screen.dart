import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../../../shared/widgets/empty_state.dart';
import '../application/ride_history_providers.dart';
import '../data/ride_history_item.dart';

enum _Filter { all, completed, cancelled }

class RideHistoryScreen extends ConsumerStatefulWidget {
  const RideHistoryScreen({super.key});

  @override
  ConsumerState<RideHistoryScreen> createState() => _RideHistoryScreenState();
}

class _RideHistoryScreenState extends ConsumerState<RideHistoryScreen> {
  final _scrollController = ScrollController();
  _Filter _filter = _Filter.all;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      ref.read(rideHistoryProvider.notifier).loadMore();
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  List<RideHistoryItem> _applyFilter(List<RideHistoryItem> items) {
    switch (_filter) {
      case _Filter.completed:
        return items.where((r) => r.isCompleted).toList();
      case _Filter.cancelled:
        return items.where((r) => r.isCancelled).toList();
      case _Filter.all:
        return items;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(rideHistoryProvider);
    final filtered = _applyFilter(state.items);

    return Scaffold(
      backgroundColor: const Color(0xFF11191D),
      appBar: const CustomAppBar(title: 'Trips History', showBack: false),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                _FilterChip(
                  label: 'All',
                  selected: _filter == _Filter.all,
                  onTap: () => setState(() => _filter = _Filter.all),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Completed',
                  selected: _filter == _Filter.completed,
                  onTap: () => setState(() => _filter = _Filter.completed),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Cancelled',
                  selected: _filter == _Filter.cancelled,
                  onTap: () => setState(() => _filter = _Filter.cancelled),
                ),
              ],
            ),
          ),
          Expanded(
            child: state.loading && state.items.isEmpty
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : state.error != null && state.items.isEmpty
                    ? Center(child: Text(state.error!, style: const TextStyle(color: Color(0xFF94A3B8))))
                    : filtered.isEmpty
                        ? const EmptyState(
                            icon: Icons.receipt_long_outlined,
                            title: 'No trips found',
                            subtitle: 'Your ride history will show up here',
                          )
                        : RefreshIndicator(
                            color: AppColors.primary,
                            backgroundColor: const Color(0xFF222222),
                            onRefresh: () => ref.read(rideHistoryProvider.notifier).loadFirstPage(),
                            child: ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                              itemCount: filtered.length + (state.loadingMore ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (index >= filtered.length) {
                                  return const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 16),
                                    child: Center(child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.primary)),
                                  );
                                }
                                final ride = filtered[index];
                                return _RideHistoryTile(
                                  ride: ride,
                                  onTap: () => context.push('/trip-detail', extra: ride),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : const Color(0xFF222222),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? AppColors.primary : const Color(0xFF2E2E2E)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? const Color(0xFF11191D) : Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _RideHistoryTile extends StatelessWidget {
  final RideHistoryItem ride;
  final VoidCallback onTap;

  const _RideHistoryTile({required this.ride, required this.onTap});

  Color get _statusColor {
    if (ride.isCompleted) return AppColors.primary;
    if (ride.isCancelled) return const Color(0xFFEF4444);
    return const Color(0xFFFFB800);
  }

  @override
  Widget build(BuildContext context) {
    final date = ride.completedAt ?? ride.createdAt;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF222222),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2E2E2E)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        date != null ? '${date.day}/${date.month}/${date.year}' : '—',
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _statusColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        ride.status,
                        style: TextStyle(color: _statusColor, fontSize: 11, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      children: [
                        const SizedBox(height: 4),
                        Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.primary,
                          ),
                        ),
                        Container(width: 1.5, height: 26, color: const Color(0xFF2E2E2E)),
                        Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFFEF4444),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ride.pickupAddress,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            ride.dropAddress,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(color: Color(0xFF2E2E2E), height: 1),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      ride.riderName.isEmpty ? 'Rider' : ride.riderName,
                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '₹${ride.fare.toStringAsFixed(0)}',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: Colors.white),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

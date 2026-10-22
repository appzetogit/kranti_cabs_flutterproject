import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterdriver/core/theme/app_colors.dart';
import 'package:go_router/go_router.dart';
import '../../auth/application/auth_providers.dart';
import '../../ride/data/ride_history_item.dart';
import '../application/earnings_providers.dart';

enum _Period { today, week, month }

class EarningsScreen extends ConsumerStatefulWidget {
  const EarningsScreen({super.key});

  @override
  ConsumerState<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends ConsumerState<EarningsScreen> {
  _Period _period = _Period.today;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final driver = await ref.read(authRepositoryProvider).getCurrentDriver();
      ref.read(authProvider.notifier).updateDriver(driver);
    });
  }

  @override
  Widget build(BuildContext context) {
    final driver = ref.watch(authProvider).driver;
    final ridesAsync = ref.watch(recentRidesProvider);

    // Zero when there is nothing yet, never a sample figure. These previously
    // defaulted to Rs 64 across 3 trips and 6.7 km, which reads as real earnings
    // to a driver who has not completed a trip today.
    final earningsAmount = _amountFor(driver?.todaySummary.earnings ?? 0, ridesAsync.value);
    final tripsCount = _ridesCountFor(driver?.todaySummary.rides ?? 0, ridesAsync.value);
    final distanceKm = (_distanceFor(driver?.todaySummary.distanceMeters ?? 0, ridesAsync.value) / 1000).toStringAsFixed(1);

    // Earnings per km for the selected period; a dash until there is distance.
    final km = double.tryParse(distanceKm) ?? 0;
    final perKmLabel = km > 0 ? '₹${(earningsAmount / km).toStringAsFixed(1)}/km' : '₹—/km';

    // Real period-on-period change, or null when there is nothing to compare
    // against. This badge used to read a fixed "+12% vs yesterday" no matter
    // what the driver had actually earned.
    final growthLabel = _growthLabel(earningsAmount, ridesAsync.value);

    return Scaffold(
      backgroundColor: const Color(0xFF11191D),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          backgroundColor: const Color(0xFF222222),
          onRefresh: () => ref.refresh(recentRidesProvider.future),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              // Top Header Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text(
                    'Earnings',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  Row(
                    children: [
                      // Trophy Icon Button
                      GestureDetector(
                        onTap: () => context.push('/incentives'),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: const Icon(
                            Icons.emoji_events_outlined,
                            color: Color(0xFF1E293B),
                            size: 20,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Wallet Icon Button
                      GestureDetector(
                        onTap: () => context.push('/wallet'),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: const Icon(
                            Icons.account_balance_wallet_outlined,
                            color: Color(0xFF1E293B),
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Royal Dark Blue Hero Card
              Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0F1E40), Color(0xFF1E3A8A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x200F1E40),
                      blurRadius: 12,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _periodLabel(_period),
                              style: const TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '₹${earningsAmount.toStringAsFixed(0)}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                              ),
                            ),
                            if (growthLabel != null) ...[
                              const SizedBox(height: 6),

                              // Percentage Growth Badge
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: growthLabel.isPositive
                                      ? const Color(0xFF064E3B)
                                      : const Color(0xFF4C1D1D),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: growthLabel.isPositive
                                        ? const Color(0xFF047857)
                                        : const Color(0xFF991B1B),
                                  ),
                                ),
                                child: Text(
                                  growthLabel.text,
                                  style: TextStyle(
                                    color: growthLabel.isPositive
                                        ? const Color(0xFF34D399)
                                        : const Color(0xFFFCA5A5),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),

                        // 3D Wallet & Coins Illustration Icon Graphic
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.account_balance_wallet_rounded,
                            color: Color(0xFF60A5FA),
                            size: 32,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    // Stats Row inside Card (Trips & Distance)
                    Row(
                      children: [
                        _StatChip(
                          icon: Icons.directions_car_rounded,
                          label: '$tripsCount Trips',
                        ),
                        const SizedBox(width: 8),
                        _StatChip(
                          icon: Icons.alt_route_rounded,
                          label: '$distanceKm km',
                        ),
                        const SizedBox(width: 8),
                        _StatChip(
                          icon: Icons.currency_rupee_rounded,
                          label: perKmLabel,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Period Filter Tabs
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    _PeriodTab(
                      label: 'Today',
                      isSelected: _period == _Period.today,
                      onTap: () => setState(() => _period = _Period.today),
                    ),
                    _PeriodTab(
                      label: 'This Week',
                      isSelected: _period == _Period.week,
                      onTap: () => setState(() => _period = _Period.week),
                    ),
                    _PeriodTab(
                      label: 'This Month',
                      isSelected: _period == _Period.month,
                      onTap: () => setState(() => _period = _Period.month),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // Recent Trips Header Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Recent Trips',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  TextButton(
                    onPressed: () => context.push('/ride-history'),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'View all',
                      style: TextStyle(
                        color: Color(0xFF0EA4A2),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 6),

              // Recent Trips List
              // Only the driver's own trips, ever. This used to fall back to
              // three sample trips when the period was empty, while loading and
              // on error, and those rows opened as real trip details.
              ridesAsync.when(
                data: (rides) {
                  final filtered = _filterByPeriod(rides, _period);
                  if (filtered.isEmpty) {
                    return _TripsMessage(
                      icon: Icons.directions_car_outlined,
                      message: 'No completed trips ${_periodPhrase(_period)}.',
                    );
                  }

                  return Column(
                    children: filtered
                        .map((ride) => _TripTile(
                              ride: ride,
                              onTap: () => context.push('/trip-detail', extra: ride),
                            ))
                        .toList(),
                  );
                },
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                ),
                error: (error, stack) => _TripsMessage(
                  icon: Icons.cloud_off_rounded,
                  message: "Couldn't load your trips. Check your connection and try again.",
                  actionLabel: 'Retry',
                  onAction: () => ref.invalidate(recentRidesProvider),
                ),
              ),

              const SizedBox(height: 14),

              // Keep Going Incentive Card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFE6F7F0), Color(0xFFD1FAE5)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFA7F3D0)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Keep going! 🎉',
                            style: TextStyle(
                              color: Color(0xFF0F172A),
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          const Text(
                            'You\'re doing great. More trips, more earnings!',
                            style: TextStyle(
                              color: Color(0xFF047857),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Growth Bar Chart Graphic Box
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.trending_up_rounded,
                        color: Color(0xFF00A859),
                        size: 26,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _periodLabel(_Period period) {
    switch (period) {
      case _Period.today:
        return "Today's Earnings";
      case _Period.week:
        return "This Week's Earnings";
      case _Period.month:
        return "This Month's Earnings";
    }
  }

  String _periodPhrase(_Period period) {
    switch (period) {
      case _Period.today:
        return 'today';
      case _Period.week:
        return 'this week';
      case _Period.month:
        return 'this month';
    }
  }

  double _amountFor(double todayEarnings, List<RideHistoryItem>? rides) {
    if (_period == _Period.today) return todayEarnings;
    final list = _filterByPeriod(rides ?? const [], _period);
    if (list.isEmpty) return todayEarnings;
    return list.fold(0.0, (sum, r) => sum + r.driverEarnings);
  }

  int _ridesCountFor(int todayRides, List<RideHistoryItem>? rides) {
    if (_period == _Period.today) return todayRides;
    final list = _filterByPeriod(rides ?? const [], _period);
    if (list.isEmpty) return todayRides;
    return list.length;
  }

  double _distanceFor(double todayDistance, List<RideHistoryItem>? rides) {
    if (_period == _Period.today) return todayDistance;
    final list = _filterByPeriod(rides ?? const [], _period);
    if (list.isEmpty) return todayDistance;
    return list.fold(0.0, (sum, r) => sum + r.estimatedDistanceMeters);
  }

  /// Earnings for the period immediately before the one on screen, so the badge
  /// compares like with like: yesterday for Today, last week for This Week.
  double? _previousPeriodEarnings(List<RideHistoryItem>? rides) {
    if (rides == null || rides.isEmpty) return null;

    final now = DateTime.now();
    final DateTime from;
    final DateTime to;

    switch (_period) {
      case _Period.today:
        to = DateTime(now.year, now.month, now.day);
        from = to.subtract(const Duration(days: 1));
        break;
      case _Period.week:
        final thisWeek = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: now.weekday - 1));
        to = thisWeek;
        from = thisWeek.subtract(const Duration(days: 7));
        break;
      case _Period.month:
        to = DateTime(now.year, now.month, 1);
        from = DateTime(now.year, now.month - 1, 1);
        break;
    }

    final previous = rides.where((ride) {
      final at = ride.completedAt ?? ride.createdAt;
      if (at == null) return false;
      return at.isAfter(from) && at.isBefore(to);
    }).toList();

    if (previous.isEmpty) return null;
    return previous.fold<double>(0, (sum, r) => sum + r.driverEarnings);
  }

  _GrowthLabel? _growthLabel(double current, List<RideHistoryItem>? rides) {
    final previous = _previousPeriodEarnings(rides);
    // Nothing to compare against, or a previous period of zero — a percentage
    // change from zero is not a meaningful number to show a driver.
    if (previous == null || previous <= 0) return null;

    final change = ((current - previous) / previous) * 100;
    final rounded = change.abs().round();
    if (rounded == 0) {
      return _GrowthLabel(text: 'Same as ${_previousPeriodName()}', isPositive: true);
    }

    final sign = change >= 0 ? '+' : '-';
    return _GrowthLabel(
      text: '$sign$rounded% vs ${_previousPeriodName()}',
      isPositive: change >= 0,
    );
  }

  String _previousPeriodName() {
    switch (_period) {
      case _Period.today:
        return 'yesterday';
      case _Period.week:
        return 'last week';
      case _Period.month:
        return 'last month';
    }
  }

  List<RideHistoryItem> _filterByPeriod(List<RideHistoryItem> rides, _Period period) {
    final now = DateTime.now();
    DateTime from;
    switch (period) {
      case _Period.today:
        from = DateTime(now.year, now.month, now.day);
        break;
      case _Period.week:
        from = now.subtract(Duration(days: now.weekday - 1)).let((d) => DateTime(d.year, d.month, d.day));
        break;
      case _Period.month:
        from = DateTime(now.year, now.month, 1);
        break;
    }
    return rides.where((r) => (r.completedAt ?? r.createdAt)?.isAfter(from) ?? false).toList();
  }
}

extension _Let<T> on T {
  R let<R>(R Function(T) block) => block(this);
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _StatChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PeriodTab extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _PeriodTab({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF12DEDC) : Colors.transparent,
            borderRadius: BorderRadius.circular(17),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.black : const Color(0xFF64748B),
              fontSize: 11.5,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _TripTile extends StatelessWidget {
  final RideHistoryItem ride;
  final VoidCallback? onTap;

  const _TripTile({required this.ride, this.onTap});

  @override
  Widget build(BuildContext context) {
    final date = ride.completedAt ?? ride.createdAt;
    final dateStr = date != null
        ? '${date.day} ${_monthName(date.month)} ${date.year} • ${_formatTime(date)}'
        : 'Date not recorded';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(15),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                // Green Car Icon Circle
                Container(
                  width: 38,
                  height: 38,
                  decoration: const BoxDecoration(
                    color: Color(0xFFDCFCE7),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.directions_car_rounded,
                    color: Color(0xFF16A34A),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),

                // Location Title & Date Subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ride.dropAddress.isEmpty ? 'Drop location not recorded' : ride.dropAddress,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        dateStr,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

                // Amount Pill
                Row(
                  children: [
                    Text(
                      '+₹${ride.driverEarnings.toStringAsFixed(0)}',
                      style: const TextStyle(
                        color: Color(0xFF16A34A),
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(width: 3),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: Color(0xFF16A34A),
                      size: 18,
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

  static String _monthName(int m) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[(m - 1).clamp(0, 11)];
  }

  static String _formatTime(DateTime d) {
    final hour = d.hour == 0 ? 12 : (d.hour > 12 ? d.hour - 12 : d.hour);
    final period = d.hour >= 12 ? 'PM' : 'AM';
    final minute = d.minute.toString().padLeft(2, '0');
    return '$hour:$minute $period';
  }
}

/// The earnings badge's text and whether it reads as growth.
class _GrowthLabel {
  final String text;
  final bool isPositive;

  const _GrowthLabel({required this.text, required this.isPositive});
}

/// Stands in for the trip list when there is nothing real to show.
class _TripsMessage extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _TripsMessage({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppColors.darkTextSecondary, size: 26),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.darkTextSecondary,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 6),
            TextButton(
              onPressed: onAction,
              child: Text(
                actionLabel!,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

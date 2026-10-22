import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/loading_widget.dart';
import '../../../shared/widgets/app_bottom_navigation_bar.dart';
import '../data/models/ride_model.dart';
import '../application/ride_history_controller.dart';
import '../application/ride_history_state.dart';
import '../../rental/application/rental_providers.dart';
import '../../rental/data/models/rental_booking_model.dart';
import 'widgets/recent_activity_card.dart';

/// Normalized history entry representing either a Ride or a Rental booking.
class _HistoryEntry {
  final String rideId;
  final String title;
  final String subtitle;
  final String pickup;
  final String drop;
  final DateTime date;
  final double fare;
  final String status;
  final String serviceType;
  final String? vehicleIconType;
  /// Set only for rides booked for a future time.
  final DateTime? scheduledAt;
  final String route;

  const _HistoryEntry({
    required this.rideId,
    required this.title,
    required this.subtitle,
    required this.pickup,
    required this.drop,
    required this.date,
    required this.fare,
    required this.status,
    required this.serviceType,
    this.vehicleIconType,
    this.scheduledAt,
    required this.route,
  });

  factory _HistoryEntry.fromRide(RideModel ride) {
    final serviceType = (ride.serviceType ?? '').toLowerCase();
    final vehicle = ride.vehicleType ?? ride.vehicleIconType ?? '';

    final scheduledFor = ride.scheduledAt;
    final isUpcoming = scheduledFor != null && scheduledFor.isAfter(DateTime.now());

    String title;
    String subtitle;
    if (scheduledFor != null) {
      subtitle = 'SCHEDULED RIDE';
      if (serviceType == 'parcel') {
        title = 'Scheduled Parcel';
      } else if (serviceType == 'intercity' || serviceType == 'outstation') {
        title = 'Scheduled Outstation';
      } else {
        title = vehicle.isEmpty ? 'Scheduled Taxi' : 'Scheduled $vehicle';
      }
    } else if (serviceType == 'parcel') {
      title = 'Parcel Delivery';
      subtitle = 'DELIVERY BOOKING';
    } else if (serviceType == 'intercity' || serviceType == 'outstation') {
      title = 'Outstation Ride';
      subtitle = 'INTERCITY TRIP';
    } else if (serviceType == 'bus') {
      title = 'Bus Booking';
      subtitle = 'BUS TICKET';
    } else {
      title = vehicle.isEmpty ? 'Taxi Ride' : vehicle;
      subtitle = 'CITY TRIP';
    }

    final status = isUpcoming && ride.status.toLowerCase() == 'searching'
        ? 'scheduled'
        : ride.status;

    return _HistoryEntry(
      rideId: ride.rideId,
      title: title,
      subtitle: subtitle,
      pickup: ride.pickupAddress,
      drop: ride.dropAddress,
      date: ride.completedAt ??
          ride.startedAt ??
          ride.acceptedAt ??
          ride.scheduledAt ??
          DateTime.now(),
      fare: ride.fare,
      status: status,
      serviceType: serviceType,
      vehicleIconType: ride.vehicleIconType,
      scheduledAt: ride.scheduledAt,
      route: '/rides/${ride.rideId}',
    );
  }

  factory _HistoryEntry.fromRental(RentalBookingModel booking) {
    return _HistoryEntry(
      rideId: booking.id,
      title: booking.vehicleName.isNotEmpty ? booking.vehicleName : 'Rental Vehicle',
      subtitle: booking.packageLabel.isNotEmpty
          ? booking.packageLabel.toUpperCase()
          : 'RENTAL BOOKING',
      pickup: booking.vehicleName,
      drop: booking.packageLabel,
      date: booking.pickupDateTime ?? booking.createdAt ?? DateTime.now(),
      fare: booking.totalCost,
      status: booking.status,
      serviceType: 'rental',
      route: '/rental/history',
    );
  }
}

class _HistoryFilter {
  final String id;
  final String label;
  final IconData? icon;

  /// Category query sent to backend (null means not fetched from ride API)
  final String? rideCategory;
  final bool includesRentals;

  const _HistoryFilter({
    required this.id,
    required this.label,
    this.icon,
    this.rideCategory,
    this.includesRentals = false,
  });
}

class RideHistoryScreen extends ConsumerStatefulWidget {
  const RideHistoryScreen({super.key});

  @override
  ConsumerState<RideHistoryScreen> createState() => _RideHistoryScreenState();
}

class _RideHistoryScreenState extends ConsumerState<RideHistoryScreen> {
  final _scrollController = ScrollController();

  static const _filters = <_HistoryFilter>[
    _HistoryFilter(
      id: 'all',
      label: 'ALL',
      rideCategory: 'all',
      includesRentals: true,
    ),
    _HistoryFilter(
      id: 'rides',
      label: 'RIDES',
      icon: Icons.directions_car_rounded,
      rideCategory: 'rides',
    ),
    _HistoryFilter(
      id: 'parcels',
      label: 'PARCELS',
      icon: Icons.inventory_2_outlined,
      rideCategory: 'parcels',
    ),
    _HistoryFilter(
      id: 'outstation',
      label: 'OUTSTATION',
      icon: Icons.add_road_rounded,
      rideCategory: 'outstation',
    ),
    _HistoryFilter(
      id: 'rental',
      label: 'RENTAL',
      icon: Icons.car_rental_rounded,
      includesRentals: true,
    ),
    _HistoryFilter(
      id: 'scheduled',
      label: 'SCHEDULED',
      icon: Icons.access_time_rounded,
      rideCategory: 'scheduled',
    ),
  ];

  String _selectedId = 'all';

  _HistoryFilter get _selected =>
      _filters.firstWhere((f) => f.id == _selectedId, orElse: () => _filters.first);

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_selected.rideCategory == null) return;

    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 300) {
      ref.read(rideHistoryControllerProvider.notifier).loadNextPage();
    }
  }

  void _onFilterSelected(String id) {
    if (id == _selectedId) return;
    setState(() => _selectedId = id);

    final filter = _filters.firstWhere((f) => f.id == id);
    if (filter.rideCategory != null) {
      ref.read(rideHistoryControllerProvider.notifier).setCategory(filter.rideCategory!);
    }
  }

  List<_HistoryEntry> _entriesFor(
    _HistoryFilter filter,
    RideHistoryState rideState,
    List<RentalBookingModel> rentals,
  ) {
    final entries = <_HistoryEntry>[];

    if (filter.rideCategory != null) {
      final rides = rideState.rides.map(_HistoryEntry.fromRide);
      if (filter.id == 'all') {
        entries.addAll(rides);
      } else if (filter.id == 'rides') {
        entries.addAll(rides.where((e) =>
            e.serviceType != 'parcel' &&
            e.serviceType != 'intercity' &&
            e.serviceType != 'outstation' &&
            e.serviceType != 'bus' &&
            e.serviceType != 'rental' &&
            e.scheduledAt == null));
      } else if (filter.id == 'parcels') {
        entries.addAll(rides.where((e) => e.serviceType == 'parcel' && e.scheduledAt == null));
      } else if (filter.id == 'outstation') {
        entries.addAll(rides.where((e) =>
            (e.serviceType == 'outstation' || e.serviceType == 'intercity') &&
            e.scheduledAt == null));
      } else if (filter.id == 'bus') {
        entries.addAll(rides.where((e) => e.serviceType == 'bus'));
      } else if (filter.id == 'scheduled') {
        entries.addAll(rides.where((e) => e.scheduledAt != null));
      } else {
        entries.addAll(rides);
      }
    }

    if (filter.includesRentals && (filter.id == 'all' || filter.id == 'rental')) {
      entries.addAll(rentals.map(_HistoryEntry.fromRental));
    }

    entries.sort((a, b) => b.date.compareTo(a.date));
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final rideState = ref.watch(rideHistoryControllerProvider);
    final rentalsAsync = ref.watch(myRentalBookingsProvider);
    final filter = _selected;

    final rentals = rentalsAsync.valueOrNull ?? const <RentalBookingModel>[];

    // Kranti Cabs Dark Palette
    const screenBg = Color(0xFF0F151D);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        context.go('/home');
      },
      child: Scaffold(
        backgroundColor: screenBg,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: const Text(
            'MY BOOKINGS',
            style: TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          centerTitle: false,
          titleSpacing: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 21),
            onPressed: () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              } else {
                context.go('/home');
              }
            },
          ),
        ),
        bottomNavigationBar: const AppBottomNavigationBar(currentIndex: 2),
        body: Stack(
          children: [
            // Ambient city skyline watermark at the bottom matching reference screenshot
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 180,
              child: IgnorePointer(
                child: Opacity(
                  opacity: 0.22,
                  child: Image.asset(
                    'assets/kranti_bookings_hero.jpg',
                    fit: BoxFit.cover,
                    alignment: Alignment.bottomCenter,
                    errorBuilder: (c, e, s) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),

            // Main Content
            SafeArea(
              top: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Hero Header Row: Title & Subtitle + Car on Bridge
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 2, 16, 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Left text
                        Expanded(
                          flex: 11,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              RichText(
                                text: const TextSpan(
                                  children: [
                                    TextSpan(
                                      text: 'My ',
                                      style: TextStyle(
                                        fontSize: 28,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                    TextSpan(
                                      text: 'Bookings',
                                      style: TextStyle(
                                        fontSize: 28,
                                        fontWeight: FontWeight.w900,
                                        color: Color(0xFFF5B400),
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 5),
                              const Text(
                                'Track all your rides, rentals and bookings in one place',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: Color(0xFF94A3B8),
                                  fontWeight: FontWeight.w500,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Right car banner
                        Expanded(
                          flex: 9,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: ShaderMask(
                              shaderCallback: (bounds) {
                                return const LinearGradient(
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                  colors: [Colors.transparent, Colors.black, Colors.black],
                                  stops: [0.0, 0.2, 1.0],
                                ).createShader(bounds);
                              },
                              blendMode: BlendMode.dstIn,
                              child: Image.asset(
                                'assets/kranti_bookings_hero.jpg',
                                height: 86,
                                fit: BoxFit.cover,
                                errorBuilder: (c, e, s) => const SizedBox.shrink(),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Capsule Filters Bar
                  _FilterBar(
                    filters: _filters,
                    selectedId: _selectedId,
                    onSelected: _onFilterSelected,
                  ),

                  // Body Content (Empty State Hero Card or Active List)
                  Expanded(
                    child: _buildBody(filter, rideState, rentals, rentalsAsync.isLoading),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    _HistoryFilter filter,
    RideHistoryState rideState,
    List<RentalBookingModel> rentals,
    bool rentalsLoading,
  ) {
    final loading = filter.rideCategory != null
        ? rideState.isLoading
        : rentalsLoading;
    if (loading) {
      return const LoadingWidget(message: 'Loading your bookings…');
    }

    final entries = _entriesFor(filter, rideState, rentals);

    if (entries.isEmpty && rideState.error != null && filter.rideCategory != null) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
          child: EmptyState(
            icon: Icons.error_outline_rounded,
            title: 'Could not load your bookings',
            message: 'Please check your connection and try again.',
            actionLabel: 'Retry',
            onAction: _refresh,
          ),
        ),
      );
    }

    // EMPTY STATE: 1:1 match with user's reference screenshot
    if (entries.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 26),
            decoration: BoxDecoration(
              color: const Color(0xFF131A24),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: const Color(0xFF232D3B), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 3D Illustration matching reference design
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.asset(
                    'assets/empty_bookings.jpg',
                    height: 200,
                    fit: BoxFit.contain,
                    errorBuilder: (c, e, s) => Container(
                      height: 180,
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.search_rounded,
                        size: 80,
                        color: Color(0xFFF5B400),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                // Title: "No Bookings Yet"
                RichText(
                  textAlign: TextAlign.center,
                  text: const TextSpan(
                    children: [
                      TextSpan(
                        text: 'No Bookings ',
                        style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: -0.4,
                        ),
                      ),
                      TextSpan(
                        text: 'Yet',
                        style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFFF5B400),
                          letterSpacing: -0.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // Subtitle
                Text(
                  filter.id == 'all'
                      ? "You haven't made any bookings yet.\nPlan your next ride, rental or outstation trip\nwith Kranti Cabs."
                      : "You don't have any ${filter.label.toLowerCase()} bookings yet.\nPlan your next ride with Kranti Cabs.",
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF94A3B8),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 24),

                // Solid Gold CTA Button: "Book a Ride Now ->"
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => context.go('/home'),
                    borderRadius: BorderRadius.circular(26),
                    child: Ink(
                      width: double.infinity,
                      height: 52,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5B400),
                        borderRadius: BorderRadius.circular(26),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFF5B400).withValues(alpha: 0.35),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.directions_car_rounded,
                            color: Color(0xFF0A0A0A),
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Book a Ride Now',
                            style: TextStyle(
                              color: Color(0xFF0A0A0A),
                              fontWeight: FontWeight.w900,
                              fontSize: 15.5,
                              letterSpacing: -0.2,
                            ),
                          ),
                          SizedBox(width: 8),
                          Icon(
                            Icons.arrow_forward_rounded,
                            color: Color(0xFF0A0A0A),
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final showFooterLoader = filter.rideCategory != null && rideState.isLoadingMore;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: entries.length + (showFooterLoader ? 1 : 0),
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index >= entries.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: CircularProgressIndicator(
                  color: Color(0xFFF5B400),
                ),
              ),
            );
          }

          final entry = entries[index];
          return RecentActivityCard(
            title: entry.title,
            subtitle: entry.subtitle,
            pickup: entry.pickup,
            drop: entry.drop,
            date: entry.date,
            fare: entry.fare,
            status: entry.status,
            serviceType: entry.serviceType,
            vehicleIconType: entry.vehicleIconType,
            onTap: () {
              if (entry.route.isNotEmpty) {
                context.push(entry.route);
              }
            },
          );
        },
      ),
    );
  }

  Future<void> _refresh() async {
    ref.invalidate(myRentalBookingsProvider);
    if (_selected.rideCategory != null) {
      await ref.read(rideHistoryControllerProvider.notifier).loadFirstPage();
    }
  }
}

class _FilterBar extends StatelessWidget {
  final List<_HistoryFilter> filters;
  final String selectedId;
  final ValueChanged<String> onSelected;

  const _FilterBar({
    required this.filters,
    required this.selectedId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.transparent,
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: filters.map((filter) {
            final selected = filter.id == selectedId;
            final bg = selected ? const Color(0xFFF5B400) : const Color(0xFF18202A);
            final fg = selected ? const Color(0xFF0A0A0A) : Colors.white;
            final border = selected ? Colors.transparent : const Color(0xFF263242);

            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => onSelected(filter.id),
                  borderRadius: BorderRadius.circular(22),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8.5),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: border, width: 1.2),
                      boxShadow: selected
                          ? [
                              BoxShadow(
                                color: const Color(0xFFF5B400).withValues(alpha: 0.28),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (filter.icon != null) ...[
                          Icon(
                            filter.icon,
                            size: 15,
                            color: fg,
                          ),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          filter.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: fg,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

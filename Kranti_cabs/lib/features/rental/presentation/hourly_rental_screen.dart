import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/snackbar_utils.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../../home/application/booking_controller.dart';
import '../../home/application/booking_state.dart';
import '../../home/application/home_providers.dart';
import '../../home/presentation/schedule_ride_sheet.dart';
import '../application/rental_providers.dart';
import '../data/hourly_rental.dart';

const _gold = Color(0xFFF5B400);
const _card = Color(0xFF222222);
const _border = Color(0xFF2E2E2E);
const _muted = Color(0xFF94A3B8);

/// Hourly rental with a driver: pick up from a point, choose a package and a
/// cab, ride now or later. No drop - the trip ends wherever the rider ends it.
/// Time and km beyond the package are billed by the server at the end.
class HourlyRentalScreen extends ConsumerStatefulWidget {
  const HourlyRentalScreen({super.key});

  @override
  ConsumerState<HourlyRentalScreen> createState() => _HourlyRentalScreenState();
}

class _HourlyRentalScreenState extends ConsumerState<HourlyRentalScreen> {
  BookingLocation? _pickup;
  String? _packageId, _vehicleTypeId;
  DateTime? _scheduledAt;
  bool _booking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _useCurrentLocation());
  }

  Future<void> _useCurrentLocation() async {
    final pos = await ref.read(currentPositionProvider.future);
    if (pos == null || !mounted || _pickup != null) return;
    final address = await ref.read(currentAddressProvider.future);
    if (!mounted || _pickup != null) return;
    setState(() => _pickup = BookingLocation(
          lat: pos.latitude,
          lng: pos.longitude,
          address: address.isEmpty ? 'Current Location' : address,
        ));
  }

  Future<void> _changePickup() async {
    final result = await context.push<Object?>('/home/map-picker?type=pickup');
    if (result is! Map || !mounted) return;
    final lat = (result['lat'] as num?)?.toDouble();
    final lng = (result['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return;
    final address = (result['address'] as String?)?.trim() ?? '';
    setState(() {
      _pickup = BookingLocation(
        lat: lat,
        lng: lng,
        address: address.isNotEmpty ? address : '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
      );
      // City prices can differ: the list reloads for the new pickup.
      _packageId = null;
      _vehicleTypeId = null;
    });
  }

  Future<void> _pickTime() async {
    final selected = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF11191D),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => Padding(padding: const EdgeInsets.all(20), child: ScheduleRideSheet(initial: _scheduledAt)),
    );
    if (selected == null) return; // dismissed: keep what was set
    setState(() => _scheduledAt = identical(selected, ScheduleRideSheet.rideNow) ? null : selected);
  }

  String _key(BookingLocation p) => '${p.lat.toStringAsFixed(2)},${p.lng.toStringAsFixed(2)}';

  Future<void> _book(HourlyRentalPackage pkg, HourlyRentalVehicle vehicle) async {
    final pickup = _pickup;
    if (pickup == null || _booking) return;
    setState(() => _booking = true);
    final controller = ref.read(bookingControllerProvider.notifier);
    try {
      var attempt = await controller.bookHourlyRental(
        pickup: pickup, package: pkg, vehicle: vehicle, scheduledAt: _scheduledAt);
      if (attempt == BookingAttempt.kycRequired && mounted) {
        final review = ref.read(bookingControllerProvider).error?.toLowerCase().contains('review') ?? false;
        if (!review && await context.push<bool>('/profile/verify-identity', extra: true) == true) {
          attempt = await controller.bookHourlyRental(
            pickup: pickup, package: pkg, vehicle: vehicle, scheduledAt: _scheduledAt);
        }
      }
      if (!mounted) return;
      switch (attempt) {
        case BookingAttempt.booked:
          if (_scheduledAt != null) {
            // A reservation has no search to watch.
            controller.reset();
            SnackbarUtils.success(context, 'Rental scheduled. We will tell you when a driver is assigned.');
            context.go('/rides');
          } else {
            context.pushReplacement('/home/finding-driver');
          }
        case BookingAttempt.failed:
          context.pushReplacement('/home/no-driver');
        case BookingAttempt.notReady:
        case BookingAttempt.kycRequired:
          final message = ref.read(bookingControllerProvider).error;
          if (message != null) SnackbarUtils.error(context, message);
          // The cab may have been switched off for rentals: reload the list.
          ref.invalidate(hourlyPackagesProvider);
      }
    } finally {
      if (mounted) setState(() => _booking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pickup = _pickup;
    return Scaffold(
      backgroundColor: const Color(0xFF11191D),
      appBar: const CustomAppBar(title: 'Hourly Rental'),
      body: pickup == null
          ? _pickupMissing()
          : ref.watch(hourlyPackagesProvider(_key(pickup))).when(
                loading: () => const Center(child: CircularProgressIndicator(color: _gold)),
                error: (_, _) => _message('Could not load rental packages.', retry: true),
                data: (packages) => packages.isEmpty
                    ? _message('Rentals are not available at this pickup yet.')
                    : _content(pickup, packages),
              ),
    );
  }

  Widget _pickupMissing() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Choose where the car should pick you up',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 16)),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _gold, foregroundColor: Colors.black),
              onPressed: _changePickup,
              child: const Text('Set pickup'),
            ),
          ]),
        ),
      );

  Widget _message(String text, {bool retry = false}) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(text, textAlign: TextAlign.center, style: const TextStyle(color: _muted, fontSize: 15)),
            if (retry) TextButton(onPressed: () => ref.invalidate(hourlyPackagesProvider), child: const Text('Retry')),
            TextButton(onPressed: _changePickup, child: const Text('Change pickup')),
          ]),
        ),
      );

  Widget _content(BookingLocation pickup, List<HourlyRentalPackage> packages) {
    final pkg = packages.firstWhere((p) => p.id == _packageId, orElse: () => packages.first);
    final vehicle = pkg.vehicles.firstWhere((v) => v.vehicleTypeId == _vehicleTypeId, orElse: () => pkg.vehicles.first);

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _pickupTile(pickup),
              const SizedBox(height: 18),
              const Text('Choose a package', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final p in packages)
                  ChoiceChip(
                    label: Text('${p.name} · from ₹${p.startingPrice.round()}'),
                    selected: p.id == pkg.id,
                    selectedColor: _gold,
                    backgroundColor: _card,
                    labelStyle: TextStyle(color: p.id == pkg.id ? Colors.black : Colors.white, fontSize: 12.5),
                    onSelected: (_) => setState(() {
                      _packageId = p.id;
                      _vehicleTypeId = null;
                    }),
                  ),
              ]),
              if (pkg.description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(pkg.description, style: const TextStyle(color: _muted, fontSize: 12.5)),
              ],
              const SizedBox(height: 18),
              const Text('Choose a cab', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              for (final v in pkg.vehicles) _vehicleTile(v, selected: v.vehicleTypeId == vehicle.vehicleTypeId),
              const SizedBox(height: 6),
              Text(
                'Beyond the package: ₹${vehicle.extraKmRate}/km and ₹${vehicle.extraMinuteRate}/min. Tolls and parking are extra.',
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: _border),
                  minimumSize: const Size.fromHeight(44),
                ),
                icon: const Icon(Icons.schedule_rounded, size: 18),
                label: Text(_scheduledAt == null ? 'Ride now · tap for Ride later' : 'Ride later · ${_fmt(_scheduledAt!)}'),
                onPressed: _booking ? null : _pickTime,
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _gold,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _booking ? null : () => _book(pkg, vehicle),
                  child: _booking
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black))
                      : Text('Book ${vehicle.vehicleName} · ₹${vehicle.price.round()}',
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                ),
              ),
              const SizedBox(height: 4),
              const Text('Pay by cash at the end of the trip', style: TextStyle(color: _muted, fontSize: 11.5)),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _pickupTile(BookingLocation pickup) => InkWell(
        onTap: _changePickup,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14), border: Border.all(color: _border)),
          child: Row(children: [
            const Icon(Icons.my_location_rounded, color: _gold),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('PICKUP', style: TextStyle(color: _gold, fontSize: 10.5, fontWeight: FontWeight.w900)),
                Text(pickup.address, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ]),
            ),
            const Icon(Icons.edit_outlined, color: _muted, size: 18),
          ]),
        ),
      );

  Widget _vehicleTile(HourlyRentalVehicle v, {required bool selected}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: InkWell(
          onTap: () => setState(() => _vehicleTypeId = v.vehicleTypeId),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: selected ? _gold : _border, width: selected ? 1.6 : 1),
            ),
            child: Row(children: [
              SizedBox(
                width: 56,
                height: 40,
                child: v.iconUrl.isEmpty
                    ? const Icon(Icons.directions_car_rounded, color: _muted)
                    : Image.network(v.iconUrl, fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const Icon(Icons.directions_car_rounded, color: _muted)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(v.vehicleName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                  Text('${v.category}${v.capacity > 0 ? ' · ${v.capacity} seats' : ''}',
                      style: const TextStyle(color: _muted, fontSize: 12)),
                  Text('${v.includes} · ${v.extras}', style: const TextStyle(color: _muted, fontSize: 11)),
                ]),
              ),
              Text('₹${v.price.round()}', style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
            ]),
          ),
        ),
      );

  String _fmt(DateTime d) {
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final t = TimeOfDay.fromDateTime(d).format(context);
    return '${d.day} ${m[d.month - 1]}, $t';
  }
}

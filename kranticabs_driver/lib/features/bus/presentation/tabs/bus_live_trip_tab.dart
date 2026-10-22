import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/core_providers.dart';
import '../../../../core/utils/snackbar_utils.dart';
import '../../application/bus_auth_providers.dart';
import '../../application/bus_operate_providers.dart';
import '../../data/models/bus_driver_models.dart';
import '../../data/models/bus_operate_models.dart';
import '../bus_ui.dart';

/// Tab 2 — start/manage the live trip and push the bus location so riders (and
/// admin) can track it.
class BusLiveTripTab extends ConsumerStatefulWidget {
  const BusLiveTripTab({super.key});

  @override
  ConsumerState<BusLiveTripTab> createState() => _BusLiveTripTabState();
}

class _BusLiveTripTabState extends ConsumerState<BusLiveTripTab> {
  String? _scheduleId;
  DateTime _date = DateTime.now();
  bool _busy = false;
  String _status = 'idle';
  Timer? _locationTimer;

  @override
  void initState() {
    super.initState();
    // While a trip is running, push the location every 20s so tracking stays
    // live without draining the battery.
    _locationTimer = Timer.periodic(const Duration(seconds: 20), (_) => _pushLocation(silent: true));
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    super.dispose();
  }

  Future<void> _pushLocation({bool silent = false}) async {
    if (_status != 'in_progress') return;
    try {
      final pos = await ref.read(locationServiceProvider).getCurrentPosition();
      await ref.read(busDriverRepositoryProvider).updateLiveLocation(
            lat: pos.latitude,
            lng: pos.longitude,
            speedKmph: pos.speed * 3.6,
          );
      if (!silent) {
        ref.invalidate(busLiveTripProvider);
        if (mounted) SnackbarUtils.success('Location updated');
      }
    } catch (_) {
      if (!silent && mounted) SnackbarUtils.error('Could not update location');
    }
  }

  Future<void> _start() async {
    final id = _scheduleId;
    if (id == null) {
      SnackbarUtils.error('Select a schedule first');
      return;
    }
    setState(() => _busy = true);
    try {
      double? lat, lng;
      try {
        final pos = await ref.read(locationServiceProvider).getCurrentPosition();
        lat = pos.latitude;
        lng = pos.longitude;
      } catch (_) {/* start without a fix; location updates follow */}
      await ref.read(busDriverRepositoryProvider).startLiveTrip(
            scheduleId: id,
            travelDate: _date,
            lat: lat,
            lng: lng,
          );
      ref.invalidate(busLiveTripProvider);
      if (mounted) SnackbarUtils.success('Trip started');
    } catch (e) {
      if (mounted) {
        SnackbarUtils.error(e.toString().toLowerCase().contains('pending')
            ? 'Your account or bus is not active yet.'
            : 'Could not start the trip.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _action(String action, String okMsg) async {
    setState(() => _busy = true);
    try {
      await ref.read(busDriverRepositoryProvider).updateLiveStatus(action);
      ref.invalidate(busLiveTripProvider);
      if (mounted) SnackbarUtils.success(okMsg);
    } catch (_) {
      if (mounted) SnackbarUtils.error('Could not update the trip');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(busAuthProvider).profile;
    final schedules = profile?.busService?.schedules ?? const <BusSchedule>[];
    _scheduleId ??= schedules.isNotEmpty ? schedules.first.id : null;

    final async = ref.watch(busLiveTripProvider);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator(color: BusColors.teal)),
      error: (e, _) => _errorView(e),
      data: (trip) {
        _status = trip.status;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _statusCard(trip),
            const SizedBox(height: 14),
            if (trip.isIdle || trip.isCompleted) ...[
              _scheduleSelector(schedules),
              const SizedBox(height: 14),
            ],
            _controls(trip),
          ],
        );
      },
    );
  }

  Widget _statusCard(BusLiveTrip trip) {
    final color = trip.isRunning
        ? BusColors.teal
        : (trip.isPaused ? const Color(0xFFF59E0B) : BusColors.textMuted);
    final label = trip.isRunning
        ? 'LIVE'
        : (trip.isPaused ? 'PAUSED' : (trip.isCompleted ? 'COMPLETED' : 'NOT STARTED'));
    return BusCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 14)),
              const Spacer(),
              if (trip.isRunning)
                TextButton.icon(
                  onPressed: () => _pushLocation(),
                  icon: const Icon(Icons.my_location_rounded, size: 16, color: BusColors.teal),
                  label: const Text('Update', style: TextStyle(color: BusColors.teal)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _metric('Speed', '${trip.speedKmph.toStringAsFixed(0)} km/h'),
              _metric('Distance', '${trip.totalDistanceKm.toStringAsFixed(1)} km'),
              _metric('Updated', _time(trip.lastUpdatedAt)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: BusColors.textMuted, fontSize: 11)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _scheduleSelector(List<BusSchedule> schedules) {
    if (schedules.isEmpty) {
      return const BusCard(
        child: Text('Add a schedule in the Schedules tab to start a trip.',
            style: TextStyle(color: BusColors.textMuted)),
      );
    }
    return BusCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Trip schedule',
              style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: schedules.map((s) {
              final active = _scheduleId == s.id;
              final label = s.departureTime.isNotEmpty ? s.departureTime : s.label;
              return GestureDetector(
                onTap: () => setState(() => _scheduleId = s.id),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: active ? BusColors.teal : BusColors.bg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: active ? BusColors.teal : BusColors.border),
                  ),
                  child: Text(label.isNotEmpty ? label : 'Trip',
                      style: TextStyle(
                          color: active ? const Color(0xFF053B38) : BusColors.textMuted,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5)),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: _pickDate,
            child: Row(
              children: [
                const Icon(Icons.calendar_month_rounded, color: BusColors.teal, size: 18),
                const SizedBox(width: 8),
                Text(_prettyDate(_date),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _controls(BusLiveTrip trip) {
    if (trip.isIdle || trip.isCompleted) {
      return BusBottomBarInline(label: 'Start Trip', loading: _busy, onTap: _start);
    }
    if (trip.isPaused) {
      return Row(
        children: [
          Expanded(child: BusBottomBarInline(label: 'Resume', loading: _busy, onTap: () => _action('resume', 'Trip resumed'))),
          const SizedBox(width: 12),
          Expanded(
            child: BusBottomBarInline(
              label: 'Complete',
              loading: _busy,
              danger: true,
              onTap: () => _action('complete', 'Trip completed'),
            ),
          ),
        ],
      );
    }
    // running
    return Row(
      children: [
        Expanded(child: BusBottomBarInline(label: 'Pause', loading: _busy, onTap: () => _action('pause', 'Trip paused'))),
        const SizedBox(width: 12),
        Expanded(
          child: BusBottomBarInline(
            label: 'Complete',
            loading: _busy,
            danger: true,
            onTap: () => _action('complete', 'Trip completed'),
          ),
        ),
      ],
    );
  }

  Widget _errorView(Object e) {
    final pending = e.toString().toLowerCase().contains('pending');
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 70, 24, 24),
      children: [
        const Icon(Icons.my_location_rounded, color: BusColors.textMuted, size: 52),
        const SizedBox(height: 14),
        Text(
          pending ? 'Your account or bus is not active yet.' : 'Could not load live trip.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: BusColors.textMuted, fontSize: 14),
        ),
        const SizedBox(height: 14),
        Center(
          child: TextButton(
            onPressed: () => ref.invalidate(busLiveTripProvider),
            child: const Text('Retry', style: TextStyle(color: BusColors.teal)),
          ),
        ),
      ],
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isBefore(now) ? now : _date,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 30)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  String _prettyDate(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${months[d.month - 1]}, ${d.year}';
  }

  String _time(DateTime? dt) {
    if (dt == null) return '—';
    final l = dt.toLocal();
    final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
    final m = l.minute.toString().padLeft(2, '0');
    return '$h:$m ${l.hour < 12 ? 'AM' : 'PM'}';
  }
}

/// A standalone action button sized for inline use (not a bottom bar).
class BusBottomBarInline extends StatelessWidget {
  final String label;
  final bool loading;
  final bool danger;
  final VoidCallback? onTap;

  const BusBottomBarInline({
    super.key,
    required this.label,
    this.loading = false,
    this.danger = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger ? const Color(0xFFEF4444) : BusColors.teal;
    final disabled = onTap == null || loading;
    return Opacity(
      opacity: disabled ? 0.6 : 1,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: disabled ? null : onTap,
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            height: 52,
            child: Center(
              child: loading
                  ? const SizedBox(
                      height: 20, width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                  : Text(label,
                      style: TextStyle(
                          color: danger ? Colors.white : const Color(0xFF053B38),
                          fontSize: 15,
                          fontWeight: FontWeight.w800)),
            ),
          ),
        ),
      ),
    );
  }
}

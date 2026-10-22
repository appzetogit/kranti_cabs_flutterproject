import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/bus_auth_providers.dart';
import '../../application/bus_operate_providers.dart';
import '../../data/models/bus_driver_models.dart';
import '../../data/models/bus_operate_models.dart';
import '../bus_ui.dart';

/// Tab 1 — the passenger manifest for a schedule + date, with a shortcut to add
/// a counter (cash) booking.
class BusManifestTab extends ConsumerStatefulWidget {
  const BusManifestTab({super.key});

  @override
  ConsumerState<BusManifestTab> createState() => _BusManifestTabState();
}

class _BusManifestTabState extends ConsumerState<BusManifestTab> {
  String? _scheduleId;
  DateTime _date = DateTime.now();

  String get _ymd =>
      '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(busAuthProvider).profile;
    final schedules = profile?.busService?.schedules ?? const <BusSchedule>[];
    _scheduleId ??= schedules.isNotEmpty ? schedules.first.id : null;

    return Column(
      children: [
        _topBar(profile?.busService?.busName ?? 'Manifest'),
        if (schedules.isNotEmpty) _scheduleBar(schedules),
        _dateBar(),
        Expanded(
          child: (_scheduleId == null)
              ? _empty('Your bus has no schedules yet. Add one in the Schedules tab.')
              : _manifestList(_scheduleId!),
        ),
      ],
    );
  }

  Widget _topBar(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Row(
        children: [
          const Icon(Icons.event_seat_rounded, color: BusColors.teal, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: BusColors.textMuted),
            onPressed: () {
              if (_scheduleId != null) {
                ref.invalidate(busManifestProvider((scheduleId: _scheduleId!, date: _ymd)));
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _scheduleBar(List<BusSchedule> schedules) {
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: schedules.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final s = schedules[i];
          final active = _scheduleId == s.id;
          final label = s.departureTime.isNotEmpty ? s.departureTime : (s.label.isNotEmpty ? s.label : 'Trip ${i + 1}');
          return GestureDetector(
            onTap: () => setState(() => _scheduleId = s.id),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? BusColors.teal : BusColors.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: active ? BusColors.teal : BusColors.border),
              ),
              child: Text(label,
                  style: TextStyle(
                      color: active ? const Color(0xFF053B38) : BusColors.textMuted,
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
            ),
          );
        },
      ),
    );
  }

  Widget _dateBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: BusCard(
              onTap: _pickDate,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.calendar_month_rounded, color: BusColors.teal, size: 18),
                  const SizedBox(width: 10),
                  Text(_prettyDate(_date),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  const Icon(Icons.expand_more_rounded, color: BusColors.textMuted, size: 18),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Material(
            color: BusColors.teal,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _scheduleId == null
                  ? null
                  : () => context.push('/bus-add-booking', extra: {'scheduleId': _scheduleId, 'date': _ymd}),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                child: Row(
                  children: [
                    Icon(Icons.add_rounded, color: Color(0xFF053B38), size: 18),
                    SizedBox(width: 4),
                    Text('Booking',
                        style: TextStyle(color: Color(0xFF053B38), fontWeight: FontWeight.w800, fontSize: 13)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _manifestList(String scheduleId) {
    final async = ref.watch(busManifestProvider((scheduleId: scheduleId, date: _ymd)));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator(color: BusColors.teal)),
      error: (e, _) => _empty(
        e.toString().toLowerCase().contains('pending')
            ? 'Your account or bus is not active yet.'
            : 'Could not load the manifest.',
      ),
      data: (list) {
        if (list.isEmpty) return _empty('No bookings for this trip yet.');
        final seatCount = list.fold<int>(0, (a, b) => a + b.seatLabels.length);
        return RefreshIndicator(
          color: BusColors.teal,
          onRefresh: () async => ref.refresh(busManifestProvider((scheduleId: scheduleId, date: _ymd)).future),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              Text('${list.length} booking(s) · $seatCount seat(s)',
                  style: const TextStyle(color: BusColors.textMuted, fontSize: 12)),
              const SizedBox(height: 10),
              ...list.map(_bookingCard),
            ],
          ),
        );
      },
    );
  }

  Widget _bookingCard(BusDriverBooking booking) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: BusCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(booking.passengerName.isNotEmpty ? booking.passengerName : 'Passenger',
                      style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w700)),
                ),
                BusTag(
                  label: booking.isCounterBooking ? 'Counter' : 'Online',
                  color: booking.isCounterBooking ? const Color(0xFFF59E0B) : BusColors.teal,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.event_seat_rounded, color: BusColors.textMuted, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('Seats ${booking.seatLabels.join(", ")}',
                      style: const TextStyle(color: Colors.white, fontSize: 12.5)),
                ),
                Text(busMoney(booking.amount, booking.currency),
                    style: const TextStyle(color: BusColors.teal, fontSize: 13, fontWeight: FontWeight.w800)),
              ],
            ),
            if (booking.passengerPhone.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.call_rounded, color: BusColors.textMuted, size: 13),
                  const SizedBox(width: 6),
                  Text(booking.passengerPhone,
                      style: const TextStyle(color: BusColors.textMuted, fontSize: 12)),
                  const Spacer(),
                  Text('PNR ${booking.bookingCode}',
                      style: const TextStyle(color: BusColors.textMuted, fontSize: 11)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isBefore(now) ? now : _date,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 60)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Widget _empty(String message) => ListView(
        padding: const EdgeInsets.fromLTRB(24, 70, 24, 24),
        children: [
          const Icon(Icons.inbox_rounded, color: BusColors.textMuted, size: 52),
          const SizedBox(height: 14),
          Text(message,
              textAlign: TextAlign.center, style: const TextStyle(color: BusColors.textMuted, fontSize: 14)),
        ],
      );

  String _prettyDate(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]}';
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/snackbar_utils.dart';
import '../../application/bus_auth_providers.dart';
import '../../data/models/bus_driver_models.dart';
import '../bus_ui.dart';

/// Tab 3 — view and edit the bus's departure schedules.
class BusSchedulesTab extends ConsumerStatefulWidget {
  const BusSchedulesTab({super.key});

  @override
  ConsumerState<BusSchedulesTab> createState() => _BusSchedulesTabState();
}

class _BusSchedulesTabState extends ConsumerState<BusSchedulesTab> {
  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  List<BusSchedule>? _schedules;
  bool _saving = false;
  bool _loadedFor = false;

  List<BusSchedule> _seed() {
    final profile = ref.read(busAuthProvider).profile;
    return List<BusSchedule>.from(profile?.busService?.schedules ?? const <BusSchedule>[]);
  }

  @override
  Widget build(BuildContext context) {
    // Seed the editable copy once from the profile.
    if (!_loadedFor) {
      _schedules = _seed();
      _loadedFor = true;
    }
    final list = _schedules ?? const <BusSchedule>[];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Row(
            children: [
              const Icon(Icons.schedule_rounded, color: BusColors.teal, size: 22),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Schedules',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
              ),
              TextButton.icon(
                onPressed: _addSchedule,
                icon: const Icon(Icons.add_rounded, size: 18, color: BusColors.teal),
                label: const Text('Add', style: TextStyle(color: BusColors.teal)),
              ),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? _empty()
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) => _scheduleCard(i, list[i]),
                ),
        ),
        BusBottomBar(actionLabel: 'Save Schedules', isLoading: _saving, onPressed: _save),
      ],
    );
  }

  Widget _empty() => ListView(
        padding: const EdgeInsets.fromLTRB(24, 70, 24, 24),
        children: [
          const Icon(Icons.schedule_rounded, color: BusColors.textMuted, size: 52),
          const SizedBox(height: 14),
          const Text('No schedules yet. Tap "Add" to create your first departure.',
              textAlign: TextAlign.center, style: TextStyle(color: BusColors.textMuted, fontSize: 14)),
        ],
      );

  Widget _scheduleCard(int index, BusSchedule s) {
    return BusCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(s.label.isNotEmpty ? s.label : 'Departure ${index + 1}',
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
              ),
              GestureDetector(
                onTap: () => _toggleStatus(index),
                child: BusTag(
                  label: s.status.toLowerCase() == 'paused' ? 'Paused' : 'Active',
                  color: s.status.toLowerCase() == 'paused' ? const Color(0xFFF59E0B) : BusColors.teal,
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _remove(index),
                child: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 20),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _timeField('Departure', s.departureTime, (t) => _setTime(index, departure: t))),
              const SizedBox(width: 12),
              Expanded(child: _timeField('Arrival', s.arrivalTime, (t) => _setTime(index, arrival: t))),
            ],
          ),
          const SizedBox(height: 12),
          const Text('Runs on', style: TextStyle(color: BusColors.textMuted, fontSize: 11, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _days.map((d) {
              final on = s.activeDays.contains(d);
              return GestureDetector(
                onTap: () => _toggleDay(index, d),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: on ? BusColors.teal : BusColors.bg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: on ? BusColors.teal : BusColors.border),
                  ),
                  child: Text(d,
                      style: TextStyle(
                          color: on ? const Color(0xFF053B38) : BusColors.textMuted,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700)),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _timeField(String label, String value, void Function(String) onPick) {
    return InkWell(
      onTap: () async {
        final parts = value.split(':');
        final initial = TimeOfDay(
          hour: int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 9,
          minute: int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0,
        );
        final picked = await showTimePicker(context: context, initialTime: initial);
        if (picked != null) {
          onPick('${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: BusColors.bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: BusColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: BusColors.textMuted, fontSize: 11)),
            const SizedBox(height: 2),
            Text(value.isEmpty ? '--:--' : value,
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  void _update(int index, BusSchedule next) {
    final list = List<BusSchedule>.from(_schedules ?? const []);
    list[index] = next;
    setState(() => _schedules = list);
  }

  void _setTime(int index, {String? departure, String? arrival}) {
    final s = _schedules![index];
    _update(index, s.copyWith(departureTime: departure, arrivalTime: arrival));
  }

  void _toggleStatus(int index) {
    final s = _schedules![index];
    _update(index, s.copyWith(status: s.status.toLowerCase() == 'paused' ? 'active' : 'paused'));
  }

  void _toggleDay(int index, String day) {
    final s = _schedules![index];
    final days = List<String>.from(s.activeDays);
    if (days.contains(day)) {
      days.remove(day);
    } else {
      days.add(day);
    }
    _update(index, s.copyWith(activeDays: days));
  }

  void _remove(int index) {
    final list = List<BusSchedule>.from(_schedules ?? const []);
    list.removeAt(index);
    setState(() => _schedules = list);
  }

  void _addSchedule() {
    final list = List<BusSchedule>.from(_schedules ?? const []);
    list.add(BusSchedule(
      id: 'sch_${DateTime.now().millisecondsSinceEpoch}',
      label: 'Departure ${list.length + 1}',
      departureTime: '09:00',
      arrivalTime: '18:00',
      activeDays: const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
      status: 'active',
    ));
    setState(() => _schedules = list);
  }

  Future<void> _save() async {
    final list = _schedules ?? const <BusSchedule>[];
    setState(() => _saving = true);
    try {
      await ref.read(busDriverRepositoryProvider).updateSchedules(list);
      await ref.read(busAuthProvider.notifier).refreshProfile();
      if (!mounted) return;
      SnackbarUtils.success('Schedules saved');
    } catch (e) {
      if (!mounted) return;
      SnackbarUtils.error(e.toString().toLowerCase().contains('pending')
          ? 'Your account or bus is not active yet.'
          : 'Could not save schedules.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/snackbar_utils.dart';
import '../application/bus_auth_providers.dart';
import '../application/bus_operate_providers.dart';
import '../data/models/bus_operate_models.dart';
import 'bus_ui.dart';

/// Counter (cash) booking by the driver — pick seats and enter passenger.
class BusAddBookingScreen extends ConsumerStatefulWidget {
  final String scheduleId;
  final String date; // YYYY-MM-DD

  const BusAddBookingScreen({super.key, required this.scheduleId, required this.date});

  @override
  ConsumerState<BusAddBookingScreen> createState() => _BusAddBookingScreenState();
}

class _BusAddBookingScreenState extends ConsumerState<BusAddBookingScreen> {
  final _selected = <String>{};
  final _name = TextEditingController();
  final _age = TextEditingController();
  final _phone = TextEditingController();
  String _gender = 'Male';
  bool _upper = false;
  bool _submitting = false;

  @override
  void dispose() {
    _name.dispose();
    _age.dispose();
    _phone.dispose();
    super.dispose();
  }

  BusManifestQuery get _q => (scheduleId: widget.scheduleId, date: widget.date);

  Future<void> _submit() async {
    if (_selected.isEmpty) {
      SnackbarUtils.error('Select at least one seat');
      return;
    }
    final name = _name.text.trim();
    final age = int.tryParse(_age.text.trim()) ?? 0;
    final phone = _phone.text.trim();
    if (name.isEmpty || age < 1 || phone.length < 10) {
      SnackbarUtils.error('Enter passenger name, age and mobile');
      return;
    }
    setState(() => _submitting = true);
    try {
      final date = DateTime.tryParse(widget.date) ?? DateTime.now();
      await ref.read(busDriverRepositoryProvider).createReservation(
            scheduleId: widget.scheduleId,
            travelDate: date,
            seatIds: _selected.toList(),
            name: name,
            age: age,
            gender: _gender,
            phone: phone,
          );
      ref.invalidate(busManifestProvider(_q));
      ref.invalidate(busDriverSeatsProvider(_q));
      if (!mounted) return;
      SnackbarUtils.success('Booking added');
      context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      final msg = e.toString().toLowerCase();
      SnackbarUtils.error(msg.contains('409') || msg.contains('conflict')
          ? 'A selected seat was just taken. Pick again.'
          : 'Could not add booking.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(busDriverSeatsProvider(_q));
    return BusScaffold(
      title: 'Add Booking',
      bottomBar: BusBottomBar(
        actionLabel: _selected.isEmpty ? 'Select seats' : 'Confirm ${_selected.length} seat(s)',
        isLoading: _submitting,
        onPressed: _selected.isEmpty ? null : _submit,
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator(color: BusColors.teal)),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              e.toString().toLowerCase().contains('pending')
                  ? 'Your account or bus is not active yet.'
                  : 'Could not load the seat map.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: BusColors.textMuted),
            ),
          ),
        ),
        data: (layout) {
          final deck = _upper ? layout.upperDeck : layout.lowerDeck;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              if (layout.hasUpperDeck) _deckTabs(),
              _legend(),
              const SizedBox(height: 8),
              ...deck.map(_seatRow),
              const SizedBox(height: 20),
              const Text('Passenger',
                  style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              BusField(controller: _name, label: 'Name', hint: 'Passenger name', icon: Icons.person_rounded),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: BusField(
                      controller: _age,
                      label: 'Age',
                      hint: 'Age',
                      icon: Icons.cake_rounded,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: BusField(
                      controller: _phone,
                      label: 'Mobile',
                      hint: '10-digit',
                      icon: Icons.call_rounded,
                      keyboardType: TextInputType.phone,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: ['Male', 'Female', 'Other'].map((g) {
                  final active = _gender == g;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => setState(() => _gender = g),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: active ? BusColors.tealDark : BusColors.card,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: active ? BusColors.teal : BusColors.border),
                          ),
                          child: Text(g,
                              style: TextStyle(
                                  color: active ? BusColors.teal : BusColors.textMuted,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13)),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _deckTabs() {
    Widget tab(String label, bool active, VoidCallback onTap) => Expanded(
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: active ? BusColors.teal : Colors.transparent, width: 2),
                ),
              ),
              child: Text(label,
                  style: TextStyle(
                      color: active ? BusColors.teal : BusColors.textMuted, fontWeight: FontWeight.w700)),
            ),
          ),
        );
    return Row(children: [
      tab('Lower Deck', !_upper, () => setState(() => _upper = false)),
      tab('Upper Deck', _upper, () => setState(() => _upper = true)),
    ]);
  }

  Widget _legend() {
    Widget item(Color c, String label, {Color? border}) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: c,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: border ?? c),
              ),
            ),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: BusColors.textMuted, fontSize: 11)),
          ],
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          item(Colors.transparent, 'Available', border: BusColors.textMuted),
          item(BusColors.teal, 'Selected'),
          item(BusColors.booked, 'Sold'),
        ],
      ),
    );
  }

  Widget _seatRow(List<BusDriverSeatCell> row) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: row.map(_seatCell).toList(),
      ),
    );
  }

  Widget _seatCell(BusDriverSeatCell cell) {
    if (!cell.isSeat) return const SizedBox(width: 34, height: 40);
    final selected = _selected.contains(cell.id);
    final available = cell.isAvailable;

    Color bg;
    Color borderColor;
    Color fg;
    if (!available) {
      bg = BusColors.booked;
      borderColor = BusColors.booked;
      fg = BusColors.textMuted;
    } else if (selected) {
      bg = BusColors.teal;
      borderColor = BusColors.teal;
      fg = const Color(0xFF053B38);
    } else {
      bg = Colors.transparent;
      borderColor = BusColors.textMuted;
      fg = Colors.white;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: GestureDetector(
        onTap: available
            ? () => setState(() {
                  if (selected) {
                    _selected.remove(cell.id);
                  } else {
                    _selected.add(cell.id);
                  }
                })
            : null,
        child: Container(
          width: cell.isSleeper ? 54 : 34,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor, width: 1.4),
          ),
          child: Text(cell.label, style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}

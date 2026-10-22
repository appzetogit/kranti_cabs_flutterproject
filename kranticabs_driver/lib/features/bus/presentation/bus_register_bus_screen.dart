import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/snackbar_utils.dart';
import '../application/bus_onboarding_providers.dart';
import '../data/models/bus_driver_models.dart';
import 'bus_ui.dart';

/// Step 4 of registration — join an existing bus or create a new one, then
/// submit for approval.
class BusRegisterBusScreen extends ConsumerStatefulWidget {
  const BusRegisterBusScreen({super.key});

  @override
  ConsumerState<BusRegisterBusScreen> createState() => _BusRegisterBusScreenState();
}

class _BusRegisterBusScreenState extends ConsumerState<BusRegisterBusScreen> {
  bool _createNew = false;
  String? _selectedBusId;
  bool _loading = false;

  final _operator = TextEditingController();
  final _busName = TextEditingController();
  final _serviceNo = TextEditingController();
  final _from = TextEditingController();
  final _to = TextEditingController();

  @override
  void dispose() {
    _operator.dispose();
    _busName.dispose();
    _serviceNo.dispose();
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final notifier = ref.read(busOnboardingProvider.notifier);
    setState(() => _loading = true);
    try {
      if (_createNew) {
        final op = _operator.text.trim();
        final bn = _busName.text.trim();
        final from = _from.text.trim();
        final to = _to.text.trim();
        if (op.isEmpty || bn.isEmpty || from.isEmpty || to.isEmpty) {
          SnackbarUtils.error('Fill operator, bus name, from and to');
          setState(() => _loading = false);
          return;
        }
        await notifier.createBus(
          operatorName: op,
          busName: bn,
          originCity: from,
          destinationCity: to,
          serviceNumber: _serviceNo.text.trim(),
        );
      } else {
        if (_selectedBusId == null) {
          SnackbarUtils.error('Select a bus to join');
          setState(() => _loading = false);
          return;
        }
        await notifier.joinBus(_selectedBusId!);
      }
      final profile = await notifier.complete();
      if (!mounted) return;
      // Fresh signups are pending until an admin approves them.
      context.go(profile.canOperate ? '/bus-home' : '/bus-pending');
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      final msg = e.toString().toLowerCase();
      SnackbarUtils.error(
        msg.contains('already') ? 'This number already has a bus account.' : 'Could not submit. Please try again.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BusScaffold(
      title: 'Your Bus',
      bottomBar: BusBottomBar(actionLabel: 'Submit for Approval', isLoading: _loading, onPressed: _submit),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        children: [
          _modeTabs(),
          const SizedBox(height: 16),
          if (_createNew) _createForm() else _joinList(),
        ],
      ),
    );
  }

  Widget _modeTabs() {
    Widget tab(String label, bool active, VoidCallback onTap) => Expanded(
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 11),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? BusColors.teal : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(label,
                  style: TextStyle(
                      color: active ? const Color(0xFF053B38) : BusColors.textMuted,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5)),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: BusColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: BusColors.border),
      ),
      child: Row(
        children: [
          tab('Join a bus', !_createNew, () => setState(() => _createNew = false)),
          tab('Add my bus', _createNew, () => setState(() => _createNew = true)),
        ],
      ),
    );
  }

  Widget _joinList() {
    final async = ref.watch(busSignupOptionsProvider);
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.only(top: 40),
        child: Center(child: CircularProgressIndicator(color: BusColors.teal)),
      ),
      error: (e, _) => const Padding(
        padding: EdgeInsets.only(top: 40),
        child: Text('Could not load buses. Switch to "Add my bus".',
            textAlign: TextAlign.center, style: TextStyle(color: BusColors.textMuted)),
      ),
      data: (list) {
        if (list.isEmpty) {
          return const Padding(
            padding: EdgeInsets.only(top: 30),
            child: Text('No buses available to join yet. Use "Add my bus" to register your own.',
                textAlign: TextAlign.center, style: TextStyle(color: BusColors.textMuted)),
          );
        }
        return Column(
          children: list.map(_busOption).toList(),
        );
      },
    );
  }

  Widget _busOption(BusSignupOption o) {
    final selected = _selectedBusId == o.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: BusCard(
        onTap: () => setState(() => _selectedBusId = o.id),
        borderColor: selected ? BusColors.teal : BusColors.border,
        color: selected ? BusColors.tealDark : BusColors.card,
        child: Row(
          children: [
            Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                color: selected ? BusColors.teal : BusColors.textMuted, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(o.busName.isNotEmpty ? o.busName : o.operatorName,
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (o.operatorName.isNotEmpty) o.operatorName,
                      if (o.originCity.isNotEmpty || o.destinationCity.isNotEmpty)
                        '${o.originCity} → ${o.destinationCity}',
                    ].join('  ·  '),
                    style: const TextStyle(color: BusColors.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _createForm() {
    return Column(
      children: [
        BusField(controller: _operator, label: 'Operator name', hint: 'e.g. SRS Travels', icon: Icons.business_rounded),
        const SizedBox(height: 14),
        BusField(controller: _busName, label: 'Bus name', hint: 'e.g. Volvo AC Sleeper', icon: Icons.directions_bus_rounded),
        const SizedBox(height: 14),
        BusField(controller: _serviceNo, label: 'Service number (optional)', hint: 'e.g. SRS-204', icon: Icons.tag_rounded),
        const SizedBox(height: 14),
        BusField(controller: _from, label: 'From city', hint: 'Origin', icon: Icons.my_location_rounded),
        const SizedBox(height: 14),
        BusField(controller: _to, label: 'To city', hint: 'Destination', icon: Icons.location_on_rounded),
        const SizedBox(height: 14),
        const BusCard(
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded, color: BusColors.textMuted, size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Your bus is created as a draft. An admin will review and activate it, then set seats, pricing and schedules.',
                  style: TextStyle(color: BusColors.textMuted, fontSize: 12.5, height: 1.4),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

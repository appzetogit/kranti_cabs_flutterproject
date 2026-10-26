import 'package:flutter/material.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/secondary_button.dart';

/// "Ride later": pick a pickup time 30 minutes to 30 days out.
///
/// Pops the chosen time, [ScheduleRideSheet.rideNow] for "Ride now instead",
/// or null when dismissed - so closing the sheet keeps the time already set
/// rather than clearing it.
class ScheduleRideSheet extends StatefulWidget {
  final DateTime? initial;
  const ScheduleRideSheet({super.key, this.initial});

  /// Returned by "Ride now instead".
  static final DateTime rideNow = DateTime.fromMillisecondsSinceEpoch(0);

  /// Earliest pickup, as on Ola / Uber. The server takes anything 15 minutes
  /// out; this leaves room for the time spent booking.
  static const Duration minLead = Duration(minutes: 30);

  @override
  State<ScheduleRideSheet> createState() => _ScheduleRideSheetState();
}

class _ScheduleRideSheetState extends State<ScheduleRideSheet> {
  DateTime? _selected;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
  }

  bool get _tooSoon =>
      _selected != null && _selected!.isBefore(DateTime.now().add(ScheduleRideSheet.minLead));

  Future<void> _pick() async {
    final now = DateTime.now();
    final earliest = now.add(ScheduleRideSheet.minLead);
    final initial = _selected != null && _selected!.isAfter(earliest)
        ? _selected!
        : earliest.add(const Duration(minutes: 15));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(earliest.year, earliest.month, earliest.day),
      lastDate: now.add(const Duration(days: 30)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    setState(() {
      _selected = DateTime(date.year, date.month, date.day, time.hour, time.minute);
      _error = _tooSoon ? 'Pick a time at least 30 minutes from now' : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Ride later', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          _selected != null
              ? '${_selected!.day}/${_selected!.month}/${_selected!.year} at ${TimeOfDay.fromDateTime(_selected!).format(context)}'
              : 'Pick a date & time for your ride',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 6),
        Text(
          _error ??
              'Drivers can take it in advance - you are notified when one is assigned, and again when they head to you.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: _error != null ? theme.colorScheme.error : null,
          ),
        ),
        const SizedBox(height: 16),
        SecondaryButton(label: 'Choose date & time', onPressed: _pick),
        const SizedBox(height: 20),
        Row(
          children: [
            if (widget.initial != null || _selected != null) ...[
              Expanded(
                child: SecondaryButton(
                  label: 'Ride now instead',
                  onPressed: () => Navigator.of(context).pop(ScheduleRideSheet.rideNow),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: PrimaryButton(
                label: 'Confirm',
                onPressed: _selected == null
                    ? null
                    : () {
                        if (_tooSoon) {
                          setState(() => _error = 'Pick a time at least 30 minutes from now');
                          return;
                        }
                        Navigator.of(context).pop(_selected);
                      },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

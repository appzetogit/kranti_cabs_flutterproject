import 'package:flutter/material.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/secondary_button.dart';

class ScheduleRideSheet extends StatefulWidget {
  final DateTime? initial;
  const ScheduleRideSheet({super.key, this.initial});

  @override
  State<ScheduleRideSheet> createState() => _ScheduleRideSheetState();
}

class _ScheduleRideSheetState extends State<ScheduleRideSheet> {
  DateTime? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
  }

  Future<void> _pick() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _selected ?? now.add(const Duration(minutes: 30)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selected ?? now.add(const Duration(minutes: 30))),
    );
    if (time == null) return;
    setState(() {
      _selected = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Ride later', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          _selected != null
              ? '${_selected!.day}/${_selected!.month}/${_selected!.year} at ${TimeOfDay.fromDateTime(_selected!).format(context)}'
              : 'Pick a date & time for your ride',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        SecondaryButton(label: 'Choose date & time', onPressed: _pick),
        const SizedBox(height: 20),
        Row(
          children: [
            if (_selected != null) ...[
              Expanded(
                child: SecondaryButton(
                  label: 'Ride now instead',
                  onPressed: () => Navigator.of(context).pop(null),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: PrimaryButton(
                label: 'Confirm',
                onPressed: _selected == null ? null : () => Navigator.of(context).pop(_selected),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

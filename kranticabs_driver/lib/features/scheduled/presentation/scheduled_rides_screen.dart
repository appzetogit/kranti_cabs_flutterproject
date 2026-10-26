import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/snackbar_utils.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../application/scheduled_rides_providers.dart';
import '../data/scheduled_ride.dart';

/// Rides booked for later: the driver's own (with the time to be there and a
/// way to give one back) and open ones they can take in advance.
///
/// A ride here is not a trip yet. Thirty minutes before pickup the server
/// sends a "head out now" reminder and the ride opens as the active trip;
/// at pickup time a second reminder follows if they have not set off.
class ScheduledRidesScreen extends ConsumerStatefulWidget {
  const ScheduledRidesScreen({super.key});

  @override
  ConsumerState<ScheduledRidesScreen> createState() => _ScheduledRidesScreenState();
}

class _ScheduledRidesScreenState extends ConsumerState<ScheduledRidesScreen> {
  String? _busyRideId;

  Future<void> _run(String rideId, Future<void> Function() action, String done) async {
    if (_busyRideId != null) return;
    setState(() => _busyRideId = rideId);
    try {
      await action();
      SnackbarUtils.success(done);
    } on ApiException catch (error) {
      SnackbarUtils.error(error.message);
    } catch (_) {
      SnackbarUtils.error('Something went wrong. Please try again.');
    } finally {
      ref.invalidate(scheduledRidesProvider);
      if (mounted) setState(() => _busyRideId = null);
    }
  }

  Future<void> _accept(ScheduledRide ride) async {
    final ok = await _confirm(
      'Take this scheduled ride?',
      'Pickup ${_when(ride.scheduledAt)}. You will be reminded 30 minutes before, and it opens as your trip then.',
      'Take ride',
    );
    if (!ok) return;
    await _run(
      ride.rideId,
      () => ref.read(scheduledRidesRepositoryProvider).accept(ride.rideId),
      'Ride accepted for ${_when(ride.scheduledAt)}',
    );
  }

  Future<void> _cancel(ScheduledRide ride) async {
    final ok = await _confirm(
      'Give back this ride?',
      'The rider is told straight away and the ride goes back to other drivers.',
      'Give back',
    );
    if (!ok) return;
    await _run(
      ride.rideId,
      () => ref.read(scheduledRidesRepositoryProvider).cancel(ride.rideId),
      'Scheduled ride cancelled',
    );
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Not now')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text(action)),
        ],
      ),
    );
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    final rides = ref.watch(scheduledRidesProvider);
    return Scaffold(
      appBar: const CustomAppBar(title: 'Scheduled Rides'),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(scheduledRidesProvider.future),
        child: rides.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => ListView(
            children: const [
              SizedBox(height: 120),
              Center(child: Text('Could not load scheduled rides. Pull down to try again.')),
            ],
          ),
          data: (list) {
            final mine = list.where((r) => r.isMine).toList();
            final open = list.where((r) => !r.isMine).toList();
            if (list.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 120),
                  Icon(Icons.event_available_rounded, size: 48, color: Color(0xFF94A3B8)),
                  SizedBox(height: 12),
                  Center(child: Text('No scheduled rides right now.', style: TextStyle(fontWeight: FontWeight.w700))),
                  SizedBox(height: 4),
                  Center(child: Text('Rides booked for later in your area show up here.')),
                ],
              );
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (mine.isNotEmpty) ...[
                  const _SectionTitle('Your scheduled rides'),
                  for (final ride in mine)
                    _RideCard(
                      ride: ride,
                      busy: _busyRideId == ride.rideId,
                      actionLabel: 'Give back',
                      actionColor: AppColors.error,
                      onAction: () => _cancel(ride),
                    ),
                  const SizedBox(height: 8),
                ],
                if (open.isNotEmpty) ...[
                  const _SectionTitle('Open - take one in advance'),
                  for (final ride in open)
                    _RideCard(
                      ride: ride,
                      busy: _busyRideId == ride.rideId,
                      actionLabel: 'Take ride',
                      actionColor: AppColors.primary,
                      onAction: () => _accept(ride),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

String _when(DateTime? at) {
  if (at == null) return '';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(at.year, at.month, at.day);
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final hour = at.hour % 12 == 0 ? 12 : at.hour % 12;
  final time = '$hour:${at.minute.toString().padLeft(2, '0')} ${at.hour < 12 ? 'AM' : 'PM'}';
  final diff = day.difference(today).inDays;
  final dayText = diff == 0 ? 'Today' : diff == 1 ? 'Tomorrow' : '${at.day} ${months[at.month - 1]}';
  return '$dayText, $time';
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
      );
}

class _RideCard extends StatelessWidget {
  final ScheduledRide ride;
  final bool busy;
  final String actionLabel;
  final Color actionColor;
  final VoidCallback onAction;

  const _RideCard({
    required this.ride,
    required this.busy,
    required this.actionLabel,
    required this.actionColor,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final km = ride.distanceMeters > 0 ? '${(ride.distanceMeters / 1000).toStringAsFixed(1)} km · ' : '';
    final tag = ride.isOutstation
        ? (ride.isRoundTrip
            ? 'Outstation · Round trip${ride.returnAt != null ? ' · Return ${_when(ride.returnAt)}' : ''}'
            : 'Outstation · One way')
        : ride.serviceType == 'hourly_rental'
            ? 'Hourly rental'
            : (ride.serviceType == 'parcel' ? 'Parcel' : 'City ride');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.event_rounded, size: 18, color: Color(0xFFB45309)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _when(ride.scheduledAt),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
              Text('₹${ride.fare.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '$tag · $km${ride.paymentMethod.toUpperCase()}',
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          _Place(icon: Icons.trip_origin_rounded, color: const Color(0xFF16A34A), text: ride.pickupAddress),
          const SizedBox(height: 6),
          _Place(icon: Icons.location_on_rounded, color: const Color(0xFFDC2626), text: ride.dropAddress),
          if (ride.isMine && ride.riderName.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Rider: ${ride.riderName}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
                : TextButton(
                    onPressed: onAction,
                    style: TextButton.styleFrom(foregroundColor: actionColor),
                    child: Text(actionLabel, style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Place extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _Place({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text.isEmpty ? '-' : text, style: const TextStyle(fontSize: 13))),
        ],
      );
}

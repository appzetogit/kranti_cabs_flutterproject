import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../data/opportunity_models.dart';
import 'opportunity_style.dart';
import 'surge_pill_icon.dart';

/// Details for one area, opened by tapping a hexagon or "Go to".
///
/// Aggregates only - riders waiting and drivers free. Nothing here identifies
/// a rider, and no other driver's position is shown.
void showOpportunitySheet(
  BuildContext context, {
  required OpportunityMap map,
  OpportunityCell? cell,
  Hotspot? hotspot,
  VoidCallback? onShowOnMap,
}) {
  // A tapped cell borrows the hotspot's example fare and name when it is one.
  Hotspot? matching = hotspot;
  if (matching == null && cell != null) {
    for (final candidate in map.hotspots) {
      if (candidate.hex == cell.hex) {
        matching = candidate;
        break;
      }
    }
  }
  if (cell == null && matching == null) return;
  // A final copy: Dart only narrows a nullable type on a variable that is not
  // reassigned, and the sheet's builder closes over it.
  final match = matching;

  final title = (cell?.label.isNotEmpty == true ? cell!.label : match?.title) ?? '';
  final multiplier = cell?.multiplier ?? match?.multiplier ?? 1;
  final endsAt = cell?.surgeEndsAt != null
      ? map.toLocalClock(cell!.surgeEndsAt!)
      : (match != null && match.isSurging)
          ? map.receivedAt.add(Duration(minutes: match.surgeEndsInMinutes))
          : null;

  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _OpportunitySheet(
      title: title,
      center: cell?.center ?? match!.center,
      multiplier: multiplier,
      maxMultiplier: map.maxMultiplier,
      endsAt: endsAt,
      demand: cell?.demand ?? match?.demand ?? DemandIntensity.normal,
      riders: cell?.riders,
      freeDrivers: cell?.freeDrivers,
      distanceKm: cell?.distanceKm ?? match?.distanceKm,
      exampleFare: match?.exampleFare,
      onShowOnMap: onShowOnMap,
    ),
  );
}

class _OpportunitySheet extends StatefulWidget {
  final String title;
  final LatLng center;
  final double multiplier;
  final double maxMultiplier;
  final DateTime? endsAt;
  final DemandIntensity demand;
  final int? riders;
  final int? freeDrivers;
  final double? distanceKm;
  final ExampleFare? exampleFare;
  final VoidCallback? onShowOnMap;

  const _OpportunitySheet({
    required this.title,
    required this.center,
    required this.multiplier,
    required this.maxMultiplier,
    required this.endsAt,
    required this.demand,
    required this.riders,
    required this.freeDrivers,
    required this.distanceKm,
    required this.exampleFare,
    required this.onShowOnMap,
  });

  @override
  State<_OpportunitySheet> createState() => _OpportunitySheetState();
}

class _OpportunitySheetState extends State<_OpportunitySheet> {
  Timer? _ticker;

  bool get _surging => widget.multiplier > 1;

  @override
  void initState() {
    super.initState();
    // Only the countdown changes; once a second is all it needs.
    if (widget.endsAt != null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String? get _countdown {
    final endsAt = widget.endsAt;
    if (endsAt == null) return null;
    final left = endsAt.difference(DateTime.now());
    if (left.isNegative) return 'Surge ended';
    final minutes = left.inMinutes;
    final seconds = left.inSeconds % 60;
    return 'Ends in $minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// Turn-by-turn straight away (Android), else the directions page - the
  /// same order the active-ride screen uses.
  Future<void> _navigate() async {
    final lat = widget.center.latitude;
    final lng = widget.center.longitude;
    final turnByTurn = Uri.parse('google.navigation:q=$lat,$lng&mode=d');
    if (await canLaunchUrl(turnByTurn)) {
      await launchUrl(turnByTurn, mode: LaunchMode.externalApplication);
      return;
    }
    final directions = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');
    await launchUrl(directions, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final accent = _surging
        ? SurgePillIcon.colorFor(widget.multiplier, max: widget.maxMultiplier)
        : OpportunityStyle.demandColor(widget.demand);
    final countdown = _countdown;
    final ended = countdown == 'Surge ended';
    final distance = OpportunityStyle.distanceLabel(widget.distanceKm);
    final fare = widget.exampleFare;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 14, 20, 20 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: Color(0xFF222222),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(color: const Color(0xFF334155), borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            widget.title.isNotEmpty ? widget.title : (distance.isNotEmpty ? distance : 'This area'),
            style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800),
          ),
          if (widget.title.isNotEmpty && distance.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(distance, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5)),
          ],
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _surging && !ended ? '${SurgePillIcon.labelFor(widget.multiplier)} fares' : OpportunityStyle.demandLabel(widget.demand),
                style: TextStyle(color: accent, fontSize: 26, fontWeight: FontWeight.w900),
              ),
              const Spacer(),
              if (countdown != null)
                Text(
                  countdown,
                  style: TextStyle(
                    color: ended ? const Color(0xFF94A3B8) : Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          if (widget.riders != null && widget.freeDrivers != null) ...[
            const SizedBox(height: 8),
            Text(
              '${widget.riders} rider${widget.riders == 1 ? '' : 's'} looking · '
              '${widget.freeDrivers} driver${widget.freeDrivers == 1 ? '' : 's'} free nearby',
              style: const TextStyle(color: Color(0xFFB6C2D2), fontSize: 13),
            ),
          ],
          if (fare != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF11191D),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF2E2E2E)),
              ),
              child: Text.rich(
                TextSpan(
                  style: const TextStyle(color: Color(0xFFB6C2D2), fontSize: 13),
                  children: [
                    TextSpan(
                      text: '₹${fare.now}',
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900),
                    ),
                    TextSpan(text: ' for a ${fare.km.toStringAsFixed(0)} km trip'),
                    if (fare.extra > 0) TextSpan(text: ' (normally ₹${fare.normal})'),
                    if (fare.vehicle.isNotEmpty) TextSpan(text: ' · ${fare.vehicle}'),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              if (widget.onShowOnMap != null) ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onShowOnMap,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFF334155)),
                      minimumSize: const Size(0, 46),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(23)),
                    ),
                    child: const Text('Show on map', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _navigate,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: const Color(0xFF11191D),
                    elevation: 0,
                    minimumSize: const Size(0, 46),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(23)),
                  ),
                  icon: const Icon(Icons.navigation_rounded, size: 18),
                  label: const Text('Navigate', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
          if (_surging) ...[
            const SizedBox(height: 10),
            const Text(
              'Surge can end before you arrive. You are paid the fare the rider is quoted when they book.',
              style: TextStyle(color: Color(0xFF7C8BA1), fontSize: 11, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'opportunity_style.dart';
import 'surge_pill_icon.dart';

/// Compact key for the map.
///
/// Sits at the top of the map deliberately: the bottom of the screen is where
/// the summary card and the driver's own position live.
class HeatmapLegend extends StatelessWidget {
  final double maxMultiplier;

  const HeatmapLegend({super.key, this.maxMultiplier = 1.5});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFF222222).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF2E2E2E)),
        boxShadow: const [
          BoxShadow(color: Color(0x55000000), blurRadius: 14, offset: Offset(0, 4)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _LegendSwatch(
            colors: [
              SurgePillIcon.colorFor(1.05, max: maxMultiplier),
              SurgePillIcon.colorFor(maxMultiplier, max: maxMultiplier),
            ],
            label: 'Surge',
          ),
          const _LegendSwatch(colors: [OpportunityStyle.veryHighDemand], label: 'Very busy'),
          const _LegendSwatch(colors: [OpportunityStyle.highDemand], label: 'Busy'),
          const _LegendSwatch(colors: [OpportunityStyle.normal], label: 'Normal'),
        ],
      ),
    );
  }
}

class _LegendSwatch extends StatelessWidget {
  final List<Color> colors;
  final String label;

  const _LegendSwatch({required this.colors, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: colors.length > 1 ? 20 : 11,
          height: 11,
          decoration: BoxDecoration(
            gradient: colors.length > 1 ? LinearGradient(colors: colors) : null,
            color: colors.length == 1 ? colors.first.withValues(alpha: 0.85) : null,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

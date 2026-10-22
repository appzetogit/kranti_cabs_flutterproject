import 'package:flutter/material.dart';

import '../data/opportunity_models.dart';
import 'surge_pill_icon.dart';

/// Colours for the surge & demand map, in one place so the map, the legend,
/// the sheet and the Home card always agree.
///
/// Surge is warm (orange to red, by multiplier); demand without a surge is
/// cool (violet), so a driver can tell "pays more here" from "busy here" at a
/// glance. Fills stay translucent: street names must read through them.
class OpportunityStyle {
  OpportunityStyle._();

  static const Color highDemand = Color(0xFF8B5CF6);
  static const Color veryHighDemand = Color(0xFFC026D3);
  static const Color airport = Color(0xFF38BDF8);

  /// The quiet grid around the driver: present, but out of the way.
  static const Color normal = Color(0xFF94A3B8);

  static Color demandColor(DemandIntensity level) =>
      level == DemandIntensity.veryHigh ? veryHighDemand : highDemand;

  static Color cellColor(OpportunityCell cell, {double maxMultiplier = 1.5}) {
    if (cell.isSurging) return SurgePillIcon.colorFor(cell.multiplier, max: maxMultiplier);
    if (cell.demand == DemandIntensity.normal) return normal;
    return demandColor(cell.demand);
  }

  static String demandLabel(DemandIntensity level) {
    switch (level) {
      case DemandIntensity.veryHigh:
        return 'Very high demand';
      case DemandIntensity.high:
        return 'High demand';
      case DemandIntensity.normal:
        return 'Normal demand';
    }
  }

  static String distanceLabel(double? km) {
    if (km == null) return '';
    if (km < 1) return '${(km * 1000).round()} m away';
    return '${km.toStringAsFixed(km < 10 ? 1 : 0)} km away';
  }
}

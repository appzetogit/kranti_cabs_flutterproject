/// Hourly-rental block on a ride. Null for every other service type.
/// [settledAt] != null means the bill is final and the ride's fare already
/// includes the extra km / time charges.
class RideRental {
  final String packagePriceId, packageName;
  final num packagePrice, includedKm, includedMinutes, extraKmRate, extraMinuteRate;
  final num travelledKm, usedMinutes, extraKm, extraMinutes, extraKmCharge, extraTimeCharge;
  final DateTime? settledAt;

  bool get isSettled => settledAt != null;

  static RideRental? maybe(dynamic j) =>
      (j is Map && '${j['packagePriceId'] ?? ''}'.isNotEmpty)
          ? RideRental._(Map<String, dynamic>.from(j))
          : null;

  RideRental._(Map<String, dynamic> j)
      : packagePriceId = '${j['packagePriceId']}',
        packageName = '${j['packageName'] ?? ''}',
        packagePrice = _n(j['packagePrice']),
        includedKm = _n(j['includedKm']),
        includedMinutes = _n(j['includedMinutes']),
        extraKmRate = _n(j['extraKmRate']),
        extraMinuteRate = _n(j['extraMinuteRate']),
        travelledKm = _n(j['travelledKm']),
        usedMinutes = _n(j['usedMinutes']),
        extraKm = _n(j['extraKm']),
        extraMinutes = _n(j['extraMinutes']),
        extraKmCharge = _n(j['extraKmCharge']),
        extraTimeCharge = _n(j['extraTimeCharge']),
        settledAt = j['settledAt'] != null ? DateTime.tryParse('${j['settledAt']}') : null;

  static num _n(dynamic v) => v is num ? v : num.tryParse('${v ?? ''}') ?? 0;

  /// "1 hr / 10 km" style label for the included package.
  String get includedLabel {
    final h = includedMinutes / 60;
    final time = includedMinutes % 60 == 0 ? '${h.toInt()} hr' : '$includedMinutes min';
    return '$time / ${includedKm.toInt()} km';
  }
}

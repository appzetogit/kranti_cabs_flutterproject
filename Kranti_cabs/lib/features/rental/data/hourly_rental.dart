import '../../../core/constants/app_constants.dart';

num _n(dynamic v) => v is num ? v : num.tryParse('${v ?? ''}') ?? 0;

/// One cab offered under an hourly-rental package, with its own price.
class HourlyRentalVehicle {
  final String vehicleTypeId, vehicleName, category, icon, iconType;
  final int capacity;
  final num price, includedKm, includedMinutes, extraKmRate, extraMinuteRate;

  HourlyRentalVehicle.fromJson(Map<String, dynamic> j)
      : vehicleTypeId = '${j['vehicleTypeId'] ?? ''}',
        vehicleName = '${j['vehicleName'] ?? 'Vehicle'}',
        category = '${j['category'] ?? ''}',
        icon = '${j['icon'] ?? ''}',
        iconType = '${j['iconType'] ?? ''}',
        capacity = _n(j['capacity']).toInt(),
        price = _n(j['price']),
        includedKm = _n(j['includedKm']),
        includedMinutes = _n(j['includedMinutes']),
        extraKmRate = _n(j['extraKmRate']),
        extraMinuteRate = _n(j['extraMinuteRate']);

  /// Icon paths can be relative ("/vehicles/dzire.jpg").
  String get iconUrl {
    if (icon.isEmpty || icon.startsWith('http')) return icon;
    return '${AppConstants.mediaBaseUrl}/${icon.replaceFirst(RegExp(r'^/+'), '')}';
  }

  String get includes => 'Includes ${_hours(includedMinutes)} / ${includedKm.toInt()} km';
  String get extras => 'Extra ₹${extraKmRate}/km, ₹${extraMinuteRate}/min';

  static String _hours(num minutes) {
    final h = minutes / 60;
    return minutes % 60 == 0 ? '${h.toInt()} hr' : '${minutes.toInt()} min';
  }
}

class HourlyRentalPackage {
  final String id, name, description;
  final num includedMinutes, includedKm, startingPrice;
  final List<HourlyRentalVehicle> vehicles;

  HourlyRentalPackage.fromJson(Map<String, dynamic> j)
      : id = '${j['id'] ?? j['_id'] ?? ''}',
        name = '${j['name'] ?? ''}',
        description = '${j['description'] ?? ''}',
        includedMinutes = _n(j['includedMinutes']),
        includedKm = _n(j['includedKm']),
        startingPrice = _n(j['startingPrice']),
        vehicles = ((j['vehicles'] ?? const []) as List)
            .whereType<Map>()
            .map((v) => HourlyRentalVehicle.fromJson(Map<String, dynamic>.from(v)))
            .toList();
}

/// The `rental` block on a hourly-rental ride. [settledAt] set means the bill is
/// final and the ride's fare already includes the extra km / time charges.
class RideRental {
  final String packageName;
  final num packagePrice, includedKm, includedMinutes, extraKmRate, extraMinuteRate;
  final num travelledKm, usedMinutes, extraKm, extraMinutes, extraKmCharge, extraTimeCharge;
  final DateTime? settledAt;

  bool get isSettled => settledAt != null;

  static RideRental? maybe(dynamic j) =>
      (j is Map && '${j['packagePriceId'] ?? ''}'.isNotEmpty) ? RideRental._(Map<String, dynamic>.from(j)) : null;

  RideRental._(Map<String, dynamic> j)
      : packageName = '${j['packageName'] ?? ''}',
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
}

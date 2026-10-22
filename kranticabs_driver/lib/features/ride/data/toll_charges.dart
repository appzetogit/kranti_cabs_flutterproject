import '../../../core/utils/json_safe.dart';

/// One toll plaza on an outstation route.
class TollPlaza {
  final String name;
  final String highway;
  final num oneWay;
  final num returnTrip;

  /// What this plaza costs for the whole trip, return leg included.
  final num amount;

  const TollPlaza({
    this.name = '',
    this.highway = '',
    this.oneWay = 0,
    this.returnTrip = 0,
    this.amount = 0,
  });

  factory TollPlaza.fromJson(Map<String, dynamic> json) {
    return TollPlaza(
      name: asText(json['name']),
      highway: asText(json['highway']),
      oneWay: asDouble(json['oneWay']),
      returnTrip: asDouble(json['returnTrip']),
      amount: asDouble(json['amount']),
    );
  }
}

/// Tolls on an outstation trip. Already included in the fare, and the driver
/// keeps all of it (no commission) since they pay it at the plaza.
class TollCharges {
  final num total;
  final bool roundTrip;
  final List<TollPlaza> items;

  const TollCharges({this.total = 0, this.roundTrip = false, this.items = const []});

  static const none = TollCharges();

  bool get hasTolls => total > 0;

  /// "₹180", without decimals for a whole amount.
  String get totalText {
    final s = total == total.roundToDouble() ? total.toInt().toString() : total.toStringAsFixed(2);
    return '₹$s';
  }

  String get plazaCountText => items.length == 1 ? '1 plaza' : '${items.length} plazas';

  /// Null, missing or malformed reads as no tolls.
  factory TollCharges.fromJson(dynamic json) {
    final map = asMap(json);
    if (map.isEmpty) return none;
    return TollCharges(
      total: asDouble(map['total']),
      roundTrip: asBool(map['roundTrip']),
      items: asMapList(map['items']).map(TollPlaza.fromJson).toList(growable: false),
    );
  }
}

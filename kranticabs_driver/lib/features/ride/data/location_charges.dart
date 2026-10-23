/// One location charge inside a ride's fare, from the ride payload's
/// `locationCharges`: `{ code, label, amount }`.
///
/// Codes: airport_fee, station_entry, state_tax, mcd_tax, pickup_parking,
/// drop_fee. All are already inside the fare. Everything but the airport fee
/// is money the driver hands over (station barrier, border, parking) and is
/// never commissioned.
class RideLocationCharge {
  final String code;
  final String label;
  final double amount;

  const RideLocationCharge({required this.code, required this.label, required this.amount});

  /// Paid by the driver on the rider's behalf and passed back in full.
  bool get isPassThrough => code != 'airport_fee';

  static List<RideLocationCharge> listFromJson(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((e) => RideLocationCharge(
              code: (e['code'] ?? '').toString(),
              label: (e['label'] ?? '').toString(),
              amount: double.tryParse('${e['amount'] ?? 0}') ?? 0,
            ))
        .where((e) => e.amount > 0 && e.label.isNotEmpty)
        .toList();
  }
}

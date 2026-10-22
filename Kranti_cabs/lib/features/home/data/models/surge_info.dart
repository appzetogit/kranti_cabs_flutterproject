/// Demand surge at the rider's pickup, as the server applied it to the prices.
///
/// The fares in the catalog already include [multiplier]; this is only so the
/// rider can see why a price is higher and roughly when it will ease. The
/// server sends it as `surge: { multiplier, source, ends_at }` alongside the
/// tariffs.
class SurgeInfo {
  final double multiplier;
  final DateTime? endsAt;

  const SurgeInfo({this.multiplier = 1, this.endsAt});

  static const none = SurgeInfo();

  bool get isActive => multiplier > 1.001;

  /// "1.10x" - two decimals, as the driver map and admin show it.
  String get label => '${multiplier.toStringAsFixed(2)}x';

  /// Whole minutes until the surge is due to end, or null when unknown.
  int? get minutesLeft {
    final ends = endsAt;
    if (ends == null) return null;
    final minutes = ends.difference(DateTime.now()).inSeconds / 60;
    return minutes <= 0 ? 0 : minutes.ceil();
  }

  factory SurgeInfo.fromJson(dynamic json) {
    if (json is! Map) return none;
    final multiplier = double.tryParse('${json['multiplier'] ?? 1}') ?? 1;
    final endsAt = json['ends_at'] == null ? null : DateTime.tryParse('${json['ends_at']}')?.toLocal();
    return SurgeInfo(multiplier: multiplier < 1 ? 1 : multiplier, endsAt: endsAt);
  }
}

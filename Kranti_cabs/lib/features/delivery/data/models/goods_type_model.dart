import '../../../../core/utils/json_safe.dart';

/// A parcel material the admin has listed, e.g. "Documents" or "Electronics".
///
/// The sender picks from this catalog rather than typing freely, because the
/// backend checks the chosen name against the same list to decide which
/// vehicles may carry it — a typed value would not match and the check would
/// silently pass, letting a fragile parcel onto an unsuitable vehicle.
class GoodsTypeModel {
  final String id;
  final String name;

  /// Which vehicle classes the admin allows for this material. `both` (the
  /// default) means no restriction.
  final String allowedFor;

  final String icon;

  const GoodsTypeModel({
    required this.id,
    required this.name,
    this.allowedFor = 'both',
    this.icon = '',
  });

  factory GoodsTypeModel.fromJson(Map<String, dynamic> json) {
    return GoodsTypeModel(
      id: asText(json['_id'] ?? json['id']),
      // The admin panel writes `goods_type_name`; older rows carry `name`.
      name: asText(json['goods_type_name'] ?? json['name']),
      allowedFor: asText(json['goods_types_for'] ?? json['goods_type_for'], 'both'),
      icon: asText(json['icon']),
    );
  }
}

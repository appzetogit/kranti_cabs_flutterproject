class VehicleTypeModel {
  final String id;
  final String name;
  final String shortDescription;
  final String description;
  final String transportType;

  /// 'normal' | 'bidding' | 'both', from Admin -> Vehicle Types.
  ///
  /// The server only honours a bidding booking when this is 'bidding' or
  /// 'both'; asking for one on a 'normal' vehicle silently falls back to a
  /// fixed fare. The app therefore offers the choice only where it is real.
  final String dispatchType;

  final String iconType;
  /// Which delivery card this vehicle appears under in the parcel flow
  /// ('trucks' | '2wheeler' | 'auto' | 'movers'). Empty for taxi vehicles.
  final String deliveryCategory;
  final int capacity;
  final String image;
  final String mapIcon;

  /// App modules this vehicle is offered under, as configured in the admin
  /// panel. Empty means every module — see [isOfferedUnderModule].
  final List<String> appModules;

  /// Parcel pricing from Admin -> Vehicle Types. A vehicle with none of this
  /// set cannot be quoted, which is why [hasDeliveryPricing] gates it out of
  /// the delivery flow rather than letting it quote Rs 0.
  final bool deliveryPricingEnabled;
  final double deliveryBasePrice;
  final double deliveryDistancePrice;

  const VehicleTypeModel({
    required this.id,
    required this.name,
    required this.shortDescription,
    required this.description,
    required this.transportType,
    this.dispatchType = 'normal',
    required this.iconType,
    this.deliveryCategory = '',
    required this.capacity,
    required this.image,
    required this.mapIcon,
    this.appModules = const [],
    this.deliveryPricingEnabled = false,
    this.deliveryBasePrice = 0,
    this.deliveryDistancePrice = 0,
  });

  factory VehicleTypeModel.fromJson(Map<String, dynamic> json) {
    return VehicleTypeModel(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      shortDescription: (json['short_description'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      transportType: (json['transport_type'] ?? 'taxi').toString(),
      dispatchType: (json['dispatch_type'] ?? 'normal').toString().trim().toLowerCase(),
      iconType: (json['icon_types'] ?? 'car').toString(),
      deliveryCategory: (json['delivery_category'] ?? '').toString(),
      capacity: int.tryParse('${json['capacity'] ?? 0}') ?? 0,
      image: (json['image'] ?? '').toString(),
      mapIcon: (json['map_icon'] ?? '').toString(),
      deliveryPricingEnabled: _pricing(json)['enabled'] == true,
      deliveryBasePrice: _num(_pricing(json)['base_price']),
      deliveryDistancePrice: _num(_pricing(json)['distance_price']),
      appModules: (json['app_modules'] as List?)
              ?.map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList() ??
          const [],
    );
  }

  /// Whether this vehicle should be offered for [moduleId].
  ///
  /// A vehicle with no modules assigned is offered everywhere. That default is
  /// what lets modules be assigned one vehicle at a time instead of the whole
  /// catalog vanishing the moment the feature ships.
  bool isOfferedUnderModule(String? moduleId) {
    if (moduleId == null || moduleId.isEmpty) return true;
    if (appModules.isEmpty) return true;
    return appModules.contains(moduleId);
  }

  /// Whether a rider may name their own price on this vehicle.
  bool get supportsBidding => dispatchType == 'bidding' || dispatchType == 'both';

  /// Whether this vehicle can actually be priced for a parcel.
  ///
  /// The toggle alone is not enough — a vehicle with it on and no rates quotes
  /// Rs 0, which reads to the sender as a free delivery.
  bool get hasDeliveryPricing =>
      (deliveryPricingEnabled || deliveryBasePrice > 0 || deliveryDistancePrice > 0) &&
      (deliveryBasePrice > 0 || deliveryDistancePrice > 0);
}

Map<String, dynamic> _pricing(Map<String, dynamic> json) {
  final raw = json['delivery_distance_pricing'];
  return raw is Map ? Map<String, dynamic>.from(raw) : const {};
}

double _num(dynamic v) => double.tryParse('${v ?? 0}') ?? 0;

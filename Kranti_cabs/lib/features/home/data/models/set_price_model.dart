class SetPriceModel {
  final String id;
  final String? vehicleTypeId;
  final String? zoneId;
  final String? serviceLocationId;
  final double basePrice;
  final double baseDistanceKm;
  final double pricePerDistance;
  final double timePrice;
  final double waitingCharge;
  final double serviceTaxPercent;

  /// Separate tariff for intercity trips, configured per vehicle type in
  /// Admin -> Set Prices. Only meaningful when [outstationEnabled] is on.
  final bool outstationEnabled;
  final double outstationBasePrice;
  final double outstationBaseDistanceKm;
  final double outstationPricePerDistance;
  final double outstationTimePrice;

  /// Round trip: per km (0 = use [outstationPricePerDistance]), minimum km
  /// billed per day, and driver allowance per day.
  final double outstationRoundTripPricePerDistance;
  final double outstationMinKmPerDay;
  final double outstationDriverAllowancePerDay;

  /// The per-ride platform fee - the client's admin charges (platform support,
  /// third party and GST) - charged on top of the trip. A fixed sum unless
  /// [platformFeeIsPercentage].
  final double platformFee;
  final bool platformFeeIsPercentage;

  const SetPriceModel({
    required this.id,
    required this.vehicleTypeId,
    required this.zoneId,
    required this.serviceLocationId,
    required this.basePrice,
    required this.baseDistanceKm,
    required this.pricePerDistance,
    required this.timePrice,
    required this.waitingCharge,
    required this.serviceTaxPercent,
    this.outstationEnabled = false,
    this.outstationBasePrice = 0,
    this.outstationBaseDistanceKm = 0,
    this.outstationPricePerDistance = 0,
    this.outstationTimePrice = 0,
    this.outstationRoundTripPricePerDistance = 0,
    this.outstationMinKmPerDay = 0,
    this.outstationDriverAllowancePerDay = 0,
    this.platformFee = 0,
    this.platformFeeIsPercentage = false,
  });

  /// True when this vehicle type can be booked for an intercity trip and has
  /// rates to price it with. A tariff with the toggle on but no rates would
  /// quote zero, so both are required.
  bool get supportsOutstation =>
      outstationEnabled && (outstationPricePerDistance > 0 || outstationBasePrice > 0);

  /// Reads an id that the API may send either flat (`"6a7f…"`) or populated
  /// (`{_id: "6a7f…", name: "…"}`). Returns null for anything unusable.
  static String? _idOf(dynamic value) {
    if (value == null) return null;
    if (value is Map) {
      final id = (value['_id'] ?? value['id'])?.toString();
      return (id == null || id.isEmpty) ? null : id;
    }
    final id = value.toString();
    return id.isEmpty ? null : id;
  }

  factory SetPriceModel.fromJson(Map<String, dynamic> json) {
    double asDouble(dynamic value) => double.tryParse('${value ?? 0}') ?? 0;
    return SetPriceModel(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      // `vehicle_type`, `zone_id` and `service_location_id` come back as
      // populated objects (`{_id, name}`) for the admin UI. Calling toString()
      // on those yielded "{_id: …, name: …}", which matched no vehicle id, so
      // every ride type silently fell back to the first tariff in the list.
      vehicleTypeId: _idOf(json['type_id']) ?? _idOf(json['vehicle_type']),
      zoneId: _idOf(json['zone_id']),
      serviceLocationId: _idOf(json['service_location_id']),
      basePrice: asDouble(json['base_price']),
      baseDistanceKm: asDouble(json['base_distance']),
      pricePerDistance: asDouble(json['price_per_distance']),
      timePrice: asDouble(json['time_price']),
      waitingCharge: asDouble(json['waiting_charge']),
      serviceTaxPercent: asDouble(json['service_tax']),
      // `support_outstation` is the legacy flag the backend still falls back to.
      outstationEnabled: json['enable_outstation_ride'] == true ||
          json['enable_outstation_ride'] == 1 ||
          json['support_outstation'] == 1 ||
          json['support_outstation'] == true,
      outstationBasePrice: asDouble(json['outstation_base_price']),
      outstationBaseDistanceKm: asDouble(json['outstation_base_distance']),
      outstationPricePerDistance: asDouble(json['outstation_price_per_distance']),
      outstationTimePrice: asDouble(json['outstation_time_price']),
      outstationRoundTripPricePerDistance: asDouble(json['outstation_round_trip_price_per_distance']),
      outstationMinKmPerDay: asDouble(json['outstation_min_km_per_day']),
      outstationDriverAllowancePerDay: asDouble(json['outstation_driver_allowance_per_day']),
      platformFee: asDouble(json['rider_platform_fee']),
      platformFeeIsPercentage: json['rider_platform_fee_type'] == 'percentage',
    );
  }
}

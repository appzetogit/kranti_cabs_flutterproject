/// What kind of trip the pickup and drop make, as the server decides it -
/// which in turn decides the vehicles the rider is offered:
///
///   - airport: pickup or drop inside an airport the admin drew -> Zi Airport
///   - outstation: drop outside every zone, or in another city -> Zi Outstation
///   - city: pickup and drop in the same city -> Zi City Ride
///   - unserviceable: the pickup is outside every zone
///
/// Also carries the location charges the server adds to the fare: the
/// railway station entry fee and state / MCD tax (at booking) and hub parking
/// (at trip end, so only an estimate here).
///
/// From GET /users/trip-category.
class TripCategory {
  final String category;
  final String? moduleId;
  final String? moduleName;
  final String? airportName;

  /// Flat charges the admin set on the airport, added once to the fare.
  final double airportFee;
  final String? message;

  /// Railway station entry fee, the same for every vehicle class.
  final double stationFee;

  /// "KSR Bengaluru" or "Station A & Station B".
  final String? stationNames;

  /// State / MCD tax lines per vehicle class (bike / auto / car).
  final Map<String, List<LocationChargeLine>> taxLinesByClass;

  /// The least pickup parking can cost per vehicle class, and whether it
  /// grows with the driver's wait.
  final Map<String, double> parkingFromByClass;
  final Map<String, bool> parkingVariesByClass;

  const TripCategory({
    required this.category,
    this.moduleId,
    this.moduleName,
    this.airportName,
    this.airportFee = 0,
    this.message,
    this.stationFee = 0,
    this.stationNames,
    this.taxLinesByClass = const {},
    this.parkingFromByClass = const {},
    this.parkingVariesByClass = const {},
  });

  bool get isAirport => category == 'airport';
  bool get isOutstation => category == 'outstation';
  bool get isUnserviceable => category == 'unserviceable';

  /// The charges the server adds to the fare at booking for a vehicle of
  /// [vehicleClass], apart from the airport fee: station entry and state /
  /// MCD tax. Never send these in the booking's `fare`.
  List<LocationChargeLine> bookingChargesFor(String vehicleClass) => [
        if (stationFee > 0)
          LocationChargeLine(
            label: stationNames != null ? '$stationNames entry' : 'Station entry fee',
            amount: stationFee,
          ),
        ...?taxLinesByClass[vehicleClass],
      ];

  double parkingFromFor(String vehicleClass) => parkingFromByClass[vehicleClass] ?? 0;
  bool parkingVariesFor(String vehicleClass) => parkingVariesByClass[vehicleClass] ?? false;

  factory TripCategory.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? map(dynamic value) =>
        value is Map ? Map<String, dynamic>.from(value) : null;
    double number(dynamic value) => double.tryParse('${value ?? 0}') ?? 0;
    String? text(dynamic value) {
      final s = value?.toString().trim() ?? '';
      return s.isEmpty ? null : s;
    }

    final airport = map(json['airport']);

    final station = map(json['station_fee']);
    final stationNames = ((station?['lines'] as List?) ?? const [])
        .map((line) => text(map(line)?['name']))
        .whereType<String>()
        .join(' & ');

    final taxLinesByClass = <String, List<LocationChargeLine>>{};
    (map(map(json['tax_fee'])?['by_vehicle_class']) ?? const <String, dynamic>{}).forEach((vehicleClass, value) {
      final lines = ((map(value)?['lines'] as List?) ?? const [])
          .map((line) => map(line))
          .whereType<Map<String, dynamic>>()
          .map((line) => LocationChargeLine(
                label: '${line['tax_type'] == 'mcd_tax' ? 'MCD tax' : 'State tax'}'
                    ' - ${text(line['state']) ?? text(line['name']) ?? 'state'}',
                amount: number(line['fee']),
              ))
          .where((line) => line.amount > 0)
          .toList();
      if (lines.isNotEmpty) taxLinesByClass[vehicleClass] = lines;
    });

    final parkingFromByClass = <String, double>{};
    final parkingVariesByClass = <String, bool>{};
    (map(map(json['hub_parking'])?['by_vehicle_class']) ?? const <String, dynamic>{}).forEach((vehicleClass, value) {
      final estimate = map(value);
      if (estimate == null) return;
      parkingFromByClass[vehicleClass] = number(estimate['estimated_total']);
      parkingVariesByClass[vehicleClass] = map(estimate['pickup'])?['varies_with_wait'] == true;
    });

    return TripCategory(
      category: text(json['category']) ?? 'city',
      moduleId: text(json['module_id']),
      moduleName: text(json['module_name']),
      airportName: text(airport?['name']),
      airportFee: number(airport?['total_fee']),
      message: text(json['message']),
      stationFee: number(station?['total_fee']),
      stationNames: stationNames.isEmpty ? null : stationNames,
      taxLinesByClass: taxLinesByClass,
      parkingFromByClass: parkingFromByClass,
      parkingVariesByClass: parkingVariesByClass,
    );
  }
}

/// One charge in the fare that is not the trip itself ("State tax - Rajasthan").
class LocationChargeLine {
  final String label;
  final double amount;

  const LocationChargeLine({required this.label, required this.amount});
}

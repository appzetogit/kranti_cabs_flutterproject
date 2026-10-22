/// What kind of trip the pickup and drop make, as the server decides it -
/// which in turn decides the vehicles the rider is offered:
///
///   - airport: pickup or drop inside an airport the admin drew -> Zi Airport
///   - outstation: drop outside every zone, or in another city -> Zi Outstation
///   - city: pickup and drop in the same city -> Zi City Ride
///   - unserviceable: the pickup is outside every zone
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

  const TripCategory({
    required this.category,
    this.moduleId,
    this.moduleName,
    this.airportName,
    this.airportFee = 0,
    this.message,
  });

  bool get isAirport => category == 'airport';
  bool get isOutstation => category == 'outstation';
  bool get isUnserviceable => category == 'unserviceable';

  factory TripCategory.fromJson(Map<String, dynamic> json) {
    final airport = json['airport'] is Map ? Map<String, dynamic>.from(json['airport'] as Map) : null;
    String? text(dynamic value) {
      final s = value?.toString().trim() ?? '';
      return s.isEmpty ? null : s;
    }

    return TripCategory(
      category: text(json['category']) ?? 'city',
      moduleId: text(json['module_id']),
      moduleName: text(json['module_name']),
      airportName: text(airport?['name']),
      airportFee: double.tryParse('${airport?['total_fee'] ?? 0}') ?? 0,
      message: text(json['message']),
    );
  }
}

/// One ride from GET /drivers/scheduled-rides: an open scheduled ride the
/// driver may take in advance, or one already theirs.
class ScheduledRide {
  final String rideId;
  final DateTime? scheduledAt;
  final String pickupAddress;
  final String dropAddress;
  final num fare;
  final String paymentMethod;
  final num distanceMeters;
  final num durationMinutes;
  final String serviceType;
  final bool isOutstation;
  final bool isRoundTrip;
  final DateTime? returnAt;
  final String riderName;
  final String riderPhone;

  /// Already this driver's ride (else open to take).
  final bool isMine;

  const ScheduledRide({
    required this.rideId,
    this.scheduledAt,
    this.pickupAddress = '',
    this.dropAddress = '',
    this.fare = 0,
    this.paymentMethod = 'cash',
    this.distanceMeters = 0,
    this.durationMinutes = 0,
    this.serviceType = 'ride',
    this.isOutstation = false,
    this.isRoundTrip = false,
    this.returnAt,
    this.riderName = '',
    this.riderPhone = '',
    this.isMine = false,
  });

  factory ScheduledRide.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> map(dynamic value) =>
        value is Map ? Map<String, dynamic>.from(value) : const <String, dynamic>{};
    DateTime? date(dynamic value) => value == null ? null : DateTime.tryParse(value.toString())?.toLocal();
    num number(dynamic value) => num.tryParse('${value ?? 0}') ?? 0;

    final intercity = map(json['intercity']);
    final user = map(json['user']);
    final serviceType = (json['serviceType'] ?? 'ride').toString();
    return ScheduledRide(
      rideId: (json['rideId'] ?? '').toString(),
      scheduledAt: date(json['scheduledAt']),
      pickupAddress: (json['pickupAddress'] ?? '').toString(),
      dropAddress: (json['dropAddress'] ?? '').toString(),
      fare: number(json['fare']),
      paymentMethod: (json['paymentMethod'] ?? 'cash').toString(),
      distanceMeters: number(json['estimatedDistanceMeters']),
      durationMinutes: number(json['estimatedDurationMinutes']),
      serviceType: serviceType,
      // Only `intercity` is outstation: the rider app sends an intercity block
      // (trip type one_way) with every booking, city rides included.
      isOutstation: serviceType == 'intercity',
      isRoundTrip: serviceType == 'intercity' &&
          (intercity['tripType'] ?? '').toString().toLowerCase() == 'round_trip',
      returnAt: date(intercity['returnDate']),
      riderName: (user['name'] ?? '').toString(),
      riderPhone: (user['phone'] ?? '').toString(),
      isMine: json['isAssignedToCurrentDriver'] == true,
    );
  }
}

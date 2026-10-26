import 'location_charges.dart';
import 'parcel_info.dart';
import 'ride_rental.dart';
import 'toll_charges.dart';

class RideMessage {
  final String id;
  final String senderRole;
  final String senderId;
  final String message;
  final String imageUrl;
  final DateTime sentAt;

  const RideMessage({
    required this.id,
    required this.senderRole,
    required this.senderId,
    required this.message,
    this.imageUrl = '',
    required this.sentAt,
  });

  bool get hasImage => imageUrl.isNotEmpty;

  factory RideMessage.fromJson(Map<String, dynamic> json) {
    return RideMessage(
      id: json['id']?.toString() ?? '',
      senderRole: json['senderRole']?.toString() ?? '',
      senderId: json['senderId']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      imageUrl: json['imageUrl']?.toString() ?? '',
      sentAt: DateTime.tryParse(json['sentAt']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

double? _lat(dynamic point) {
  final coords = point is Map ? point['coordinates'] : null;
  if (coords is List && coords.length >= 2) return (coords[1] as num).toDouble();
  return null;
}

double? _lng(dynamic point) {
  final coords = point is Map ? point['coordinates'] : null;
  if (coords is List && coords.length >= 2) return (coords[0] as num).toDouble();
  return null;
}

class RideStopModel {
  final double lat;
  final double lng;
  final String address;
  const RideStopModel({
    required this.lat,
    required this.lng,
    required this.address,
  });

  factory RideStopModel.fromJson(Map<String, dynamic> json) {
    double lat = 0;
    double lng = 0;
    if (json['lat'] != null) lat = double.tryParse('${json['lat']}') ?? 0;
    if (json['lng'] != null) lng = double.tryParse('${json['lng']}') ?? 0;
    if (lat == 0 && json['location'] is Map) {
      final coords = json['location']['coordinates'];
      if (coords is List && coords.length >= 2) {
        lat = (coords[1] as num).toDouble();
        lng = (coords[0] as num).toDouble();
      }
    }
    return RideStopModel(
      lat: lat,
      lng: lng,
      address: (json['address'] ?? json['name'] ?? '').toString(),
    );
  }
}

class RideModel {
  final String id;
  final String status;
  final String liveStatus;
  final double? pickupLat;
  final double? pickupLng;
  final String pickupAddress;
  final double? dropLat;
  final double? dropLng;
  final String dropAddress;
  final List<RideStopModel> stops;
  final num fare;
  final num driverEarnings;
  /// Encoded route for the current leg, resolved server-side.
  final String routePolyline;
  final String otp;
  final String paymentMethod;
  /// The rider paid the fare online in the app (Razorpay): the money is in
  /// the driver's wallet already, so nothing is to be collected.
  final bool paidOnline;
  final num estimatedDistanceMeters;
  final num estimatedDurationMinutes;
  final String riderName;
  final String riderPhone;
  final String? serviceType;
  final String? vehicleType;
  final double riderRating;
  final String? riderProfileImage;
  final DateTime? completedAt;
  final DateTime? startedAt;

  /// Pickup time for a ride booked for later; null for "now".
  final DateTime? scheduledAt;
  final List<RideMessage> messages;

  /// Parcel details for a delivery, empty for an ordinary ride. Carries the
  /// driver's own handover photos too, which decide whether the trip is allowed
  /// to start or complete.
  final ParcelInfo parcel;

  /// Outstation tolls, already inside [fare] and kept in full by the driver.
  final TollCharges tollCharges;

  /// Hourly-rental terms and (once settled) the final bill; null otherwise.
  final RideRental? rental;

  /// Airport fee, station entry fee, state / MCD tax and (once the trip ends)
  /// parking, each already inside [fare].
  final List<RideLocationCharge> locationCharges;

  const RideModel({
    required this.id,
    required this.status,
    required this.liveStatus,
    this.pickupLat,
    this.pickupLng,
    required this.pickupAddress,
    this.dropLat,
    this.dropLng,
    required this.dropAddress,
    this.stops = const [],
    required this.fare,
    required this.driverEarnings,
    this.routePolyline = '',
    required this.otp,
    required this.paymentMethod,
    this.paidOnline = false,
    required this.estimatedDistanceMeters,
    required this.estimatedDurationMinutes,
    required this.riderName,
    required this.riderPhone,
    this.serviceType,
    this.vehicleType,
    this.riderRating = 4.8,
    this.riderProfileImage,
    this.completedAt,
    this.startedAt,
    this.scheduledAt,
    this.messages = const [],
    this.parcel = ParcelInfo.none,
    this.tollCharges = TollCharges.none,
    this.rental,
    this.locationCharges = const [],
  });

  bool get isParcel => (serviceType ?? '').toLowerCase() == 'parcel';

  factory RideModel.fromJson(Map<String, dynamic> json) {
    final rider = Map<String, dynamic>.from(
      (json['user'] ?? json['userId'] ?? const {}) as Map,
    );
    return RideModel(
      id: (json['rideId'] ?? json['_id'] ?? json['id'])?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      liveStatus: json['liveStatus']?.toString() ?? '',
      pickupLat: _lat(json['pickupLocation']),
      pickupLng: _lng(json['pickupLocation']),
      pickupAddress: json['pickupAddress']?.toString() ?? '',
      dropLat: _lat(json['dropLocation']),
      dropLng: _lng(json['dropLocation']),
      dropAddress: json['dropAddress']?.toString() ?? '',
      stops: ((json['stops'] as List?) ?? [])
          .map((e) => RideStopModel.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      fare: (json['fare'] as num?) ?? 0,
      driverEarnings: (json['driverEarnings'] as num?) ?? 0,
      routePolyline: ((json['route'] is Map
              ? ((json['route'] as Map)['polyline'] ?? (json['route'] as Map)['encodedPolyline'])
              : null) ??
          json['polyline'] ??
          json['encodedPolyline'] ??
          json['routePolyline'] ??
          (json['route'] is String ? json['route'] : '') ??
          '').toString(),
      otp: json['otp']?.toString() ?? '',
      paymentMethod: json['paymentMethod']?.toString() ?? '',
      paidOnline: _isPaidOnline(json),
      estimatedDistanceMeters: (json['estimatedDistanceMeters'] as num?) ?? 0,
      estimatedDurationMinutes: (json['estimatedDurationMinutes'] as num?) ?? 0,
      riderName: rider['name']?.toString() ?? 'Rider',
      riderPhone: rider['phone']?.toString() ?? '',
      serviceType: json['serviceType']?.toString(),
      vehicleType: (json['vehicleType'] ?? json['serviceType'])?.toString(),
      riderRating: (rider['rating'] is num) ? (rider['rating'] as num).toDouble() : 4.8,
      riderProfileImage: (rider['profileImage'] ?? rider['image'] ?? rider['avatar'])?.toString(),
      completedAt: json['completedAt'] != null ? DateTime.tryParse(json['completedAt'].toString()) : null,
      startedAt: json['startedAt'] != null ? DateTime.tryParse(json['startedAt'].toString()) : null,
      scheduledAt: json['scheduledAt'] != null ? DateTime.tryParse(json['scheduledAt'].toString()) : null,
      messages: (json['messages'] as List? ?? const [])
          .map((m) => RideMessage.fromJson(Map<String, dynamic>.from(m as Map)))
          .toList(),
      parcel: ParcelInfo.fromJson(json['parcel']),
      tollCharges: TollCharges.fromJson(json['tollCharges']),
      rental: RideRental.maybe(json['rental']),
      locationCharges: RideLocationCharge.listFromJson(json['locationCharges']),
    );
  }

  static bool _isPaidOnline(Map<String, dynamic> json) {
    if ('${json['collectedVia'] ?? ''}'.toLowerCase() == 'online') return true;
    final collection = json['driverPaymentCollection'];
    if (collection is! Map) return false;
    return '${collection['source'] ?? ''}' == 'rider_fare_online' &&
        '${collection['status'] ?? ''}'.toLowerCase() == 'paid';
  }

  RideModel copyWith({
    String? status,
    String? liveStatus,
    List<RideMessage>? messages,
    DateTime? completedAt,
    ParcelInfo? parcel,
  }) {
    return RideModel(
      id: id,
      status: status ?? this.status,
      liveStatus: liveStatus ?? this.liveStatus,
      pickupLat: pickupLat,
      pickupLng: pickupLng,
      pickupAddress: pickupAddress,
      dropLat: dropLat,
      dropLng: dropLng,
      dropAddress: dropAddress,
      // Was dropped here, which silently emptied the stop list on every status
      // change of a multi-stop trip.
      stops: stops,
      fare: fare,
      driverEarnings: driverEarnings,
      routePolyline: routePolyline,
      otp: otp,
      paymentMethod: paymentMethod,
      paidOnline: paidOnline,
      estimatedDistanceMeters: estimatedDistanceMeters,
      estimatedDurationMinutes: estimatedDurationMinutes,
      riderName: riderName,
      riderPhone: riderPhone,
      serviceType: serviceType,
      vehicleType: vehicleType,
      riderRating: riderRating,
      riderProfileImage: riderProfileImage,
      completedAt: completedAt ?? this.completedAt,
      startedAt: startedAt,
      scheduledAt: scheduledAt,
      messages: messages ?? this.messages,
      parcel: parcel ?? this.parcel,
      tollCharges: tollCharges,
      rental: rental,
      locationCharges: locationCharges,
    );
  }
}

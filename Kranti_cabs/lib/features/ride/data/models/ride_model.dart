import '../../../delivery/data/models/parcel_model.dart';
import 'ride_bid_model.dart';
import 'ride_message_model.dart';

class LatLngPoint {
  final double lat;
  final double lng;
  const LatLngPoint({required this.lat, required this.lng});

  factory LatLngPoint.fromGeoJson(dynamic geo) {
    if (geo is Map &&
        geo['coordinates'] is List &&
        geo['coordinates'].length == 2) {
      final coords = geo['coordinates'] as List;
      return LatLngPoint(
        lat: double.tryParse('${coords[1]}') ?? 0,
        lng: double.tryParse('${coords[0]}') ?? 0,
      );
    }
    return const LatLngPoint(lat: 0, lng: 0);
  }
}

class RideDriverInfo {
  final String id;
  final String name;
  final String phone;
  final String profileImage;
  final String vehicleNumber;
  final String vehicleModel;
  final String vehicleMake;
  final double rating;

  const RideDriverInfo({
    required this.id,
    required this.name,
    required this.phone,
    required this.profileImage,
    required this.vehicleNumber,
    required this.vehicleModel,
    required this.vehicleMake,
    required this.rating,
  });

  factory RideDriverInfo.fromJson(Map<String, dynamic> json) {
    final nameStr =
        (json['name'] ??
                json['fullName'] ??
                json['driverName'] ??
                json['first_name'] ??
                '')
            .toString();
    final phoneStr =
        (json['phone'] ?? json['phoneNumber'] ?? json['mobile'] ?? '')
            .toString();
    final imgStr =
        (json['profileImage'] ??
                json['profilePicture'] ??
                json['avatar'] ??
                json['image'] ??
                '')
            .toString();
    final vehNo =
        (json['vehicleNumber'] ??
                json['vehicleNo'] ??
                json['plateNumber'] ??
                json['vehicle_number'] ??
                '')
            .toString();
    final vehMod =
        (json['vehicleModel'] ?? json['model'] ?? json['vehicle_model'] ?? '')
            .toString();
    final vehMake =
        (json['vehicleMake'] ??
                json['make'] ??
                json['vehicleType'] ??
                json['vehicle_make'] ??
                '')
            .toString();
    final ratingVal =
        double.tryParse(
          '${json['rating'] ?? json['averageRating'] ?? json['avgRating'] ?? 0}',
        ) ??
        0;

    return RideDriverInfo(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      name: nameStr,
      phone: phoneStr,
      profileImage: imgStr,
      vehicleNumber: vehNo,
      vehicleModel: vehMod,
      vehicleMake: vehMake,
      rating: ratingVal,
    );
  }
}

/// The assigned driver's own payment handle, surfaced by the server only once
/// admin has verified it. Used at ride-end to render a scannable QR and build a
/// `upi://pay` deep link so the rider can pay the driver directly.
class RideDriverPayment {
  final String upiId;
  final String qrCodeImage;
  final String payeeName;

  const RideDriverPayment({
    required this.upiId,
    required this.qrCodeImage,
    required this.payeeName,
  });

  bool get hasUpi => upiId.isNotEmpty;

  factory RideDriverPayment.fromJson(Map<String, dynamic> json) {
    return RideDriverPayment(
      upiId: (json['upiId'] ?? '').toString(),
      qrCodeImage: (json['qrCodeImage'] ?? '').toString(),
      payeeName: (json['payeeName'] ?? '').toString(),
    );
  }
}

class RideStopPoint {
  final LatLngPoint location;
  final String address;
  const RideStopPoint({required this.location, required this.address});

  factory RideStopPoint.fromJson(Map<String, dynamic> json) {
    double lat = 0;
    double lng = 0;
    if (json['lat'] != null) lat = double.tryParse('${json['lat']}') ?? 0;
    if (json['lng'] != null) lng = double.tryParse('${json['lng']}') ?? 0;
    if (lat == 0 && json['location'] != null) {
      final p = LatLngPoint.fromGeoJson(json['location']);
      lat = p.lat;
      lng = p.lng;
    }
    return RideStopPoint(
      location: LatLngPoint(lat: lat, lng: lng),
      address: (json['address'] ?? json['name'] ?? '').toString(),
    );
  }
}

class RideModel {
  final String rideId;
  final String status;
  final String liveStatus;
  final double fare;
  final double baseFare;
  final double estimatedDistanceMeters;
  final double estimatedDurationMinutes;
  final String? paymentMethod;

  /// How the driver recorded collecting the fare at ride-end ('cash' | 'upi').
  final String collectedVia;

  /// The driver's verified UPI/QR, present only when the server exposes it
  /// (admin-verified). Null otherwise.
  final RideDriverPayment? driverPayment;

  /// The fare was settled through the driver's payment collection
  /// (`driverPaymentCollection` paid), whoever started it. Read the same way
  /// the server decides it: a `paidAt` stamp or a paid-like status.
  final bool farePaid;

  /// Encoded route for the current leg, resolved server-side.
  final String routePolyline;
  final String otp;
  final LatLngPoint pickup;
  final String pickupAddress;
  final LatLngPoint drop;
  final String dropAddress;
  final List<RideStopPoint> stops;
  final DateTime? scheduledAt;
  final DateTime? acceptedAt;
  final DateTime? arrivedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final RideDriverInfo? driver;
  final LatLngPoint? lastDriverLocation;
  final double? lastDriverHeading;

  /// GPS accuracy (meters) of [lastDriverLocation], when the driver app sent
  /// one. Used to keep a noisy fix from tripping off-route detection — see
  /// LiveTrackingMap. Null for an older driver build, or when the socket
  /// event predates this being sent at all.
  final double? lastDriverAccuracy;
  final List<RideMessageModel> messages;
  final String? serviceType;
  final String? vehicleType;

  /// The catalog's icon family for the assigned driver's vehicle. This is what
  /// the backend actually sends; `vehicleType` is absent from every ride
  /// payload, so relying on it alone always fell through to the car default.
  final String? vehicleIconType;

  /// The catalog id of the booked vehicle, used to pick that vehicle's own map
  /// art instead of the generic family silhouette.
  final String vehicleTypeId;

  /// The parcel declaration for a delivery, empty for an ordinary ride. Carries
  /// the captain's handover photos, which is how the sender sees proof their
  /// parcel was collected and delivered.
  final ParcelModel parcel;

  /// Negotiation rules for this ride, as the server resolved them at booking.
  /// [RideBiddingInfo.none] for an ordinary fixed-fare trip.
  final RideBiddingInfo bidding;

  const RideModel({
    required this.rideId,
    required this.status,
    required this.liveStatus,
    required this.fare,
    required this.baseFare,
    required this.estimatedDistanceMeters,
    required this.estimatedDurationMinutes,
    required this.paymentMethod,
    this.collectedVia = 'cash',
    this.driverPayment,
    this.farePaid = false,
    this.routePolyline = '',
    required this.otp,
    required this.pickup,
    required this.pickupAddress,
    required this.drop,
    required this.dropAddress,
    this.stops = const [],
    this.scheduledAt,
    this.acceptedAt,
    this.arrivedAt,
    this.startedAt,
    this.completedAt,
    this.driver,
    this.lastDriverLocation,
    this.lastDriverHeading,
    this.lastDriverAccuracy,
    this.messages = const [],
    this.serviceType,
    this.vehicleType,
    this.vehicleIconType,
    this.vehicleTypeId = '',
    this.parcel = const ParcelModel(),
    this.bidding = RideBiddingInfo.none,
  });

  bool get isParcel => (serviceType ?? '').toLowerCase() == 'parcel';

  factory RideModel.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) =>
        v == null ? null : DateTime.tryParse(v.toString());

    return RideModel(
      rideId: (json['rideId'] ?? json['_id'] ?? json['id'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      liveStatus: (json['liveStatus'] ?? '').toString(),
      fare: double.tryParse('${json['fare'] ?? 0}') ?? 0,
      baseFare:
          double.tryParse('${json['baseFare'] ?? json['fare'] ?? 0}') ?? 0,
      estimatedDistanceMeters:
          double.tryParse('${json['estimatedDistanceMeters'] ?? 0}') ?? 0,
      estimatedDurationMinutes:
          double.tryParse('${json['estimatedDurationMinutes'] ?? 0}') ?? 0,
      paymentMethod: json['paymentMethod']?.toString() ?? 'cash',
      collectedVia: (json['collectedVia'] ?? 'cash').toString(),
      driverPayment:
          (json['driverPayment'] is Map && (json['driverPayment'] as Map).isNotEmpty)
          ? RideDriverPayment.fromJson(
              Map<String, dynamic>.from(json['driverPayment'] as Map),
            )
          : null,
      farePaid: _parseFarePaid(json['driverPaymentCollection']),
      routePolyline:
          ((json['route'] is Map
                      ? ((json['route'] as Map)['polyline'] ??
                            (json['route'] as Map)['encodedPolyline'])
                      : null) ??
                  json['polyline'] ??
                  json['encodedPolyline'] ??
                  json['routePolyline'] ??
                  (json['route'] is String ? json['route'] : '') ??
                  '')
              .toString(),
      otp: (json['otp'] ?? '').toString(),
      pickup: LatLngPoint.fromGeoJson(json['pickupLocation']),
      pickupAddress: (json['pickupAddress'] ?? '').toString(),
      drop: LatLngPoint.fromGeoJson(json['dropLocation']),
      dropAddress: (json['dropAddress'] ?? '').toString(),
      stops: ((json['stops'] as List?) ?? [])
          .map((e) => RideStopPoint.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      scheduledAt: parseDate(json['scheduledAt']),
      acceptedAt: parseDate(json['acceptedAt']),
      arrivedAt: parseDate(json['arrivedAt']),
      startedAt: parseDate(json['startedAt']),
      completedAt: parseDate(json['completedAt']),
      driver: (json['driver'] is Map && (json['driver'] as Map).isNotEmpty)
          ? RideDriverInfo.fromJson(Map<String, dynamic>.from(json['driver']))
          : ((json['driverId'] is Map && (json['driverId'] as Map).isNotEmpty)
                ? RideDriverInfo.fromJson(
                    Map<String, dynamic>.from(json['driverId']),
                  )
                : null),
      // `!= null` alone isn't enough: the server writes this sub-document as
      // soon as a ride is accepted, before the driver's first location ping
      // has ever arrived — `{type: 'Point', heading: null, speed: null,
      // updatedAt: null}`, with no `coordinates` at all. `fromGeoJson`
      // defaults a missing/invalid `coordinates` to (0, 0) — "null island",
      // off the coast of west Africa — which used to get treated as a real
      // fix and drawn as the driver's position and the route's other end
      // until an actual update corrected it.
      lastDriverLocation:
          (json['lastDriverLocation'] is Map &&
              (json['lastDriverLocation'] as Map)['coordinates'] is List &&
              ((json['lastDriverLocation'] as Map)['coordinates'] as List)
                      .length ==
                  2)
          ? LatLngPoint.fromGeoJson(json['lastDriverLocation'])
          : null,
      lastDriverHeading: json['lastDriverLocation'] is Map
          ? double.tryParse('${json['lastDriverLocation']['heading'] ?? ''}')
          : null,
      // Not currently persisted server-side (the live socket event is the
      // only source of this today), parsed here only so a REST snapshot
      // would pick it up automatically if that ever changes.
      lastDriverAccuracy: json['lastDriverLocation'] is Map
          ? double.tryParse('${json['lastDriverLocation']['accuracy'] ?? ''}')
          : null,
      messages: ((json['messages'] as List?) ?? [])
          .map((e) => RideMessageModel.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      serviceType: json['serviceType']?.toString(),
      vehicleTypeId: (json['vehicleTypeId'] ?? '').toString(),
      parcel: ParcelModel.fromJson(
        json['parcel'] is Map
            ? Map<String, dynamic>.from(json['parcel'] as Map)
            : const {},
      ),
      // Read off the ride itself: the bidding fields are top-level, not nested.
      bidding: RideBiddingInfo.fromJson(json),
      vehicleType: json['vehicleType']?.toString(),
      vehicleIconType: json['vehicleIconType']?.toString(),
    );
  }

  RideModel copyWith({
    String? status,
    String? liveStatus,
    RideDriverInfo? driver,
    LatLngPoint? lastDriverLocation,
    double? lastDriverHeading,
    double? lastDriverAccuracy,
    List<RideMessageModel>? messages,
    DateTime? acceptedAt,
    DateTime? arrivedAt,
    DateTime? startedAt,
    DateTime? completedAt,
  }) {
    return RideModel(
      rideId: rideId,
      status: status ?? this.status,
      liveStatus: liveStatus ?? this.liveStatus,
      fare: fare,
      baseFare: baseFare,
      estimatedDistanceMeters: estimatedDistanceMeters,
      estimatedDurationMinutes: estimatedDurationMinutes,
      paymentMethod: paymentMethod,
      collectedVia: collectedVia,
      driverPayment: driverPayment,
      farePaid: farePaid,
      routePolyline: routePolyline,
      otp: otp,
      pickup: pickup,
      pickupAddress: pickupAddress,
      drop: drop,
      dropAddress: dropAddress,
      stops: stops,
      scheduledAt: scheduledAt,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      arrivedAt: arrivedAt ?? this.arrivedAt,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      driver: driver ?? this.driver,
      lastDriverLocation: lastDriverLocation ?? this.lastDriverLocation,
      lastDriverHeading: lastDriverHeading ?? this.lastDriverHeading,
      lastDriverAccuracy: lastDriverAccuracy ?? this.lastDriverAccuracy,
      messages: messages ?? this.messages,
      // Previously omitted, so every copyWith silently reset these to null —
      // which reset the map's vehicle marker back to the default on the first
      // status or location update.
      serviceType: serviceType,
      vehicleType: vehicleType,
      vehicleIconType: vehicleIconType,
      vehicleTypeId: vehicleTypeId,
      parcel: parcel,
      bidding: bidding,
    );
  }

  static bool _parseFarePaid(dynamic collection) {
    if (collection is! Map) return false;
    if (collection['paidAt'] != null) return true;
    final status = (collection['status'] ?? '').toString().trim().toLowerCase();
    return status == 'paid' || status == 'captured' || status == 'completed';
  }

  /// Nothing left for the rider to pay: settled through the driver's
  /// collection, or paid online up front.
  bool get isFarePaid => farePaid || isPaidOnline;

  /// True once the trip is finished, by either status axis.
  ///
  /// The server carries two: `status` (searching/accepted/ongoing/completed)
  /// and `liveStatus` (which adds arriving/arrived/started). Reading only one
  /// means a payload that advances the other is missed.
  bool get isCompleted =>
      status.toLowerCase() == 'completed' ||
      liveStatus.toLowerCase() == 'completed';

  bool get isCancelled =>
      status.toLowerCase() == 'cancelled' ||
      liveStatus.toLowerCase() == 'cancelled';

  /// A cash ride the rider can still pay online in the app.
  bool get isCashRide => (paymentMethod ?? 'cash').toLowerCase() == 'cash';

  /// The rider already paid the fare online (Razorpay): nothing to hand over.
  bool get isPaidOnline => collectedVia.toLowerCase() == 'online';

  /// True once the rider is in the car.
  ///
  /// Decides which leg everything else is about: before this the journey that
  /// matters is the driver's, coming to the pickup; after it, the rider's, on
  /// the way to the drop.
  bool get isUnderway {
    final combined = '$status $liveStatus'.toLowerCase();
    return combined.contains('started') ||
        combined.contains('ongoing') ||
        combined.contains('in_progress');
  }
}

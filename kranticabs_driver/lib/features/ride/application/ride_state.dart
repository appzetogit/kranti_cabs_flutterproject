import '../data/parcel_info.dart';
import '../data/ride_model.dart';
import '../data/ride_rental.dart';
import '../data/toll_charges.dart';

class RideRequest {
  final String rideId;
  final String pickupAddress;
  final String dropAddress;
  final List<RideStopModel> stops;
  final num fare;
  final String riderName;
  final String riderPhone;
  final String riderImage;
  final String paymentMethod;
  final String serviceType;

  /// Set for an hourly rental: no fixed drop, billed by package + overage.
  final RideRental? rental;

  /// The real, admin-configured vehicle-type name for this offer (e.g. "Kranti
  /// Mini Truck", "Kranti Scooty Parcel", "Sedan") — distinct from [serviceType],
  /// which only says ride vs. parcel, not which vehicle class within it.
  final String vehicleLabel;

  /// True for an intercity trip, and whether the rider is coming back. Shown on
  /// the offer so the driver knows what they are committing to.
  final bool isOutstation;
  final bool isRoundTrip;

  /// The rider's chosen return date/time for a round-trip outstation ride, as a
  /// display string (e.g. "15 Oct, 6:00 PM"). Empty for one-way trips or when
  /// the rider did not pick one.
  final String returnDateLabel;

  /// What the sender said they are shipping, typed on the rider app.
  /// Empty for ordinary rides.
  final String goodsType;

  /// The full parcel declaration - material, weight, photos, handling notes and
  /// both contacts. Shown on the offer so the driver can judge whether their
  /// vehicle suits the load before accepting.
  final ParcelInfo parcel;

  /// Outstation tolls, already inside [fare] and kept in full by the driver.
  final TollCharges tollCharges;

  /// True when the rider opened this trip for bidding rather than a fixed fare.
  ///
  /// Changes what the driver can do with the offer entirely: plain Accept is
  /// refused server-side on a bidding ride ("Bidding rides must be won through
  /// bid acceptance"), so the card offers a price instead.
  final bool biddingEnabled;

  /// Lowest the driver may bid.
  final num bidFloorFare;

  /// Highest the rider will pay. Bids above this are rejected.
  final num bidCeilingFare;

  /// The increment bids must move in. A bid off-step is rejected.
  final num bidStepAmount;
  final String waveText;
  final num estimatedDistanceMeters;
  final num estimatedDurationMinutes;
  final int expiresInSeconds;

  /// How far the driver currently is from the pickup point, as computed by
  /// the backend at dispatch time from the driver's last known location —
  /// not recomputed on-device, since a driver's app may not have a fresh GPS
  /// fix the instant an offer arrives. Null on an older server build that
  /// doesn't send it yet.
  final num? pickupDistanceMeters;

  /// Pickup time for a ride booked for later; null for "now".
  final DateTime? scheduledAt;

  /// Booked for later and that time is still ahead.
  bool get isScheduled => scheduledAt != null && scheduledAt!.isAfter(DateTime.now());

  /// "29 Oct, 2:00 PM", or empty when not scheduled.
  String get scheduledLabel => _formatReturnDate(scheduledAt?.toIso8601String());

  const RideRequest({
    required this.rideId,
    required this.pickupAddress,
    required this.dropAddress,
    this.stops = const [],
    required this.fare,
    required this.riderName,
    this.riderPhone = '',
    this.riderImage = '',
    this.paymentMethod = 'CASH',
    this.serviceType = 'Passenger ride',
    this.rental,
    this.vehicleLabel = '',
    this.isOutstation = false,
    this.isRoundTrip = false,
    this.returnDateLabel = '',
    this.goodsType = '',
    this.parcel = ParcelInfo.none,
    this.tollCharges = TollCharges.none,
    this.biddingEnabled = false,
    this.bidFloorFare = 0,
    this.bidCeilingFare = 0,
    this.bidStepAmount = 10,
    this.waveText = 'WAVE 1 OF 10 • RADIUS 3.0 KM',
    required this.estimatedDistanceMeters,
    required this.estimatedDurationMinutes,
    required this.expiresInSeconds,
    this.pickupDistanceMeters,
    this.scheduledAt,
  });

  factory RideRequest.fromJson(Map<String, dynamic> json) {
    final rawUser = json['user'] ?? json['rider'] ?? json['userId'];
    final user = rawUser is Map
        ? Map<String, dynamic>.from(rawUser)
        : <String, dynamic>{};
    final isParcel =
        json['serviceType'] == 'parcel' || json['isParcel'] == true;
    // Outstation trips are filed as `intercity`, with the one-way/round-trip
    // choice on the intercity block. A driver needs to know before accepting:
    // a round trip means they are committed for the return leg too.
    final isIntercity = json['serviceType'] == 'intercity';
    final intercity = json['intercity'] is Map
        ? Map<String, dynamic>.from(json['intercity'] as Map)
        : const <String, dynamic>{};
    final isRoundTrip =
        (intercity['tripType'] ?? '').toString().toLowerCase() == 'round_trip';
    final returnDateLabel = _formatReturnDate(intercity['returnDate']?.toString());
    final parcel = json['parcel'] is Map
        ? Map<String, dynamic>.from(json['parcel'] as Map)
        : const <String, dynamic>{};
    // `description` is the rider's free-text entry; `category` is the admin
    // goods-type catalog value, used as a fallback when no text was typed.
    final goodsType = (parcel['description'] ?? parcel['category'] ?? '')
        .toString()
        .trim();
    final bidding = json['bidding'] is Map
        ? Map<String, dynamic>.from(json['bidding'] as Map)
        : const <String, dynamic>{};
    final waveStr =
        json['waveText']?.toString() ??
        (json['wave'] != null
            ? 'WAVE ${json['wave']} OF 10 • RADIUS 3.0 KM'
            : 'WAVE 1 OF 10 • RADIUS 3.0 KM');

    return RideRequest(
      rideId: json['rideId']?.toString() ?? json['_id']?.toString() ?? '',
      pickupAddress:
          json['pickupAddress']?.toString() ??
          json['pickup']?['address']?.toString() ??
          '',
      dropAddress:
          json['dropAddress']?.toString() ??
          json['dropoff']?['address']?.toString() ??
          json['destination']?['address']?.toString() ??
          '',
      stops: ((json['stops'] as List?) ?? [])
          .map((e) => RideStopModel.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      fare: (json['fare'] as num?) ?? (json['estimatedFare'] as num?) ?? 0,
      riderName:
          user['name']?.toString() ?? user['fullName']?.toString() ?? 'Rider',
      riderPhone:
          user['phone']?.toString() ?? user['phoneNumber']?.toString() ?? '',
      riderImage:
          (json['riderImage'] ??
                  user['profileImage'] ??
                  user['image'] ??
                  user['avatar'] ??
                  '')
              .toString(),
      paymentMethod: (json['paymentMethod']?.toString() ?? 'CASH')
          .toUpperCase(),
      vehicleLabel: json['vehicleLabel']?.toString() ?? '',
      rental: RideRental.maybe(json['rental']),
      serviceType: isParcel
          ? 'Parcel delivery'
          : isIntercity
          ? (isRoundTrip
              ? (returnDateLabel.isNotEmpty
                  ? 'Outstation · Round trip · Return $returnDateLabel'
                  : 'Outstation · Round trip')
              : 'Outstation · One way')
          : (json['serviceType']?.toString() ?? 'Passenger ride'),
      isOutstation: isIntercity,
      isRoundTrip: isRoundTrip,
      returnDateLabel: returnDateLabel,
      goodsType: goodsType,
      parcel: ParcelInfo.fromJson(json['parcel']),
      tollCharges: TollCharges.fromJson(json['tollCharges']),
      // The dispatch offer nests the bid band under `bidding`; older/replay
      // shapes kept it at the top level, so read the nested values first and
      // fall back to the top level rather than assuming one shape.
      biddingEnabled:
          bidding['enabled'] == true ||
          (json['pricingNegotiationMode']?.toString() ?? '') == 'driver_bid',
      bidFloorFare:
          (bidding['bidFloorFare'] as num?) ??
          (json['bidFloorFare'] as num?) ??
          (bidding['baseFare'] as num?) ??
          (json['baseFare'] as num?) ??
          0,
      bidCeilingFare:
          (bidding['userMaxBidFare'] as num?) ??
          (bidding['bidCeilingMaxFare'] as num?) ??
          (json['userMaxBidFare'] as num?) ??
          (json['bidCeilingMaxFare'] as num?) ??
          0,
      bidStepAmount:
          (bidding['bidStepAmount'] as num?) ?? (json['bidStepAmount'] as num?) ?? 10,
      waveText: waveStr,
      estimatedDistanceMeters:
          (json['estimatedDistanceMeters'] as num?) ??
          (json['distance'] as num?) ??
          0,
      estimatedDurationMinutes:
          (json['estimatedDurationMinutes'] as num?) ??
          (json['duration'] as num?) ??
          0,
      expiresInSeconds:
          (json['expiresInSeconds'] as num?)?.toInt() ??
          (json['acceptRejectDurationSeconds'] as num?)?.toInt() ??
          25,
      pickupDistanceMeters: json['pickupDistanceMeters'] as num?,
      scheduledAt: json['scheduledAt'] == null ? null : DateTime.tryParse(json['scheduledAt'].toString()),
    );
  }
}

extension RideRequestBidBand on RideRequest {
  /// A copy with a fresh negotiation band.
  ///
  /// Deliberately narrow rather than a full `copyWith`: the rider can only move
  /// the band while an offer is live, and rebuilding every other field from a
  /// partial socket payload is how offers lose their addresses.
  RideRequest copyWithBidBand({num? floor, num? ceiling, num? step}) {
    return RideRequest(
      rideId: rideId,
      pickupAddress: pickupAddress,
      dropAddress: dropAddress,
      stops: stops,
      fare: fare,
      riderName: riderName,
      riderPhone: riderPhone,
      riderImage: riderImage,
      paymentMethod: paymentMethod,
      vehicleLabel: vehicleLabel,
      serviceType: serviceType,
      rental: rental,
      isOutstation: isOutstation,
      isRoundTrip: isRoundTrip,
      returnDateLabel: returnDateLabel,
      goodsType: goodsType,
      parcel: parcel,
      tollCharges: tollCharges,
      biddingEnabled: biddingEnabled,
      bidFloorFare: floor ?? bidFloorFare,
      bidCeilingFare: ceiling ?? bidCeilingFare,
      bidStepAmount: step ?? bidStepAmount,
      waveText: waveText,
      estimatedDistanceMeters: estimatedDistanceMeters,
      estimatedDurationMinutes: estimatedDurationMinutes,
      expiresInSeconds: expiresInSeconds,
      pickupDistanceMeters: pickupDistanceMeters,
      scheduledAt: scheduledAt,
    );
  }
}

/// Turns the rider's ISO return date/time into a short display label, e.g.
/// "15 Oct, 6:00 PM". Returns an empty string for null/blank/unparseable input.
String _formatReturnDate(String? iso) {
  final raw = (iso ?? '').trim();
  if (raw.isEmpty) return '';
  final dt = DateTime.tryParse(raw);
  if (dt == null) return '';
  final local = dt.toLocal();
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour < 12 ? 'AM' : 'PM';
  return '${local.day} ${months[local.month - 1]}, $hour12:$minute $period';
}

class RideFlowState {
  final RideRequest? incomingRequest;
  final RideModel? activeRide;
  final bool busy;

  /// Set when the driver tapped Accept but lost the race (or the ride was
  /// withdrawn). The request screen reads this to show a reason and pop.
  final String? acceptError;

  /// The fare the driver bid on the current offer, once the server confirmed
  /// it. Drives the "waiting for the rider" state on the offer card.
  final num? submittedBidFare;

  const RideFlowState({
    this.incomingRequest,
    this.activeRide,
    this.busy = false,
    this.acceptError,
    this.submittedBidFare,
  });

  RideFlowState copyWith({
    RideRequest? incomingRequest,
    bool clearIncomingRequest = false,
    RideModel? activeRide,
    bool clearActiveRide = false,
    bool? busy,
    String? acceptError,
    bool clearAcceptError = false,
    num? submittedBidFare,
    bool clearSubmittedBid = false,
  }) {
    return RideFlowState(
      incomingRequest: clearIncomingRequest
          ? null
          : (incomingRequest ?? this.incomingRequest),
      activeRide: clearActiveRide ? null : (activeRide ?? this.activeRide),
      busy: busy ?? this.busy,
      acceptError: clearAcceptError ? null : (acceptError ?? this.acceptError),
      submittedBidFare: clearSubmittedBid
          ? null
          : (submittedBidFare ?? this.submittedBidFare),
    );
  }
}

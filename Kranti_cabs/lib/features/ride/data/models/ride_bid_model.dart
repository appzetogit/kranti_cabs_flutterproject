import '../../../../core/utils/json_safe.dart';

/// One driver's offer to run a bidding ride at their own price.
///
/// Only outstation rides produce these: the backend routes city rides to
/// `user_increment_only`, where the rider raises their own fare instead and no
/// bids exist at all.
class RideBidModel {
  final String id;
  final String rideId;
  final String driverId;

  /// What the driver is asking for the trip.
  final double bidFare;

  /// How far that sits from the rider's base fare. Negative when the driver has
  /// undercut it, which is the case worth surfacing.
  final double incrementAmount;

  /// 'pending' | 'accepted' | 'rejected' | 'expired' | 'cancelled'.
  final String status;

  final String driverName;
  final String driverPhone;
  final String driverImage;
  final String vehicleNumber;
  final String vehicleMake;
  final String vehicleModel;
  final String vehicleColor;
  final double driverRating;

  final DateTime? createdAt;

  const RideBidModel({
    required this.id,
    required this.rideId,
    required this.driverId,
    required this.bidFare,
    this.incrementAmount = 0,
    this.status = 'pending',
    this.driverName = '',
    this.driverPhone = '',
    this.driverImage = '',
    this.vehicleNumber = '',
    this.vehicleMake = '',
    this.vehicleModel = '',
    this.vehicleColor = '',
    this.driverRating = 0,
    this.createdAt,
  });

  bool get isPending => status == 'pending';

  /// True when the driver is asking less than the rider's own estimate.
  bool get isBelowBase => incrementAmount < 0;

  /// 'Swift Dzire · White', or whichever parts came back.
  String get vehicleLabel {
    final parts = [vehicleMake, vehicleModel]
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .join(' ');
    if (parts.isEmpty) return vehicleColor.trim();
    if (vehicleColor.trim().isEmpty) return parts;
    return '$parts · ${vehicleColor.trim()}';
  }

  factory RideBidModel.fromJson(dynamic json) {
    final map = asMap(json);
    final driver = asMap(map['driver']);

    return RideBidModel(
      id: asText(map['id'] ?? map['_id']),
      rideId: asText(map['rideId']),
      driverId: asText(map['driverId']),
      bidFare: asDouble(map['bidFare']),
      incrementAmount: asDouble(map['incrementAmount']),
      status: asText(map['status'], 'pending').toLowerCase(),
      driverName: asText(driver['name']),
      driverPhone: asText(driver['phone']),
      driverImage: asText(driver['profileImage']),
      vehicleNumber: asText(driver['vehicleNumber']),
      vehicleMake: asText(driver['vehicleMake']),
      vehicleModel: asText(driver['vehicleModel']),
      vehicleColor: asText(driver['vehicleColor']),
      driverRating: asDouble(driver['rating']),
      createdAt: DateTime.tryParse(asText(map['createdAt']))?.toLocal(),
    );
  }
}

/// The negotiation rules attached to a ride, as the server resolved them.
///
/// The rider app never computes these: the floor, ceiling and step come from
/// admin settings applied at booking time, and re-deriving them locally would
/// let the two drift and produce bids the server then rejects.
class RideBiddingInfo {
  /// 'normal' | 'bidding'.
  final String bookingMode;

  /// 'none' | 'driver_bid' | 'user_increment_only'.
  final String negotiationMode;

  /// 'none' | 'open' | 'accepted' | 'expired' | 'cancelled'.
  final String biddingStatus;

  /// The fare the ride was quoted at, before any negotiation.
  final double baseFare;

  /// Lowest fare a driver may bid.
  final double bidFloorFare;

  /// The rider's current maximum. Drivers cannot bid above it, and the rider
  /// can raise it in [bidStepAmount] steps to attract more.
  final double userMaxBidFare;

  /// The hard ceiling admin settings allow, past which the rider cannot raise.
  final double bidCeilingMaxFare;

  final double bidStepAmount;

  /// How long the rider must wait between self-increases, in
  /// `user_increment_only` mode.
  final int fareIncreaseWaitMinutes;

  /// When the next self-increase becomes allowed. Null means now.
  final DateTime? nextFareIncreaseAt;

  const RideBiddingInfo({
    this.bookingMode = 'normal',
    this.negotiationMode = 'none',
    this.biddingStatus = 'none',
    this.baseFare = 0,
    this.bidFloorFare = 0,
    this.userMaxBidFare = 0,
    this.bidCeilingMaxFare = 0,
    this.bidStepAmount = 10,
    this.fareIncreaseWaitMinutes = 0,
    this.nextFareIncreaseAt,
  });

  static const RideBiddingInfo none = RideBiddingInfo();

  /// Drivers bid, the rider picks one. Outstation only.
  bool get isDriverBid => negotiationMode == 'driver_bid';

  /// No bids — the rider raises their own fare and dispatch re-runs.
  bool get isUserIncrement => negotiationMode == 'user_increment_only';

  bool get isNegotiable => isDriverBid || isUserIncrement;

  bool get isOpen => biddingStatus == 'open';

  /// Whether the rider still has headroom to raise.
  bool get canRaise => userMaxBidFare + bidStepAmount <= bidCeilingMaxFare;

  /// How many whole [bidStepAmount] increases still fit under the ceiling.
  ///
  /// The card offers one button per step up to a handful, so the rider can add
  /// what the trip is worth to them in one tap instead of waiting out the
  /// cooling-off period between single steps. Reads from the server's figures
  /// rather than recomputing the ceiling, which would drift from admin
  /// settings and produce raises the server rejects.
  int get remainingRaiseSteps {
    if (bidStepAmount <= 0) return 0;
    final headroom = bidCeilingMaxFare - userMaxBidFare;
    if (headroom < bidStepAmount) return 0;
    return (headroom / bidStepAmount).floor();
  }

  /// Seconds until the next self-increase is allowed, 0 when it already is.
  int get secondsUntilRaise {
    final next = nextFareIncreaseAt;
    if (next == null) return 0;
    final remaining = next.difference(DateTime.now()).inSeconds;
    return remaining > 0 ? remaining : 0;
  }

  factory RideBiddingInfo.fromJson(dynamic json) {
    final map = asMap(json);

    return RideBiddingInfo(
      bookingMode: asText(map['bookingMode'], 'normal').toLowerCase(),
      negotiationMode: asText(map['pricingNegotiationMode'], 'none').toLowerCase(),
      biddingStatus: asText(map['biddingStatus'], 'none').toLowerCase(),
      baseFare: asDouble(map['baseFare'] ?? map['fare']),
      bidFloorFare: asDouble(map['bidFloorFare']),
      userMaxBidFare: asDouble(map['userMaxBidFare']),
      bidCeilingMaxFare: asDouble(map['bidCeilingMaxFare']),
      // Never let this reach zero: it divides step arithmetic in the UI.
      bidStepAmount: asDouble(map['bidStepAmount'], 10) <= 0 ? 10 : asDouble(map['bidStepAmount'], 10),
      fareIncreaseWaitMinutes: asInt(map['fareIncreaseWaitMinutes']),
      nextFareIncreaseAt: DateTime.tryParse(asText(map['nextFareIncreaseAt']))?.toLocal(),
    );
  }
}

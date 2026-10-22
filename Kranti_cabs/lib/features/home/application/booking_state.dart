import '../../ride/data/models/ride_model.dart';
import '../data/models/set_price_model.dart';
import '../data/models/surge_info.dart';
import '../data/models/trip_category.dart';
import '../data/models/vehicle_type_model.dart';
import 'fare_calculator.dart';

class BookingLocation {
  final double lat;
  final double lng;
  final String address;

  const BookingLocation({required this.lat, required this.lng, required this.address});
}

/// A promo code the server has accepted, with the rules needed to price it.
///
/// Kept as rules rather than a single amount because the rider can still
/// switch vehicles after applying it, and each fare earns a different
/// discount. [discountFor] mirrors `computePromoDiscount` on the backend, which
/// recalculates and is authoritative when the ride is booked.
class AppliedPromo {
  final String code;
  final double discountPercent;
  final double maxDiscount;
  final double minimumTripAmount;

  const AppliedPromo({
    required this.code,
    required this.discountPercent,
    required this.maxDiscount,
    required this.minimumTripAmount,
  });

  factory AppliedPromo.fromJson(Map<String, dynamic> json) {
    double num(dynamic v) => double.tryParse('${v ?? 0}') ?? 0;
    return AppliedPromo(
      code: (json['code'] ?? '').toString(),
      discountPercent: num(json['discount_percentage']),
      maxDiscount: num(json['maximum_discount_amount']),
      minimumTripAmount: num(json['minimum_trip_amount']),
    );
  }

  /// What this code takes off [fare]; 0 when the fare is below its minimum.
  double discountFor(double fare) {
    if (fare <= 0 || fare < minimumTripAmount) return 0;
    // With no percentage the admin's amount is a flat discount; with one, the
    // amount is a cap on it.
    final raw = discountPercent > 0 ? fare * discountPercent / 100 : maxDiscount;
    final capped = discountPercent > 0 && maxDiscount > 0 && raw > maxDiscount ? maxDiscount : raw;
    final discount = capped > fare ? fare : capped;
    return double.parse(discount.toStringAsFixed(2));
  }
}

enum BookingStep { selectingLocations, selectingVehicle, confirming, findingDriver, noDriverFound, dispatched }

/// Whether the rider is coming back.
///
/// A round trip is charged for the return leg and is what the backend records
/// as `intercity.tripType`. Until now the One Way / Round Trip toggle only
/// coloured its own buttons — the choice never left the screen, so a round trip
/// was booked and priced exactly like a one-way.
enum TripType { oneWay, roundTrip }

extension TripTypeX on TripType {
  /// The value the backend stores on `Ride.intercity.tripType`.
  String get wireValue => this == TripType.roundTrip ? 'round_trip' : 'one_way';

  String get label => this == TripType.roundTrip ? 'Round Trip' : 'One Way';

  bool get isRoundTrip => this == TripType.roundTrip;
}

class BookingState {
  final BookingLocation? pickup;
  final BookingLocation? drop;
  final List<BookingLocation> stops;
  final double? distanceMeters;
  final double? durationSeconds;
  final List<VehicleTypeModel> vehicleTypes;
  final List<SetPriceModel> setPrices;

  /// Demand surge at the pickup. [setPrices] already include it.
  final SurgeInfo surge;
  final Map<String, int> etaMinutesByVehicle;
  final VehicleTypeModel? selectedVehicle;
  final FareBreakdown? fareBreakdown;
  final String paymentMethod;
  final String? promoCode;

  /// Set only once the server has accepted [promoCode].
  final AppliedPromo? appliedPromo;
  final DateTime? scheduledAt;

  /// One way or round trip, and whether this is an intercity (outstation) ride.
  /// Both travel to the backend and both change the fare.
  final TripType tripType;
  final bool isOutstation;

  /// When the rider wants to be driven back, for a round-trip outstation ride.
  /// Null for one-way trips; sent to the backend as `intercity.returnDate`.
  final DateTime? returnAt;

  /// The app module the rider came in through (Zi Airport, Zi City Ride ...).
  /// Filters the vehicle list to whatever that module offers.
  final String? moduleId;

  /// Whether the rider chose to name their own price instead of taking the
  /// quoted fare.
  ///
  /// Only offered when the selected vehicle allows it. What it turns into
  /// depends on the trip: an outstation ride opens for driver bids, a city ride
  /// becomes a fare the rider can raise themselves. The server decides which -
  /// the app only asks.
  final bool useBidding;

  /// The rider's ceiling for an outstation bidding ride, in rupees.
  ///
  /// Starts at the quoted fare and moves in the admin-configured step. The
  /// server clamps it into the allowed band, so this is a request, not a
  /// guarantee.
  final double bidMaxFare;

  final BookingStep step;
  /// True while the vehicle/pricing catalog is being fetched. Distinct from an
  /// empty catalog: "still loading" is a spinner, "nothing configured" is a
  /// message the rider can act on.
  final bool isLoadingCatalog;
  final bool isSubmitting;
  final String? error;
  final RideModel? createdRide;

  /// City, airport or outstation, once the server has classified the trip.
  /// Null until then, and while [checkingTrip] is true.
  final TripCategory? tripCategory;
  final bool checkingTrip;

  const BookingState({
    this.pickup,
    this.drop,
    this.stops = const [],
    this.distanceMeters,
    this.durationSeconds,
    this.vehicleTypes = const [],
    this.setPrices = const [],
    this.surge = SurgeInfo.none,
    this.etaMinutesByVehicle = const {},
    this.selectedVehicle,
    this.fareBreakdown,
    this.paymentMethod = 'cash',
    this.promoCode,
    this.appliedPromo,
    this.scheduledAt,
    this.tripType = TripType.oneWay,
    this.isOutstation = false,
    this.returnAt,
    this.moduleId,
    this.useBidding = false,
    this.bidMaxFare = 0,
    this.step = BookingStep.selectingLocations,
    this.isLoadingCatalog = false,
    this.isSubmitting = false,
    this.error,
    this.createdRide,
    this.tripCategory,
    this.checkingTrip = false,
  });

  /// The tariff configured for [vehicleTypeId], or null when there is none.
  ///
  /// Deliberately without a fallback. This used to return `setPrices.first`
  /// when a vehicle had no row of its own, which quoted the entire premium
  /// fleet at the cheapest row's rate — the rider only discovered the real
  /// fare when the trip ended. Showing no estimate is the honest failure.
  SetPriceModel? pricingFor(String vehicleTypeId) {
    for (final p in setPrices) {
      if (p.vehicleTypeId == vehicleTypeId) return p;
    }
    return null;
  }

  /// Whether this vehicle can actually be booked for an intercity trip —
  /// its own tariff has the outstation toggle on and real rates behind it.
  bool supportsOutstation(String vehicleTypeId) =>
      pricingFor(vehicleTypeId)?.supportsOutstation ?? false;

  BookingState copyWith({
    BookingLocation? pickup,
    BookingLocation? drop,
    List<BookingLocation>? stops,
    double? distanceMeters,
    double? durationSeconds,
    List<VehicleTypeModel>? vehicleTypes,
    List<SetPriceModel>? setPrices,
    SurgeInfo? surge,
    Map<String, int>? etaMinutesByVehicle,
    VehicleTypeModel? selectedVehicle,
    FareBreakdown? fareBreakdown,
    String? paymentMethod,
    String? promoCode,
    AppliedPromo? appliedPromo,
    DateTime? scheduledAt,
    TripType? tripType,
    bool? isOutstation,
    DateTime? returnAt,
    bool clearReturnAt = false,
    String? moduleId,
    bool? useBidding,
    double? bidMaxFare,
    BookingStep? step,
    bool? isLoadingCatalog,
    bool? isSubmitting,
    String? error,
    RideModel? createdRide,
    bool clearError = false,
    bool clearSelectedVehicle = false,
    bool clearScheduledAt = false,
    bool clearPromo = false,
    bool clearFareBreakdown = false,
    bool clearModule = false,
    TripCategory? tripCategory,
    bool? checkingTrip,
    bool clearTripCategory = false,
  }) {
    return BookingState(
      pickup: pickup ?? this.pickup,
      drop: drop ?? this.drop,
      stops: stops ?? this.stops,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      vehicleTypes: vehicleTypes ?? this.vehicleTypes,
      setPrices: setPrices ?? this.setPrices,
      surge: surge ?? this.surge,
      etaMinutesByVehicle: etaMinutesByVehicle ?? this.etaMinutesByVehicle,
      selectedVehicle:
          clearSelectedVehicle ? null : (selectedVehicle ?? this.selectedVehicle),
      fareBreakdown: clearFareBreakdown ? null : (fareBreakdown ?? this.fareBreakdown),
      paymentMethod: paymentMethod ?? this.paymentMethod,
      promoCode: clearPromo ? null : (promoCode ?? this.promoCode),
      appliedPromo: clearPromo ? null : (appliedPromo ?? this.appliedPromo),
      scheduledAt: clearScheduledAt ? null : (scheduledAt ?? this.scheduledAt),
      tripType: tripType ?? this.tripType,
      isOutstation: isOutstation ?? this.isOutstation,
      returnAt: clearReturnAt ? null : (returnAt ?? this.returnAt),
      moduleId: clearModule ? null : (moduleId ?? this.moduleId),
      useBidding: useBidding ?? this.useBidding,
      bidMaxFare: bidMaxFare ?? this.bidMaxFare,
      step: step ?? this.step,
      isLoadingCatalog: isLoadingCatalog ?? this.isLoadingCatalog,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      error: clearError ? null : (error ?? this.error),
      createdRide: createdRide ?? this.createdRide,
      tripCategory: clearTripCategory ? null : (tripCategory ?? this.tripCategory),
      checkingTrip: checkingTrip ?? this.checkingTrip,
    );
  }
}

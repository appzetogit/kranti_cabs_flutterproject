import '../data/models/set_price_model.dart';
import '../data/models/trip_category.dart';

class FareBreakdown {
  final double baseFare;
  final double distanceFare;
  final double timeFare;
  final double serviceTax;

  /// The per-ride platform fee, already included in [total].
  final double platformFee;

  /// The airport's flat charges on an airport trip, already in [total].
  final double airportFee;

  /// Railway station entry fee and state / MCD tax, already in [total].
  final List<LocationChargeLine> locationCharges;

  /// The least the hub's pickup parking can cost. NOT in [total]: the server
  /// adds it at trip end from how long the driver waited.
  final double parkingFrom;
  final bool parkingVaries;

  final double total;

  const FareBreakdown({
    required this.baseFare,
    required this.distanceFare,
    required this.timeFare,
    required this.serviceTax,
    this.platformFee = 0,
    this.airportFee = 0,
    this.locationCharges = const [],
    this.parkingFrom = 0,
    this.parkingVaries = false,
    required this.total,
  });

  /// The charges in [total] that the server adds to the fare by itself.
  double get serverAddedFees =>
      airportFee + locationCharges.fold<double>(0, (sum, line) => sum + line.amount);

  /// What to send as the booking's `fare`: [total] without the airport fee,
  /// station fee and state / MCD tax. The server adds those itself, so
  /// sending [total] would charge the rider for them twice.
  double get tripFare => double.parse((total - serverAddedFees).toStringAsFixed(2));
}

class FareCalculator {
  /// Client-side fare estimate only — the backend recalculates and is
  /// authoritative at ride completion.
  /// [isRoundTrip] charges the return leg — the rider is taking the car both
  /// ways, so the distance and time are doubled before the rate is applied.
  /// The base fare is not doubled: it is a one-off charge for the booking.
  ///
  /// [isOutstation] switches to the intercity tariff configured per vehicle
  /// type in Admin -> Set Prices, falling back to the city rate when a tariff
  /// has the outstation toggle on but no rates filled in.
  static FareBreakdown estimate({
    required SetPriceModel pricing,
    required double distanceMeters,
    required double durationSeconds,
    bool isRoundTrip = false,
    bool isOutstation = false,
    double airportFee = 0,
    List<LocationChargeLine> locationCharges = const [],
    double parkingFrom = 0,
    bool parkingVaries = false,
  }) {
    final locationTotal = locationCharges.fold<double>(0, (sum, line) => sum + line.amount);
    final useOutstation = isOutstation && pricing.supportsOutstation;

    final basePrice = useOutstation ? pricing.outstationBasePrice : pricing.basePrice;
    final baseDistanceKm =
        useOutstation ? pricing.outstationBaseDistanceKm : pricing.baseDistanceKm;
    final perKm =
        useOutstation ? pricing.outstationPricePerDistance : pricing.pricePerDistance;
    final perMinute = useOutstation ? pricing.outstationTimePrice : pricing.timePrice;

    // The return leg retraces the same route, so it costs the same again.
    final legMultiplier = isRoundTrip ? 2 : 1;
    final distanceKm = (distanceMeters / 1000) * legMultiplier;
    final durationMinutes = (durationSeconds / 60) * legMultiplier;

    final chargeableKm = (distanceKm - baseDistanceKm).clamp(0, double.infinity);

    final baseFare = basePrice;
    final distanceFare = chargeableKm * perKm;
    final timeFare = durationMinutes * perMinute;
    final subtotal = baseFare + distanceFare + timeFare;
    final serviceTax = subtotal * (pricing.serviceTaxPercent / 100);
    final total = (subtotal + serviceTax).clamp(basePrice, double.infinity);

    // The per-ride platform fee - the client's admin charges. Charged once per
    // booking on top of the trip, so it is not doubled for a round trip and not
    // rounded away with the trip fare.
    final platformFee = double.parse((pricing.platformFeeIsPercentage
            ? subtotal * pricing.platformFee / 100
            : pricing.platformFee)
        .toStringAsFixed(2));

    return FareBreakdown(
      baseFare: baseFare,
      distanceFare: distanceFare,
      timeFare: timeFare,
      serviceTax: serviceTax,
      platformFee: platformFee,
      airportFee: airportFee,
      locationCharges: locationCharges,
      parkingFrom: parkingFrom,
      parkingVaries: parkingVaries,
      // The airport fee, station fee and tax are charged once per trip, like
      // the platform fee.
      total: double.parse(
        (double.parse(total.toStringAsFixed(0)) + platformFee + airportFee + locationTotal)
            .toStringAsFixed(2),
      ),
    );
  }
}

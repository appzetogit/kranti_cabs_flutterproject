import '../data/models/set_price_model.dart';

class FareBreakdown {
  final double baseFare;
  final double distanceFare;
  final double timeFare;
  final double serviceTax;

  /// The per-ride platform fee, already included in [total].
  final double platformFee;

  /// The airport's flat charges on an airport trip, already in [total].
  final double airportFee;
  final double total;

  const FareBreakdown({
    required this.baseFare,
    required this.distanceFare,
    required this.timeFare,
    required this.serviceTax,
    this.platformFee = 0,
    this.airportFee = 0,
    required this.total,
  });
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
  }) {
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
      // The airport fee is charged once per trip, like the platform fee.
      total: double.parse(
        (double.parse(total.toStringAsFixed(0)) + platformFee + airportFee).toStringAsFixed(2),
      ),
    );
  }
}

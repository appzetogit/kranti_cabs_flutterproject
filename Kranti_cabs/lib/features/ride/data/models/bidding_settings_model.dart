import '../../../../core/utils/json_safe.dart';

/// The admin's negotiation bands, fetched from `/rides/app-settings/bidding`.
///
/// The app must not assume these. The server rejects a bid whose distance from
/// the base fare is not a whole multiple of the step, so a hardcoded increment
/// silently starts failing the moment an admin changes it.
class BiddingSettings {
  /// How far below and above the fare a driver may bid, as percentages.
  final double driverLowPercentage;
  final double driverHighPercentage;

  /// The increment a driver's bid must move in.
  final double driverStepAmount;

  /// How far above the fare a rider's own ceiling starts and may reach.
  final double userLowPercentage;
  final double userHighPercentage;

  /// The increment a rider's ceiling moves in.
  final double userStepAmount;

  /// Cooling-off between self-increases on a city ride.
  final int userFareIncreaseWaitMinutes;

  const BiddingSettings({
    this.driverLowPercentage = 10,
    this.driverHighPercentage = 20,
    this.driverStepAmount = 10,
    this.userLowPercentage = 10,
    this.userHighPercentage = 20,
    this.userStepAmount = 10,
    this.userFareIncreaseWaitMinutes = 0,
  });

  /// Matches the backend defaults, so a failed fetch degrades to today's
  /// behaviour rather than blocking the booking.
  static const BiddingSettings fallback = BiddingSettings();

  /// Where a city ride's fare actually starts once the rider opts in.
  ///
  /// Not the quoted fare: the server lifts it to the user floor
  /// (`baseFare x (1 + userLowPercentage/100)`, rounded up to a whole step) so
  /// the trip is worth a driver's while from the outset. Saying "book at this
  /// fare" without this would understate what the rider is agreeing to.
  double startingFareForCityRide(double quotedFare) {
    if (quotedFare <= 0) return quotedFare;

    final step = userStepAmount > 0 ? userStepAmount : 10;
    final target = quotedFare * (1 + (userLowPercentage / 100));
    final steps = ((target - quotedFare) / step).ceil();

    return quotedFare + (steps * step);
  }

  /// The highest a rider's ceiling may go for a given quote.
  double ceilingFor(double quotedFare) {
    if (quotedFare <= 0) return quotedFare;

    final step = userStepAmount > 0 ? userStepAmount : 10;
    final target = quotedFare * (1 + (userHighPercentage / 100));
    final steps = ((target - quotedFare) / step).ceil();

    return quotedFare + (steps * step);
  }

  factory BiddingSettings.fromJson(dynamic json) {
    final map = asMap(json);
    final settings = map.containsKey('settings') ? asMap(map['settings']) : map;

    double positive(dynamic value, double fallbackValue) {
      final parsed = asDouble(value, fallbackValue);
      return parsed > 0 ? parsed : fallbackValue;
    }

    return BiddingSettings(
      driverLowPercentage: positive(settings['driverLowPercentage'], 10),
      driverHighPercentage: positive(settings['driverHighPercentage'], 20),
      driverStepAmount: positive(settings['driverStepAmount'], 10),
      userLowPercentage: positive(settings['userLowPercentage'], 10),
      userHighPercentage: positive(settings['userHighPercentage'], 20),
      userStepAmount: positive(settings['userStepAmount'], 10),
      userFareIncreaseWaitMinutes: asInt(settings['userFareIncreaseWaitMinutes'], 0),
    );
  }
}

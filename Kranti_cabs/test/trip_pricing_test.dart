import 'package:flutter_test/flutter_test.dart';
import 'package:taxiuser/features/home/application/booking_state.dart';
import 'package:taxiuser/features/home/application/fare_calculator.dart';
import 'package:taxiuser/features/home/data/models/set_price_model.dart';
import 'package:taxiuser/features/home/data/models/surge_info.dart';
import 'package:taxiuser/features/home/data/models/trip_category.dart';

/// The pricing pieces the ride screen combines: what kind of trip the server
/// says it is, the airport fee, coupons and surge. Figures are the live
/// Bengaluru tariff and Kempegowda's fees, checked against the app's screen.
void main() {
  SetPriceModel bengaluruAirportNonAc() => SetPriceModel.fromJson({
        'id': 'row',
        'type_id': 'vehicle',
        'zone_id': 'bangalore',
        'service_location_id': 'blr',
        'base_price': 99,
        'base_distance': 2,
        'price_per_distance': 24,
        'time_price': 0,
        'waiting_charge': 2,
        'service_tax': 0,
      });

  group('TripCategory', () {
    test('reads an airport answer as the server sends it', () {
      final trip = TripCategory.fromJson({
        'category': 'airport',
        'module_id': '6a7f2c2683a46cae208a4cba',
        'module_name': 'Zi Airport',
        'airport': {'name': 'Devi Ahilyabai Holkar Airport IDR', 'end': 'drop', 'total_fee': 0},
      });
      expect(trip.isAirport, isTrue);
      expect(trip.isOutstation, isFalse);
      expect(trip.moduleId, '6a7f2c2683a46cae208a4cba');
      expect(trip.airportName, 'Devi Ahilyabai Holkar Airport IDR');
      expect(trip.airportFee, 0);
    });

    test('reads outstation and unserviceable answers', () {
      expect(TripCategory.fromJson({'category': 'outstation', 'module_id': 'x', 'airport': null}).isOutstation, isTrue);
      final none = TripCategory.fromJson({'category': 'unserviceable', 'message': "We don't serve this pickup point yet."});
      expect(none.isUnserviceable, isTrue);
      expect(none.message, "We don't serve this pickup point yet.");
    });

    test('falls back to a city trip on a malformed answer', () {
      final trip = TripCategory.fromJson({});
      expect(trip.category, 'city');
      expect(trip.airportFee, 0);
    });
  });

  group('FareCalculator', () {
    test('adds the airport fee once, on top of the trip fare', () {
      // Mavalli -> Kempegowda, 30.83 km: 99 + 28.83 x 24 = 791, plus Rs 275.
      final fare = FareCalculator.estimate(
        pricing: bengaluruAirportNonAc(),
        distanceMeters: 30830,
        durationSeconds: 74 * 60,
        airportFee: 275,
      );
      expect(fare.airportFee, 275);
      expect(fare.total, 1066);
    });

    test('charges no airport fee when none is passed', () {
      final fare = FareCalculator.estimate(
        pricing: bengaluruAirportNonAc(),
        distanceMeters: 30830,
        durationSeconds: 74 * 60,
      );
      expect(fare.airportFee, 0);
      expect(fare.total, 791);
    });

    test('a round trip doubles the distance but not the airport fee', () {
      final fare = FareCalculator.estimate(
        pricing: bengaluruAirportNonAc(),
        distanceMeters: 10000,
        durationSeconds: 600,
        isRoundTrip: true,
        airportFee: 100,
      );
      // 99 + (20 - 2) x 24 = 531, plus Rs 100.
      expect(fare.total, 631);
    });
  });

  group('AppliedPromo', () {
    test('percentage with a cap', () {
      const promo = AppliedPromo(code: 'P', discountPercent: 10, maxDiscount: 50, minimumTripAmount: 0);
      expect(promo.discountFor(236), 23.6);
      expect(promo.discountFor(900), 50);
    });

    test('an amount with no percentage is a flat discount, never above the fare', () {
      const promo = AppliedPromo(code: 'F', discountPercent: 0, maxDiscount: 50, minimumTripAmount: 0);
      expect(promo.discountFor(236), 50);
      expect(promo.discountFor(30), 30);
    });

    test('nothing below the minimum trip amount', () {
      const promo = AppliedPromo(code: 'M', discountPercent: 10, maxDiscount: 50, minimumTripAmount: 500);
      expect(promo.discountFor(236), 0);
    });
  });

  group('SurgeInfo', () {
    test('reads an active surge', () {
      final surge = SurgeInfo.fromJson({'multiplier': 1.2, 'ends_at': DateTime.now().add(const Duration(minutes: 7)).toUtc().toIso8601String()});
      expect(surge.isActive, isTrue);
      expect(surge.label, '1.20x');
      expect(surge.minutesLeft, inInclusiveRange(6, 7));
    });

    test('no surge for a missing or sub-1 multiplier', () {
      expect(SurgeInfo.fromJson(null).isActive, isFalse);
      expect(SurgeInfo.fromJson({'multiplier': 0.8}).multiplier, 1);
    });
  });
}

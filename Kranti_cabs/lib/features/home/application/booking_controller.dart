import '../../../core/constants/app_constants.dart';
import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers/core_providers.dart';
import '../../promo/application/promo_providers.dart';
import '../../ride/application/ride_providers.dart';
import '../../ride/data/models/ride_model.dart';
import '../data/models/set_price_model.dart';
import '../data/models/surge_info.dart';
import '../data/models/trip_category.dart';
import '../data/models/vehicle_type_model.dart';
import 'booking_state.dart';
import 'fare_calculator.dart';
import 'home_providers.dart';
import 'ride_search_controller.dart';

/// Average city-traffic speed assumed for client-side ETA estimation only.
const double _assumedSpeedKmph = 25;

/// What happened when the rider tapped Book.
///
/// This used to be a bool, and both screens answered every `false` with the
/// "no driver found" screen - so a ride that was never even sent, because it
/// had no price yet or none in this area, was reported to the rider as a
/// dispatch that found nobody.
enum BookingAttempt {
  /// The ride was created and dispatch has begun.
  booked,

  /// Nothing was sent because something the booking needs is missing. The
  /// reason is in [BookingState.error]; the rider stays where they are.
  notReady,

  /// The server wants the rider's identity verified first (KYC_REQUIRED). The
  /// message is in [BookingState.error]; the caller offers the KYC screen.
  kycRequired,

  /// The server or the network refused the booking.
  failed,
}

class BookingController extends StateNotifier<BookingState> {
  final Ref ref;

  BookingController(this.ref) : super(const BookingState());

  /// Loads the vehicle catalog and its pricing.
  ///
  /// The two are fetched concurrently but failed independently. They used to
  /// share a single `Future.wait`, which rejects the moment either side does —
  /// so a pricing endpoint having a bad day took the whole vehicle list down
  /// with it and the rider stared at a spinner that would never resolve.
  Future<void> loadCatalog() async {
    state = state.copyWith(isLoadingCatalog: true, clearError: true);

    final repo = ref.read(homeRepositoryProvider);
    // Scoped to the pickup whenever there is one. The ride screen reloads the
    // catalog on open, after the pickup is set, and this used to fetch every
    // city's table and overwrite the zone prices setPickup had just loaded.
    // The app then took the first row per vehicle - for ZI Auto in Bengaluru
    // that was Indore's, so the quote came out at Indore's rate.
    final pickup = state.pickup;
    final results = await Future.wait([
      _tryLoad<List<VehicleTypeModel>>(repo.getVehicleTypes, 'vehicle types'),
      _tryLoad<List<SetPriceModel>>(
        () => repo.getSetPrices(lat: pickup?.lat, lng: pickup?.lng),
        'set prices',
      ),
      _tryLoad<SurgeInfo>(
        () async => pickup == null ? SurgeInfo.none : await repo.getSurge(lat: pickup.lat, lng: pickup.lng),
        'surge',
      ),
    ]);


    // A failed call keeps whatever was already loaded rather than blanking it.
    final vehicleTypes = results[0] as List<VehicleTypeModel>? ?? state.vehicleTypes;
    // If the pickup moved while this was in flight, setPickup has already
    // fetched that zone's prices; these belong to the old pickup (or to no
    // city at all) and must not land on top of them.
    final pickupChanged = !identical(state.pickup, pickup);
    final setPrices = pickupChanged
        ? state.setPrices
        : (results[1] as List<SetPriceModel>? ?? state.setPrices);
    final surge = pickupChanged ? state.surge : (results[2] as SurgeInfo? ?? state.surge);

    // The pre-selected vehicle has to belong to the module the rider came in
    // through, or the fare shown on entry would be for a vehicle that is not
    // even in the list.
    final offered = vehicleTypes
        .where((v) => v.isOfferedUnderModule(state.moduleId))
        .where((v) => !state.isOutstation || state.supportsOutstation(v.id))
        .toList();
    final defaultVehicle = state.selectedVehicle ??
        (offered.isNotEmpty
            ? offered.firstWhere(
                (v) => (v.transportType.isEmpty || v.transportType == 'taxi') && v.deliveryCategory.isEmpty,
                orElse: () => offered.first,
              )
            : null);

    state = state.copyWith(
      vehicleTypes: vehicleTypes,
      setPrices: setPrices,
      surge: surge,
      selectedVehicle: defaultVehicle,
      isLoadingCatalog: false,
      // Only surfaced when there is genuinely nothing to show. Missing prices
      // alone are survivable — `pricingFor` falls back — and should not put an
      // error in front of a rider who can still book.
      error: vehicleTypes.isEmpty ? 'No vehicles are available right now.' : null,
      clearError: vehicleTypes.isNotEmpty,
    );

    _recalculateFare();
    unawaited(_loadDriverEtas());
  }

  Future<T?> _tryLoad<T>(Future<T> Function() load, String label) async {
    try {
      return await load();
    } catch (error) {
      developer.log('Could not load $label: $error', name: 'BookingController');
      return null;
    }
  }

  /// Fetches the closest available driver's ETA per vehicle type in
  /// parallel so the ride-type list can show a real "X mins away" instead
  /// of a hardcoded placeholder. Best-effort: failures are swallowed per
  /// vehicle type so one missing driver pool doesn't block the others.
  Future<void> _loadDriverEtas() async {
    final pickup = state.pickup;
    if (pickup == null || state.vehicleTypes.isEmpty) return;

    final repo = ref.read(homeRepositoryProvider);
    final entries = await Future.wait(state.vehicleTypes.map((vehicle) async {
      try {
        final eta = await repo.getClosestDriverEtaMinutes(
          lat: pickup.lat,
          lng: pickup.lng,
          vehicleTypeId: vehicle.id,
        );
        return MapEntry(vehicle.id, eta);
      } catch (_) {
        return MapEntry(vehicle.id, null);
      }
    }));

    final etaMap = <String, int>{
      for (final e in entries)
        if (e.value != null) e.key: e.value!,
    };
    state = state.copyWith(etaMinutesByVehicle: etaMap);
  }

  void setPickup(BookingLocation location) {
    state = state.copyWith(pickup: location, clearError: true);
    _recalculateRoute();
    unawaited(_loadDriverEtas());
    // Tariffs are per zone, so moving the pickup can re-price the whole fleet.
    unawaited(_reloadTariffsFor(location));
  }

  /// Re-fetches tariffs for the zone [pickup] sits in.
  ///
  /// The catalog is first loaded before any pickup exists, so those opening
  /// prices belong to no particular city. This is what makes the quote match
  /// what the backend will actually charge.
  Future<void> _reloadTariffsFor(BookingLocation pickup) async {
    try {
      final repo = ref.read(homeRepositoryProvider);
      final prices = await repo.getSetPrices(lat: pickup.lat, lng: pickup.lng);
      final surge = await repo.getSurge(lat: pickup.lat, lng: pickup.lng);
      // A later pickup has fetched its own prices; these are for an old one.
      if (!mounted || prices.isEmpty || !identical(state.pickup, pickup)) return;
      state = state.copyWith(setPrices: prices, surge: surge);
      _recalculateFare();
    } catch (_) {
      // Keep whatever is loaded: a stale estimate beats a blank one, and the
      // backend is authoritative on the fare either way.
    }
  }

  /// Re-reads prices and surge for the current pickup. The ride screen calls
  /// this every minute: surge comes and goes by the minute, and a rider who
  /// sits on the screen should book at the price in force, not the one from
  /// when they arrived.
  Future<void> refreshTariffs() async {
    final pickup = state.pickup;
    if (pickup != null) await _reloadTariffsFor(pickup);
  }

  void setDrop(BookingLocation location) {
    state = state.copyWith(drop: location, clearError: true);
    _recalculateRoute();
  }

  void setStops(List<BookingLocation> stops) {
    state = state.copyWith(stops: stops, clearError: true);
    _recalculateRoute();
  }

  void selectVehicle(VehicleTypeModel vehicle) {
    state = state.copyWith(selectedVehicle: vehicle);
    _recalculateFare();
  }

  void setPaymentMethod(String method) {
    state = state.copyWith(paymentMethod: AppConstants.onlinePaymentsEnabled ? method : 'cash');
  }

  /// Checks [code] with the server and applies it, or removes the coupon when
  /// [code] is empty. Returns why it was refused, or null when it applied.
  ///
  /// This used to store whatever was typed without asking anyone, so the rider
  /// saw no discount, and a mistyped or expired code only surfaced when the
  /// booking itself failed on it.
  Future<String?> applyPromoCode(String? code) async {
    final trimmed = code?.trim().toUpperCase() ?? '';
    if (trimmed.isEmpty) {
      state = state.copyWith(clearPromo: true);
      return null;
    }

    final fare = state.fareBreakdown?.total;
    if (fare == null || fare <= 0) {
      return 'Choose your pickup, drop and ride first, then apply the coupon.';
    }

    try {
      final result = await ref.read(promoRepositoryProvider).validatePromo(
            code: trimmed,
            fare: fare,
            lat: state.pickup?.lat,
            lng: state.pickup?.lng,
          );
      if (result['eligible'] != true) {
        return (result['message'] ?? 'This coupon cannot be used.').toString();
      }
      final promo = Map<String, dynamic>.from((result['promo'] as Map?) ?? {'code': trimmed});
      state = state.copyWith(promoCode: trimmed, appliedPromo: AppliedPromo.fromJson(promo));
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Could not check the coupon. Please try again.';
    }
  }

  /// The coupon discount on [vehicle]'s fare, or 0 with no coupon or a fare
  /// below its minimum.
  double promoDiscountFor(VehicleTypeModel vehicle) {
    final promo = state.appliedPromo;
    final fare = fareForVehicle(vehicle)?.total;
    if (promo == null || fare == null) return 0;
    return promo.discountFor(fare);
  }

  void setScheduledAt(DateTime? time) {
    if (time == null) {
      state = state.copyWith(clearScheduledAt: true);
    } else {
      state = state.copyWith(scheduledAt: time);
    }
  }

  void goToStep(BookingStep step) {
    state = state.copyWith(step: step);
  }

  void _recalculateRoute() {
    final pickup = state.pickup;
    final drop = state.drop;
    if (pickup == null || drop == null) return;

    final locationService = ref.read(locationServiceProvider);
    double totalDistanceMeters = 0;
    BookingLocation current = pickup;

    for (final stop in state.stops) {
      totalDistanceMeters += locationService.distanceMeters(
        current.lat,
        current.lng,
        stop.lat,
        stop.lng,
      );
      current = stop;
    }

    totalDistanceMeters += locationService.distanceMeters(
      current.lat,
      current.lng,
      drop.lat,
      drop.lng,
    );

    final durationSeconds = (totalDistanceMeters / 1000) / _assumedSpeedKmph * 3600;

    state = state.copyWith(
      distanceMeters: totalDistanceMeters,
      durationSeconds: durationSeconds,
    );
    _recalculateFare();
    unawaited(_classifyTrip(pickup, drop));
  }

  /// Bumped on every classification so a slow answer for an old pickup or
  /// drop cannot overwrite the answer for the current one.
  int _tripCheck = 0;

  /// Whether the rider picked One Way / Round Trip themselves on the toggle.
  bool _riderChoseTripType = false;

  /// The last answer, and the pickup/drop it was for. Re-checking the same
  /// trip (the ride screen does on every open) applies it at once and refreshes
  /// quietly, instead of falling back to the tile's list behind a
  /// "Checking your trip" message while the request is out.
  String? _lastTripKey;
  TripCategory? _lastTrip;

  String _tripKey(BookingLocation pickup, BookingLocation drop) =>
      '${pickup.lat.toStringAsFixed(5)},${pickup.lng.toStringAsFixed(5)}>'
      '${drop.lat.toStringAsFixed(5)},${drop.lng.toStringAsFixed(5)}';

  /// Asks the server what kind of trip this is and offers only its vehicles:
  /// airport vehicles to or from an airport the admin marked, outstation ones
  /// for a drop outside the city, city ones otherwise.
  ///
  /// This overrides the module of the tile the rider tapped - "City Ride" to
  /// the airport becomes an airport trip, which the ride screen says.
  Future<void> _classifyTrip(BookingLocation pickup, BookingLocation drop) async {
    final check = ++_tripCheck;
    final key = _tripKey(pickup, drop);
    final known = key == _lastTripKey ? _lastTrip : null;
    if (known != null) {
      _applyTrip(known);
    } else {
      state = state.copyWith(checkingTrip: true);
    }
    try {
      final trip = await ref
          .read(homeRepositoryProvider)
          .getTripCategory(
            pickupLat: pickup.lat,
            pickupLng: pickup.lng,
            dropLat: drop.lat,
            dropLng: drop.lng,
          )
          // A slow network must not hold Book behind "Checking your trip".
          .timeout(const Duration(seconds: 8));
      if (!mounted || check != _tripCheck) return;
      _lastTripKey = key;
      _lastTrip = trip;
      _applyTrip(trip);
    } catch (error) {
      // The rider can still book from the tile they chose; the server records
      // the real category on the ride either way.
      developer.log('Could not classify trip: $error', name: 'BookingController');
      if (mounted && check == _tripCheck && known == null) {
        state = state.copyWith(checkingTrip: false, clearTripCategory: true);
      }
    }
  }

  /// Switches to the trip's module and rates and re-prices.
  void _applyTrip(TripCategory trip) {
    state = state.copyWith(tripCategory: trip, checkingTrip: false);
    if (trip.isUnserviceable) return;
    // The rider tapped Outstation: keep it, even when the server calls the
    // trip "city". Overriding that choice used to book every outstation trip
    // as a city ride, so drivers never saw an outstation request.
    final keepOutstation = _riderChoseOutstation && !trip.isOutstation;
    if (trip.moduleId != null && !keepOutstation) setModule(trip.moduleId);
    final wasOutstation = state.isOutstation;
    setOutstation(trip.isOutstation || _riderChoseOutstation);
    // Match what the Outstation tile does: an intercity trip starts as a
    // round trip, and leaving outstation goes back to one way. Without this
    // an automatically detected outstation trip was priced one way and
    // looked far cheaper than the same trip booked from the tile. Only on
    // a change, so a rider's own choice on the toggle is not overridden.
    if (!_riderChoseTripType) {
      if (trip.isOutstation && !wasOutstation) setTripType(TripType.roundTrip);
      if (!trip.isOutstation && wasOutstation) setTripType(TripType.oneWay);
    }
    _recalculateFare();
  }

  /// Classifies the current pickup and drop again. The ride screen calls this
  /// on open: the search screen re-applies its tile's module and outstation
  /// setting whenever it is shown (including after Edit), which would
  /// otherwise leave the ride screen priced for the tile, not the trip.
  Future<void> recheckTrip() async {
    final pickup = state.pickup;
    final drop = state.drop;
    if (pickup != null && drop != null) await _classifyTrip(pickup, drop);
  }

  void _recalculateFare() {
    final vehicle = state.selectedVehicle;
    if (vehicle == null) return;
    final breakdown = fareForVehicle(vehicle);
    // A vehicle with no fare must not keep the last one. This used to return
    // early and leave the previous fare in place - harmless while every
    // vehicle could borrow some price, but a vehicle can now have none in a
    // zone, and the stale fare would have booked it at another vehicle's, or
    // another city's, price.
    state = breakdown == null
        ? state.copyWith(clearFareBreakdown: true)
        : state.copyWith(fareBreakdown: breakdown);
  }

  /// Why the selected ride can't be booked yet, or null when it can.
  ///
  /// The screens use this to disable Book and say why, and [confirmBooking]
  /// uses it as its guard, so the button and the booking can never disagree.
  String? get bookingBlocker {
    final vehicle = state.selectedVehicle;
    final trip = state.tripCategory;
    if (trip != null && trip.isUnserviceable) {
      return trip.message ?? "We don't serve this pickup point yet.";
    }
    if (state.pickup == null || state.drop == null || vehicle == null) {
      return 'Please select pickup, drop and a ride type';
    }
    if (state.checkingTrip) return 'Checking your trip. One moment.';
    if (state.fareBreakdown != null) return null;
    if (state.distanceMeters != null &&
        state.durationSeconds != null &&
        state.pricingFor(vehicle.id) == null) {
      return "${vehicle.name} isn't available in this area yet.";
    }
    return 'Working out your fare. One moment.';
  }

  /// Switches between one way and round trip, re-pricing the selection so the
  /// fare on screen matches the choice immediately.
  ///
  /// [byRider] marks a choice made on the toggle, which the automatic
  /// outstation default then leaves alone for the rest of this search.
  void setTripType(TripType tripType, {bool byRider = false}) {
    _riderChoseTripType = byRider;
    if (state.tripType == tripType) return;
    // A one-way trip has no return, so drop any return time the rider had set.
    state = tripType.isRoundTrip
        ? state.copyWith(tripType: tripType)
        : state.copyWith(tripType: tripType, clearReturnAt: true);
    _repriceSelectedVehicle();
  }

  /// The rider's chosen return date/time for a round-trip outstation ride.
  /// Passing null clears it.
  void setReturnAt(DateTime? time) {
    if (time == null) {
      state = state.copyWith(clearReturnAt: true);
    } else {
      state = state.copyWith(returnAt: time);
    }
  }

  /// Marks this booking as an intercity trip, which switches to the outstation
  /// tariff and files the ride as `intercity` on the backend.
  /// Records which app module the rider entered through.
  ///
  /// Also drops a selected vehicle that the new module does not offer —
  /// otherwise a car chosen under Zi City Ride would stay selected, and priced,
  /// after switching to Zi Airport where it is not on the list.
  void setModule(String? moduleId) {
    if (state.moduleId == moduleId) return;

    final stillOffered =
        state.selectedVehicle?.isOfferedUnderModule(moduleId) ?? false;

    state = state.copyWith(
      moduleId: moduleId,
      // copyWith reads a null moduleId as "unchanged", so leaving a module
      // (the plain search bar after Zi Airport) has to say so - otherwise the
      // next booking stayed scoped to airport vehicles.
      clearModule: moduleId == null,
      clearSelectedVehicle: !stillOffered,
    );

    if (!stillOffered) {
      final replacement = state.vehicleTypes
          .where((v) => v.isOfferedUnderModule(moduleId))
          .where((v) => (v.transportType.isEmpty || v.transportType == 'taxi') && v.deliveryCategory.isEmpty)
          .firstOrNull;
      if (replacement != null) selectVehicle(replacement);
    }
  }

  /// Set when the rider picks the Outstation tile, so the server's own
  /// classification never switches it back to a city ride.
  bool _riderChoseOutstation = false;

  /// The Outstation (or City) tile's choice, made by the rider.
  void chooseOutstation(bool isOutstation) {
    _riderChoseOutstation = isOutstation;
    setOutstation(isOutstation);
  }

  void setOutstation(bool isOutstation) {
    if (state.isOutstation == isOutstation) return;
    state = state.copyWith(isOutstation: isOutstation);

    // A vehicle picked for a city trip may have no intercity tariff at all.
    // Leaving it selected would quote the city rate for a 300 km trip, so it is
    // swapped for one that can actually be booked.
    final selected = state.selectedVehicle;
    if (isOutstation && selected != null && !state.supportsOutstation(selected.id)) {
      final replacement = state.vehicleTypes
          .where((v) => v.isOfferedUnderModule(state.moduleId))
          .where((v) => state.supportsOutstation(v.id))
          .firstOrNull;
      state = state.copyWith(
        selectedVehicle: replacement,
        clearSelectedVehicle: replacement == null,
      );
    }

    _repriceSelectedVehicle();
  }

  /// Keeps the confirmed fare in step with a changed trip type — without this
  /// the tile would update but the booking would still carry the old total.
  void _repriceSelectedVehicle() {
    final vehicle = state.selectedVehicle;
    if (vehicle == null) return;
    final breakdown = fareForVehicle(vehicle);
    if (breakdown == null) return;
    state = state.copyWith(fareBreakdown: breakdown);
  }

  FareBreakdown? fareForVehicle(VehicleTypeModel vehicle) {
    final distanceMeters = state.distanceMeters;
    final durationSeconds = state.durationSeconds;
    if (distanceMeters == null || durationSeconds == null) return null;

    final pricing = state.pricingFor(vehicle.id);
    if (pricing == null) return null;

    return FareCalculator.estimate(
      pricing: pricing,
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
      isRoundTrip: state.tripType.isRoundTrip,
      isOutstation: state.isOutstation,
      airportFee: state.tripCategory?.isAirport == true ? state.tripCategory!.airportFee : 0,
      // Station entry fee and state / MCD tax, priced for this vehicle's class
      // the way the server prices them at booking.
      locationCharges: state.tripCategory?.bookingChargesFor(vehicle.chargeClass) ?? const [],
      parkingFrom: state.tripCategory?.parkingFromFor(vehicle.chargeClass) ?? 0,
      parkingVaries: state.tripCategory?.parkingVariesFor(vehicle.chargeClass) ?? false,
      tripDays: outstationTripDays,
    );
  }

  /// Days an outstation round trip is billed for: calendar days from the
  /// travel date (or today) to the return date, counted inclusively - a
  /// same-day return is 1 day. The server counts the same way.
  int get outstationTripDays {
    final start = state.scheduledAt ?? DateTime.now();
    final end = state.returnAt;
    if (end == null) return 1;
    final startDay = DateTime(start.year, start.month, start.day);
    final endDay = DateTime(end.year, end.month, end.day);
    final days = endDay.difference(startDay).inDays + 1;
    return days < 1 ? 1 : days;
  }

  /// Turns naming-your-own-price on or off.
  ///
  /// The ceiling resets to the quoted fare each time it is switched on, so a
  /// stale figure from a previous vehicle cannot be carried over into a
  /// booking the rider did not intend.
  void setUseBidding(bool value) {
    final quoted = state.fareBreakdown?.total ?? 0;
    state = state.copyWith(
      useBidding: value,
      bidMaxFare: value ? quoted : 0,
    );
  }

  /// Moves the rider's ceiling by [steps] increments of [stepAmount].
  ///
  /// Floored at the quoted fare: bidding below it would leave the ride with no
  /// takers and the server would reject the bid anyway.
  void adjustBidMaxFare({required double stepAmount, int steps = 1}) {
    final quoted = state.fareBreakdown?.total ?? 0;
    final current = state.bidMaxFare > 0 ? state.bidMaxFare : quoted;
    final next = current + (stepAmount * steps);

    state = state.copyWith(bidMaxFare: next < quoted ? quoted : next);
  }

  /// Swaps in a fresher copy of the ride the rider is waiting on.
  ///
  /// Used after a fare increase, where the server returns new negotiation
  /// figures (fare, ceiling, next-increase time) that the search screen reads
  /// straight off the created ride.
  void replaceCreatedRide(RideModel ride) {
    state = state.copyWith(createdRide: ride);
  }

  Future<BookingAttempt> confirmBooking() async {
    final blocker = bookingBlocker;
    final pickup = state.pickup;
    final drop = state.drop;
    final vehicle = state.selectedVehicle;
    final fare = state.fareBreakdown;
    // The null checks stay alongside the blocker so the values below are
    // known to be non-null.
    if (blocker != null || pickup == null || drop == null || vehicle == null || fare == null) {
      state = state.copyWith(error: blocker ?? 'Please select pickup, drop and a ride type');
      return BookingAttempt.notReady;
    }

    final stepBefore = state.step;
    state = state.copyWith(isSubmitting: true, clearError: true, step: BookingStep.findingDriver);

    // Armed before the POST so a driver who accepts immediately can't beat us
    // to the `rideAccepted` event.
    final search = ref.read(rideSearchControllerProvider.notifier);
    search.beginCreating();

    try {
      final ride = await ref.read(rideRepositoryProvider).createRide(
            pickup: [pickup.lng, pickup.lat],
            drop: [drop.lng, drop.lat],
            pickupAddress: pickup.address,
            dropAddress: drop.address,
            stops: state.stops
                .map((s) => {
                      'lat': s.lat,
                      'lng': s.lng,
                      'address': s.address,
                    })
                .toList(),
            // The trip fare alone: the server adds the airport fee, station fee
            // and state / MCD tax itself. Sending the total charged airport
            // riders the airport fee twice.
            fare: fare.tripFare,
            // Sent separately so the server knows how much of `fare` is admin's
            // fee rather than the driver's trip money.
            platformFee: fare.platformFee,
            // The surge [fare] was priced under, recorded on the ride.
            surgeMultiplier: state.surge.multiplier,
            estimatedDistanceMeters: state.distanceMeters ?? 0,
            estimatedDurationMinutes: (state.durationSeconds ?? 0) / 60,
            vehicleTypeId: vehicle.id,
            paymentMethod: state.paymentMethod,
            // Only a coupon that discounts this fare. One applied to another
            // vehicle can fall below its minimum here, and sending it anyway
            // makes the server refuse the whole booking.
            promoCode: state.appliedPromo != null && promoDiscountFor(vehicle) > 0
                ? state.appliedPromo!.code
                : null,
            scheduledAt: state.scheduledAt,
            // An outstation booking is stored as an intercity ride so the
            // driver app, admin reports and history can all tell the two apart.
            serviceType: state.isOutstation ? 'intercity' : 'ride',
            // Honoured only for a vehicle the admin marked biddable; anything
            // else falls back to the quoted fare server-side.
            bookingMode: state.useBidding ? 'bidding' : null,
            userMaxBidFare: state.useBidding ? state.bidMaxFare : null,
            intercity: {
              'tripType': state.tripType.wireValue,
              'fromCity': pickup.address,
              'toCity': drop.address,
              'distance': ((state.distanceMeters ?? 0) / 1000),
              'vehicleName': vehicle.name,
              if (state.scheduledAt != null)
                'travelDate': state.scheduledAt!.toIso8601String(),
              // The return leg's date/time, only on a round trip.
              if (state.tripType.isRoundTrip && state.returnAt != null)
                'returnDate': state.returnAt!.toIso8601String(),
            },
          );
      search.attachRide(ride);
      state = state.copyWith(
        isSubmitting: false,
        createdRide: ride,
        step: BookingStep.dispatched,
      );
      return BookingAttempt.booked;
    } catch (e) {
      // Not a dispatch failure: the rider just has to verify first, then retry.
      // A 403 here must never be treated as a logout.
      if (e is ApiException && e.code == 'KYC_REQUIRED') {
        search.reset();
        state = state.copyWith(isSubmitting: false, error: e.message, step: stepBefore);
        return BookingAttempt.kycRequired;
      }
      search.failCreate(e.toString());
      state = state.copyWith(
        isSubmitting: false,
        error: e.toString(),
        step: BookingStep.noDriverFound,
      );
      return BookingAttempt.failed;
    }
  }

  void reset() {
    ref.read(rideSearchControllerProvider.notifier).reset();
    state = const BookingState();
  }
}

final bookingControllerProvider =
    StateNotifierProvider<BookingController, BookingState>((ref) {
  return BookingController(ref);
});

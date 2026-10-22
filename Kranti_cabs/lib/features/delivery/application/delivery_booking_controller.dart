import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../home/application/booking_state.dart';
import '../../home/application/home_providers.dart';
import '../../home/data/models/vehicle_type_model.dart';
import '../data/delivery_repository.dart';
import '../data/models/goods_type_model.dart';
import '../data/models/parcel_model.dart';
import 'delivery_providers.dart';

/// Everything gathered across the delivery booking screens.
///
/// Held in one place so the vehicle picker, address screen and contact sheet
/// can each contribute a piece without passing arguments down a route chain —
/// and so a back-navigation keeps what was already entered.
class DeliveryBookingState {
  final String vehicleTypeId;
  final String vehicleName;
  final BookingLocation? pickup;
  final BookingLocation? drop;
  final String senderName;
  final String senderMobile;
  final String receiverName;
  final String receiverMobile;
  final String category;

  /// Which app module (Zi Parcel, or any other module an admin has marked
  /// `delivery`) the rider entered this flow through — set once, from the
  /// route the module tile pushed, and carried by every screen after it
  /// since they all share this one controller.
  final String? moduleId;

  /// Free-text description of what is being sent, typed by the rider.
  ///
  /// Kept separate from [category], which is validated against the admin's
  /// GoodsType catalog for vehicle compatibility — a typed value would fail
  /// that check, so this rides along as the parcel description instead.
  final String goodsType;

  /// The delivery card the rider picked ('trucks' | '2wheeler' | 'auto' | 'movers').
  final String deliveryCategoryId;

  /// Approximate weight the sender declared, e.g. '5 kg'. The driver sees it on
  /// the offer so they know whether their vehicle can take it.
  final String weight;

  /// Hosted URLs of the parcel photos the sender took, at most two.
  final List<String> photos;

  /// Handling notes for the driver ('fragile', 'call before arriving').
  final String instructions;
  final DeliveryQuote? quote;
  final bool quoting;
  final String? error;

  const DeliveryBookingState({
    this.vehicleTypeId = '',
    this.vehicleName = '',
    this.pickup,
    this.drop,
    this.senderName = '',
    this.senderMobile = '',
    this.receiverName = '',
    this.receiverMobile = '',
    this.category = '',
    this.moduleId,
    this.goodsType = '',
    this.deliveryCategoryId = '',
    this.weight = '',
    this.photos = const [],
    this.instructions = '',
    this.quote,
    this.quoting = false,
    this.error,
  });

  bool get hasSender =>
      senderName.trim().isNotEmpty && senderMobile.trim().length >= 10;
  bool get hasReceiver =>
      receiverName.trim().isNotEmpty && receiverMobile.trim().length >= 10;

  /// What the parcel is and roughly how heavy. Both reach the driver on the
  /// offer card, so the delivery is not bookable without them.
  bool get hasParcelDetails =>
      category.trim().isNotEmpty && weight.trim().isNotEmpty;

  /// Booking needs a route, a vehicle, both contacts and a server quote.
  bool get canConfirm =>
      pickup != null &&
      drop != null &&
      vehicleTypeId.isNotEmpty &&
      hasSender &&
      hasReceiver &&
      hasParcelDetails &&
      quote != null;

  DeliveryBookingState copyWith({
    String? vehicleTypeId,
    String? vehicleName,
    BookingLocation? pickup,
    BookingLocation? drop,
    String? senderName,
    String? senderMobile,
    String? receiverName,
    String? receiverMobile,
    String? category,
    String? moduleId,
    String? goodsType,
    String? deliveryCategoryId,
    String? weight,
    List<String>? photos,
    String? instructions,
    DeliveryQuote? quote,
    bool clearQuote = false,
    bool? quoting,
    String? error,
    bool clearError = false,
  }) {
    return DeliveryBookingState(
      vehicleTypeId: vehicleTypeId ?? this.vehicleTypeId,
      vehicleName: vehicleName ?? this.vehicleName,
      pickup: pickup ?? this.pickup,
      drop: drop ?? this.drop,
      senderName: senderName ?? this.senderName,
      senderMobile: senderMobile ?? this.senderMobile,
      receiverName: receiverName ?? this.receiverName,
      receiverMobile: receiverMobile ?? this.receiverMobile,
      category: category ?? this.category,
      moduleId: moduleId ?? this.moduleId,
      goodsType: goodsType ?? this.goodsType,
      deliveryCategoryId: deliveryCategoryId ?? this.deliveryCategoryId,
      weight: weight ?? this.weight,
      photos: photos ?? this.photos,
      instructions: instructions ?? this.instructions,
      quote: clearQuote ? null : (quote ?? this.quote),
      quoting: quoting ?? this.quoting,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class DeliveryBookingController extends StateNotifier<DeliveryBookingState> {
  final Ref ref;

  DeliveryBookingController(this.ref) : super(const DeliveryBookingState());

  /// Records which app module the rider entered this flow through — set
  /// once, from the route the module tile pushed. Without this, a vehicle
  /// the admin scoped to a different module (e.g. one they marked as
  /// airport-only) would still show up here, since [deliveryVehicleTypesProvider]
  /// has nothing else to filter on.
  void setModule(String? moduleId) {
    if (state.moduleId == moduleId) return;
    state = state.copyWith(moduleId: moduleId);
  }

  void selectDeliveryCategory(String categoryId) {
    // Switching card invalidates the chosen vehicle — its pricing belongs to a
    // different class of service.
    state = state.copyWith(
      deliveryCategoryId: categoryId,
      vehicleTypeId: '',
      vehicleName: '',
      clearQuote: true,
    );
  }

  void selectVehicle({required String id, required String name}) {
    // Pricing is per vehicle type, so an existing quote is stale the moment
    // the rider switches vehicle.
    state = state.copyWith(
      vehicleTypeId: id,
      vehicleName: name,
      clearQuote: true,
    );
    _refreshQuote();
  }

  void setPickup(BookingLocation location) {
    state = state.copyWith(pickup: location, clearQuote: true);
    _refreshQuote();
  }

  void setDrop(BookingLocation location) {
    state = state.copyWith(drop: location, clearQuote: true);
    _refreshQuote();
  }

  void clearDrop() {
    state = DeliveryBookingState(
      vehicleTypeId: state.vehicleTypeId,
      vehicleName: state.vehicleName,
      pickup: state.pickup,
      drop: null,
      senderName: state.senderName,
      senderMobile: state.senderMobile,
      receiverName: state.receiverName,
      receiverMobile: state.receiverMobile,
      category: state.category,
      moduleId: state.moduleId,
      goodsType: state.goodsType,
      deliveryCategoryId: state.deliveryCategoryId,
      weight: state.weight,
      photos: state.photos,
      instructions: state.instructions,
      quote: null,
      quoting: false,
      error: null,
    );
  }

  void setContacts({
    required String senderName,
    required String senderMobile,
    required String receiverName,
    required String receiverMobile,
    String? goodsType,
  }) {
    state = state.copyWith(
      senderName: senderName,
      senderMobile: senderMobile,
      receiverName: receiverName,
      receiverMobile: receiverMobile,
      goodsType: goodsType,
    );
  }

  /// Saved from the parcel details screen in one go.
  ///
  /// Changing the material can change which vehicles are allowed to carry it,
  /// so the quote is refreshed rather than kept — the same reason
  /// [setCategory] does.
  void setParcelDetails({
    required String category,
    required String weight,
    required List<String> photos,
    required String instructions,
  }) {
    state = state.copyWith(
      category: category,
      weight: weight,
      photos: photos,
      instructions: instructions,
      clearQuote: true,
    );
    _refreshQuote();
  }

  void setCategory(String category) {
    state = state.copyWith(category: category, clearQuote: true);
    _refreshQuote();
  }

  /// Prefills the sender from the signed-in profile — the rider is almost
  /// always the sender, and re-typing their own details is friction.
  void prefillSenderFrom({String? name, String? phone}) {
    if (state.senderName.isNotEmpty) return;
    state = state.copyWith(senderName: name ?? '', senderMobile: phone ?? '');
  }

  Future<void> _refreshQuote() async {
    final pickup = state.pickup;
    final drop = state.drop;
    if (pickup == null || drop == null) return;

    // The quote endpoint prices per vehicle type, so without one there is
    // nothing to ask for. This used to return silently, leaving the fare card
    // stuck on a generic failure with no hint of the real cause.
    if (state.vehicleTypeId.isEmpty) {
      state = state.copyWith(
        quoting: false,
        clearQuote: true,
        error: 'Choose a delivery vehicle to see the fare.',
      );
      return;
    }

    state = state.copyWith(quoting: true, clearError: true);
    try {
      final quote = await ref
          .read(deliveryRepositoryProvider)
          .getQuote(
            vehicleTypeId: state.vehicleTypeId,
            pickup: [pickup.lng, pickup.lat],
            drop: [drop.lng, drop.lat],
            category: state.category,
          );
      state = state.copyWith(quote: quote, quoting: false);
    } on ApiException catch (e) {
      // The server's own reason (unpriced vehicle, goods type not allowed, …)
      // is far more actionable than a generic failure.
      state = state.copyWith(
        quoting: false,
        error: e.message,
        clearQuote: true,
      );
    } catch (e) {
      state = state.copyWith(
        quoting: false,
        error: e.toString(),
        clearQuote: true,
      );
    }
  }

  Future<void> retryQuote() => _refreshQuote();

  /// Creates the booking and returns its ride id for the search screen.
  Future<String> confirm() async {
    final pickup = state.pickup!;
    final drop = state.drop!;
    final quote = state.quote!;

    final delivery = await ref
        .read(deliveryRepositoryProvider)
        .createDelivery(
          pickup: [pickup.lng, pickup.lat],
          drop: [drop.lng, drop.lat],
          pickupAddress: pickup.address,
          dropAddress: drop.address,
          fare: quote.total,
          vehicleTypeId: state.vehicleTypeId,
          parcel: ParcelModel(
            category: state.category,
            weight: state.weight,
            photos: state.photos,
            instructions: state.instructions,
            // What the rider typed — reaches the driver on the offer card.
            description: state.goodsType,
            senderName: state.senderName,
            senderMobile: state.senderMobile,
            receiverName: state.receiverName,
            receiverMobile: state.receiverMobile,
          ),
        );

    // A delivery is a ride with `serviceType: parcel`, so tracking and the
    // dispatch search both key off the ride id.
    return delivery.ride.rideId;
  }

  void reset() => state = const DeliveryBookingState();
}

final deliveryBookingProvider =
    StateNotifierProvider<DeliveryBookingController, DeliveryBookingState>((
      ref,
    ) {
      return DeliveryBookingController(ref);
    });

/// Parcel materials the admin has listed, for the details screen.
///
/// Kept as a provider so the catalog is fetched once and shared, and so a
/// failure surfaces as an async error the screen can fall back from rather than
/// an exception mid-build.
final goodsTypesProvider = FutureProvider<List<GoodsTypeModel>>((ref) async {
  return ref.read(deliveryRepositoryProvider).listGoodsTypes();
});

/// Only the vehicle types the admin marked as delivery vehicles, further
/// narrowed to whichever app module the rider entered through — a vehicle
/// the admin scoped to another module (or left unscoped, which offers it
/// everywhere) is the only thing that reaches the category/picker screens.
final deliveryVehicleTypesProvider = FutureProvider((ref) async {
  final all = await ref.watch(allVehicleTypesProvider.future);
  final moduleId = ref.watch(deliveryBookingProvider.select((s) => s.moduleId));
  return all
      .where((v) => v.transportType.toLowerCase() == 'delivery')
      .where((v) => v.isOfferedUnderModule(moduleId))
      .toList();
});

/// Delivery vehicles filed under one category card.
///
/// A vehicle whose `delivery_category` the admin never set comes back empty and
/// would belong to no card at all, so it is deliberately excluded rather than
/// shown under an arbitrary one.
final deliveryVehiclesByCategoryProvider = FutureProvider.family((
  ref,
  String categoryId,
) async {
  final vehicles = await ref.watch(deliveryVehicleTypesProvider.future);
  return vehicles
      .where(
        (v) => v.deliveryCategory.toLowerCase() == categoryId.toLowerCase(),
      )
      // A vehicle with no parcel rates configured can only ever quote Rs 0, so
      // it is not offered at all rather than letting the sender pick it and
      // then be shown a free delivery.
      .where((v) => v.hasDeliveryPricing)
      .toList();
});

/// The candidate vehicles the picker screen offers for the currently chosen
/// delivery category, falling back to every priced delivery vehicle when that
/// category has none — the same fallback the address screen used to pick one
/// vehicle for automatically now applies to the whole list instead.
final deliveryVehicleCandidatesProvider =
    FutureProvider.autoDispose<List<VehicleTypeModel>>((ref) async {
      final categoryId = ref.watch(
        deliveryBookingProvider.select((s) => s.deliveryCategoryId),
      );
      final byCategory = categoryId.isEmpty
          ? const <VehicleTypeModel>[]
          : await ref.watch(
              deliveryVehiclesByCategoryProvider(categoryId).future,
            );

      if (byCategory.isNotEmpty) return byCategory;
      return ref.watch(deliveryVehicleTypesProvider.future);
    });

/// One vehicle candidate paired with its live server quote.
class DeliveryVehicleOption {
  final VehicleTypeModel vehicle;
  final DeliveryQuote quote;
  const DeliveryVehicleOption({required this.vehicle, required this.quote});
}

/// A priced list of every vehicle the rider can pick, for the "choose a
/// vehicle" screen shown after parcel details — the delivery equivalent of
/// the ride flow's vehicle-selection sheet.
///
/// Quoted in parallel, one request per candidate: delivery fares are priced
/// server-side only (there is no local `FareCalculator` for parcel distance
/// pricing the way there is for rides), so showing a fare per tile means
/// asking the server for each one. A vehicle that fails to price — no rate
/// configured, or the goods category is not allowed on it — is left off the
/// list rather than shown with a broken or zero fare.
final deliveryVehicleQuotesProvider =
    FutureProvider.autoDispose<List<DeliveryVehicleOption>>((ref) async {
      final booking = ref.watch(deliveryBookingProvider);
      final pickup = booking.pickup;
      final drop = booking.drop;
      if (pickup == null || drop == null) return const [];

      final candidates = await ref.watch(
        deliveryVehicleCandidatesProvider.future,
      );
      if (candidates.isEmpty) return const [];

      final repository = ref.watch(deliveryRepositoryProvider);
      final results = await Future.wait(
        candidates.map((vehicle) async {
          try {
            final quote = await repository.getQuote(
              vehicleTypeId: vehicle.id,
              pickup: [pickup.lng, pickup.lat],
              drop: [drop.lng, drop.lat],
              category: booking.category,
            );
            if (quote.total <= 0) return null;
            return DeliveryVehicleOption(vehicle: vehicle, quote: quote);
          } catch (_) {
            return null;
          }
        }),
      );

      final options = results.whereType<DeliveryVehicleOption>().toList()
        ..sort((a, b) => a.quote.total.compareTo(b.quote.total));
      return options;
    });

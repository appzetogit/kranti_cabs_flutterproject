import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/services/location_service.dart';
import '../../../core/utils/marker_icon_loader.dart';
import '../../../core/utils/route_geometry.dart';
import '../../../core/utils/vehicle_marker_icons.dart';
import '../../ride/application/ride_providers.dart';
import '../data/home_repository.dart';
import 'booking_controller.dart';
import '../data/models/app_module_model.dart';
import '../data/models/set_price_model.dart';
import '../data/models/vehicle_type_model.dart';

final homeRepositoryProvider = Provider<HomeRepository>((ref) {
  return HomeRepository(
    ref.watch(apiClientProvider),
    ref.watch(responseCacheProvider),
  );
});

final appModulesProvider = FutureProvider<List<AppModuleModel>>((ref) {
  return ref.watch(homeRepositoryProvider).getAppModules();
});

/// The whole catalog, fetched once and shared by every booking flow.
final allVehicleTypesProvider = FutureProvider<List<VehicleTypeModel>>((ref) {
  return ref.watch(homeRepositoryProvider).getVehicleTypes();
});

/// Ride booking — taxi tiers only.
final vehicleTypesProvider = FutureProvider<List<VehicleTypeModel>>((ref) async {
  final all = await ref.watch(allVehicleTypesProvider.future);
  return all.where((v) => v.transportType.toLowerCase() == 'taxi').toList();
});

/// Where banners are targeted: the GPS fix, else the pickup the rider last
/// set, rounded to two decimals (~1 km) so banners are only refetched when the
/// rider moves about a kilometre, not on every GPS update.
final bannerLocationProvider = Provider<({double lat, double lng})?>((ref) {
  final pos = ref.watch(currentPositionProvider).valueOrNull;
  final pickup = ref.watch(bookingControllerProvider.select((b) => b.pickup));
  final lat = pos?.latitude ?? pickup?.lat;
  final lng = pos?.longitude ?? pickup?.lng;
  if (lat == null || lng == null) return null;
  return (lat: double.parse(lat.toStringAsFixed(2)), lng: double.parse(lng.toStringAsFixed(2)));
});

/// Zone-targeted promo banners. Not caught here: on a failed refresh Riverpod
/// keeps the previous banners, and with none the home screen reads it as empty.
final bannersProvider = FutureProvider<List<Map<String, dynamic>>>((ref) {
  final loc = ref.watch(bannerLocationProvider);
  return ref.watch(homeRepositoryProvider).getBanners(lat: loc?.lat, lng: loc?.lng);
});

/// The admin-configured transparent images for the top of the home screen.
/// Empty list when none is set or the fetch fails.
final homeTopBannersProvider = FutureProvider<List<String>>((ref) async {
  try {
    return await ref.watch(homeRepositoryProvider).getHomeTopBanners();
  } catch (_) {
    return const [];
  }
});

final setPricesProvider = FutureProvider<List<SetPriceModel>>((ref) {
  return ref.watch(homeRepositoryProvider).getSetPrices();
});

/// Tariffs for the zone a given pickup falls in.
///
/// Prefer this over [setPricesProvider] anywhere a pickup is known: the
/// unscoped provider returns every city's rows at once and cannot say which
/// of them will actually be billed.
/// autoDispose because the key is a coordinate: every distinct pickup would
/// otherwise leave a provider alive for the life of the app.
final setPricesAtProvider =
    FutureProvider.autoDispose.family<List<SetPriceModel>, ({double lat, double lng})>((ref, at) {
  return ref.watch(homeRepositoryProvider).getSetPrices(lat: at.lat, lng: at.lng);
});

final bootstrapProvider = FutureProvider<Map<String, dynamic>>((ref) {
  return ref.watch(homeRepositoryProvider).getBootstrap();
});

/// The rider's position, or null when location is off or not allowed.
///
/// Resolved once and kept, so it has to be refreshed when the answer can have
/// changed - [LocationRefresher] does that when the app returns to the
/// foreground. Before that existed, a rider who denied location at first
/// launch and allowed it later in Settings stayed on "Fetching location..."
/// until the app was killed, because this went on returning the null it had
/// cached.
final currentPositionProvider = FutureProvider<Position?>((ref) async {
  final service = ref.watch(locationServiceProvider);
  final permission = await service.ensurePermission();
  if (!permission.granted) return null;
  try {
    return await service.getCurrentPosition();
  } catch (_) {
    // Timed out or failed - a slightly old fix is far more useful than none.
    return await Geolocator.getLastKnownPosition();
  }
});

/// Whether location is usable, read without prompting the rider.
///
/// Drives the "Turn on location" prompts. Refreshed alongside
/// [currentPositionProvider] whenever the app comes back to the foreground.
final locationStatusProvider = FutureProvider<LocationPermissionResult>((ref) {
  return ref.watch(locationServiceProvider).checkStatus();
});

/// One online driver near the rider, reduced to what the map needs.
class NearbyDriver {
  final String id;
  final double lat;
  final double lng;

  /// 'bike' | 'auto' | 'car' — the fallback key when this driver's exact
  /// vehicle type has no art of its own.
  final String iconFamily;

  /// Catalog id of the driver's vehicle type, used to look up that type's
  /// specific marker before falling back to [iconFamily].
  final String vehicleTypeId;

  const NearbyDriver({
    required this.id,
    required this.lat,
    required this.lng,
    required this.iconFamily,
    this.vehicleTypeId = '',
  });

  static NearbyDriver? fromJson(Map<String, dynamic> json) {
    final coordinates = (json['location'] as Map?)?['coordinates'] as List?;
    if (coordinates == null || coordinates.length < 2) return null;

    final lng = double.tryParse(coordinates[0].toString());
    final lat = double.tryParse(coordinates[1].toString());
    if (lat == null || lng == null) return null;

    return NearbyDriver(
      id: (json['id'] ?? '').toString(),
      lat: lat,
      lng: lng,
      iconFamily: VehicleMarkerIcons.familyFor(
        iconType: json['vehicleIconType']?.toString(),
        vehicleType: json['vehicleType']?.toString(),
      ),
      vehicleTypeId: (json['vehicleTypeId'] ?? '').toString(),
    );
  }
}

const _nearbyDriversRefreshInterval = Duration(seconds: 20);

/// Nearby-driver markers stay scoped to this radius — a screen full of
/// vehicles from across the city isn't what "who's around me" means.
const _nearbyDriversRadiusMeters = 2000.0;

/// Polls for online drivers around the rider so the home map can show live
/// vehicles. Interval stays well inside the endpoint's 60-req/min IP limit,
/// and `autoDispose` stops the polling as soon as the map is torn down.
final nearbyDriversProvider = StreamProvider.autoDispose<List<NearbyDriver>>((ref) async* {
  final position = await ref.watch(currentPositionProvider.future);
  if (position == null) {
    yield const [];
    return;
  }

  final repository = ref.watch(rideRepositoryProvider);

  // Null when the poll failed, so the caller can tell "no drivers" apart
  // from "couldn't ask".
  Future<List<NearbyDriver>?> fetch() async {
    try {
      final raw = await repository.getAvailableDrivers(
        lat: position.latitude,
        lng: position.longitude,
        maxDistance: _nearbyDriversRadiusMeters,
      );
      return raw.map(NearbyDriver.fromJson).whereType<NearbyDriver>().toList();
    } catch (_) {
      return null;
    }
  }

  // Only the very first poll has nothing to fall back on.
  yield await fetch() ?? const [];

  await for (final _ in Stream<void>.periodic(_nearbyDriversRefreshInterval)) {
    // A failed poll emits nothing, leaving the last known markers on screen.
    // Yielding an empty list here used to blank the map on every blip.
    final drivers = await fetch();
    if (drivers != null) yield drivers;
  }
});

/// One nearby driver's marker, mid-glide between its last two known fixes.
class AnimatedNearbyDriver {
  final String id;
  final LatLng from;
  final LatLng to;
  final LatLng current;
  final double heading;
  final String iconFamily;
  final String vehicleTypeId;
  final DateTime segmentStart;

  const AnimatedNearbyDriver({
    required this.id,
    required this.from,
    required this.to,
    required this.current,
    required this.heading,
    required this.iconFamily,
    required this.vehicleTypeId,
    required this.segmentStart,
  });
}

/// Turns the 20-second driver-position polls into continuous motion.
///
/// The ambient nearby-drivers endpoint only offers a fix every 20 seconds —
/// there's no socket feed for drivers the rider hasn't matched with yet — so
/// each new fix becomes the end of a glide segment starting from wherever the
/// marker currently sits, walked linearly over the full interval by a ticker.
/// That keeps vehicles gliding continuously across the map like a real drive,
/// rather than snapping to a new spot once every 20 seconds.
class NearbyDriverAnimationNotifier extends StateNotifier<Map<String, AnimatedNearbyDriver>> {
  NearbyDriverAnimationNotifier(Ref ref) : super(const {}) {
    _subscription = ref.listen<AsyncValue<List<NearbyDriver>>>(
      nearbyDriversProvider,
      (previous, next) {
        // An error still carries the previous list; re-targeting onto it would
        // only restart every glide from where it stands.
        if (next.hasError) return;
        final drivers = next.valueOrNull;
        if (drivers != null) _retarget(drivers);
      },
      fireImmediately: true,
    );
  }

  late final ProviderSubscription<AsyncValue<List<NearbyDriver>>> _subscription;
  Timer? _ticker;

  /// The ticker only runs while some marker is still mid-glide. Left running,
  /// it replaced the state every 200 ms forever and rebuilt every listening
  /// map even when nothing had moved.
  void _ensureTicking() {
    if (_ticker?.isActive ?? false) return;
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) => _tick());
  }

  void _stopTicking() {
    _ticker?.cancel();
    _ticker = null;
  }

  void _retarget(List<NearbyDriver> drivers) {
    final now = DateTime.now();
    final next = <String, AnimatedNearbyDriver>{};
    for (final driver in drivers) {
      final target = LatLng(driver.lat, driver.lng);
      final existing = state[driver.id];
      final from = existing?.current ?? target;
      final moved = existing != null && haversineMeters(from, target) > 2;
      next[driver.id] = AnimatedNearbyDriver(
        id: driver.id,
        from: from,
        to: target,
        current: from,
        heading: moved ? bearingBetween(from, target) : (existing?.heading ?? 0),
        iconFamily: driver.iconFamily,
        vehicleTypeId: driver.vehicleTypeId,
        segmentStart: now,
      );
    }
    state = next;
    if (next.isEmpty) {
      _stopTicking();
    } else {
      _ensureTicking();
    }
  }

  void _tick() {
    if (state.isEmpty) {
      _stopTicking();
      return;
    }
    final now = DateTime.now();
    var allArrived = true;
    state = state.map((id, driver) {
      final elapsedMs = now.difference(driver.segmentStart).inMilliseconds;
      final t = (elapsedMs / _nearbyDriversRefreshInterval.inMilliseconds).clamp(0.0, 1.0);
      if (t < 1) allArrived = false;
      final current = LatLng(
        driver.from.latitude + (driver.to.latitude - driver.from.latitude) * t,
        driver.from.longitude + (driver.to.longitude - driver.from.longitude) * t,
      );
      return MapEntry(
        id,
        AnimatedNearbyDriver(
          id: driver.id,
          from: driver.from,
          to: driver.to,
          current: current,
          heading: driver.heading,
          iconFamily: driver.iconFamily,
          vehicleTypeId: driver.vehicleTypeId,
          segmentStart: driver.segmentStart,
        ),
      );
    });
    // This tick has placed every marker at its target; nothing moves again
    // until the next poll retargets and restarts the ticker.
    if (allArrived) _stopTicking();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _subscription.close();
    super.dispose();
  }
}

final nearbyDriverAnimationProvider = StateNotifierProvider.autoDispose<
    NearbyDriverAnimationNotifier, Map<String, AnimatedNearbyDriver>>(
  (ref) => NearbyDriverAnimationNotifier(ref),
);

/// Marker bitmaps served by the backend, decoded once and reused for every
/// driver.
///
/// Keyed twice for each vehicle type: by its catalog id (exact art for the
/// vehicle actually assigned) and by its `icon_types` family (`bike`/`auto`/
/// `car`), which is all the nearby-driver feed carries for some drivers.
/// Admins can change the art without shipping an app build.
///
/// The bundled assets remain only as a last resort — one live vehicle type has
/// no `map_icon` at all, and a blank map is worse than a generic pin.
/// Marker bitmaps for every vehicle, best available first.
///
/// Emits twice on purpose. The bundled silhouettes decode from the asset
/// bundle in milliseconds, so they go out immediately and the map draws a car
/// on the first frame; the admin-uploaded art replaces them when it arrives.
///
/// It used to be a FutureProvider that downloaded every icon before returning
/// anything - and one `await` per row, so a dozen images downloaded one after
/// another, each its own round trip. Until the last one landed there were no
/// icons at all and every vehicle sat on the map as a generic pin. That was
/// the slow marker.
///
/// Keyed twice for each vehicle: by catalog id (exact art for the vehicle
/// actually assigned) and by `icon_types` family (`bike`/`auto`/`car`), which
/// is all the nearby-driver feed carries for some drivers.
final vehicleMarkerIconsProvider =
    StreamProvider<Map<String, BitmapDescriptor>>((ref) async* {
  // Resolved before the first await: reading a provider across an async gap
  // is not safe once this one can be disposed mid-flight.
  final repository = ref.watch(homeRepositoryProvider);
  final icons = <String, BitmapDescriptor>{};

  // Local art first so the map is never iconless.
  try {
    icons.addAll(await VehicleMarkerIcons.loadAll());
    if (icons.isNotEmpty) yield Map.of(icons);
  } catch (_) {
    // A missing bundled asset must not stop the server art below.
  }

  try {
    final rows = await repository.getVehicleMapIcons();

    // Fetched together rather than one after another.
    final descriptors = await Future.wait(
      rows.map((row) => MarkerIconLoader.fromSource(row['map_icon']?.toString())),
    );

    // First server row of a family wins, and it replaces the bundled
    // silhouette - `putIfAbsent` would have kept the bundled one forever now
    // that it is already in the map.
    final familiesFromServer = <String>{};
    var changed = false;

    for (var i = 0; i < rows.length; i++) {
      final descriptor = descriptors[i];
      if (descriptor == null) continue;

      final id = (rows[i]['id'] ?? '').toString();
      if (id.isNotEmpty) {
        icons[id] = descriptor;
        changed = true;
      }

      final family = VehicleMarkerIcons.familyFor(
        iconType: rows[i]['icon_types']?.toString(),
      );
      if (familiesFromServer.add(family)) {
        icons[family] = descriptor;
        changed = true;
      }
    }

    if (changed) yield Map.of(icons);
  } catch (_) {
    // Offline or endpoint failure - the bundled art already emitted stands.
  }
});

/// The rider's current address, or '' when there is no position to name.
///
/// This used to return the words 'Fetching location...' when location was
/// off, and callers used whatever it returned as the pickup address - so a
/// booking could carry "Fetching location..." as its pickup, placed at a
/// hardcoded fallback point in another city. Empty means "no location";
/// callers decide what to show.
final currentAddressProvider = FutureProvider<String>((ref) async {
  final pos = await ref.watch(currentPositionProvider.future);
  // Empty, not a placeholder sentence: callers treat "no address" as "no
  // location" and must not mistake text like "Fetching location..." for a real
  // pickup.
  if (pos == null) return '';
  final service = ref.watch(locationServiceProvider);
  final addr = await service.getAddressFromCoordinates(pos.latitude, pos.longitude);
  return addr.isNotEmpty ? addr : 'Current Location';
});


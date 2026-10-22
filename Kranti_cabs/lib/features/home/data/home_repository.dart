import '../../../core/constants/app_constants.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/response_cache.dart';
import '../../../core/utils/json_safe.dart';
import 'models/app_module_model.dart';
import 'models/set_price_model.dart';
import 'models/surge_info.dart';
import 'models/trip_category.dart';
import 'models/vehicle_type_model.dart';

class HomeRepository {
  final ApiClient api;

  /// Catalog reads go through here: fresh entries skip the network entirely,
  /// and a failed refresh falls back to the last good copy instead of emptying
  /// the screen.
  final ResponseCache cache;

  HomeRepository(this.api, this.cache);

  Future<Map<String, dynamic>> getBootstrap() async {
    final data = await cache.fetch(
      key: CacheKeys.bootstrap,
      ttl: CacheKeys.catalogTtl,
      loader: () => api.get(ApiConstants.bootstrap),
    );
    return asMap(data);
  }

  Future<List<AppModuleModel>> getAppModules() async {
    final data = await cache.fetch(
      key: CacheKeys.appModules,
      ttl: CacheKeys.catalogTtl,
      loader: () => api.get(ApiConstants.appModules, query: {'per_page': 50}),
    );
    final modules = asResults(
      data,
    ).map(AppModuleModel.fromJson).where((m) => m.active).toList();
    modules.sort((a, b) => a.orderBy.compareTo(b.orderBy));
    return modules;
  }

  /// The full vehicle catalog, every transport type.
  ///
  /// This used to filter to `taxi` here, which meant delivery vehicles never
  /// reached the app at all and the parcel flow always looked empty. Filtering
  /// now happens per-caller so ride and delivery can share one fetch.
  Future<List<VehicleTypeModel>> getVehicleTypes() async {
    final data = await cache.fetch(
      key: CacheKeys.vehicleTypes,
      ttl: CacheKeys.catalogTtl,
      loader: () => api.get(ApiConstants.vehicleTypes),
    );
    return asResults(data).map(VehicleTypeModel.fromJson).toList();
  }

  /// Tariffs for the zone the trip starts in.
  ///
  /// The pickup point decides the price: the same vehicle costs different
  /// amounts per city, and given coordinates the backend returns exactly one
  /// tariff per vehicle for the zone they fall in. Called without them it
  /// returns every zone's rows and the caller cannot tell which apply - which
  /// is how a Bangalore rider came to be quoted Indore's rate.
  Future<List<SetPriceModel>> getSetPrices({double? lat, double? lng}) async {
    final data = await _fetchSetPrices(lat: lat, lng: lng);
    return asResults(data).map(SetPriceModel.fromJson).toList();
  }

  /// The surge applied to the prices at this pickup. Read from the same cached
  /// response as [getSetPrices], so it costs no extra request and always
  /// describes the prices on screen.
  Future<SurgeInfo> getSurge({required double lat, required double lng}) async {
    final data = await _fetchSetPrices(lat: lat, lng: lng);
    return data is Map ? SurgeInfo.fromJson(data['surge']) : SurgeInfo.none;
  }

  /// City, airport or outstation for this pickup and drop. Not cached: an
  /// admin redrawing an airport or zone should take effect on the next search.
  Future<TripCategory> getTripCategory({
    required double pickupLat,
    required double pickupLng,
    required double dropLat,
    required double dropLng,
  }) async {
    final data = await api.get(ApiConstants.tripCategory, query: {
      'pickup': '$pickupLat,$pickupLng',
      'drop': '$dropLat,$dropLng',
    });
    return TripCategory.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<dynamic> _fetchSetPrices({double? lat, double? lng}) {
    final hasPickup = lat != null && lng != null;
    return cache.fetch(
      // Keyed by pickup, or one city's prices get served to the next. Rounded
      // to roughly a kilometre so panning the map does not defeat the cache.
      key: hasPickup
          ? '${CacheKeys.setPrices}:${lat.toStringAsFixed(2)},${lng.toStringAsFixed(2)}'
          : CacheKeys.setPrices,
      ttl: CacheKeys.setPricesTtl,
      loader: () => api.get(ApiConstants.setPrices, query: {
        'scope': 'ride',
        if (hasPickup) 'lat': lat,
        if (hasPickup) 'lng': lng,
      }),
    );
  }

  /// Active promo banners for the home strip, aimed at the rider's zone.
  ///
  /// `/users/banners` returns the banners for this app whose zones contain
  /// ([lat], [lng]), zone-targeted first, then the all-zone ones. With no
  /// location only the all-zone banners come back. Coordinates are sent at two
  /// decimals (~1 km), which is also the cache key, so moving a few metres
  /// never refetches. Normalised to `{image, redirect_url, title}`.
  Future<List<Map<String, dynamic>>> getBanners({double? lat, double? lng}) async {
    final hasLoc = lat != null && lng != null;
    final latStr = hasLoc ? lat.toStringAsFixed(2) : '';
    final lngStr = hasLoc ? lng.toStringAsFixed(2) : '';
    final data = await cache.fetch(
      key: '${CacheKeys.banners}:zone:$latStr,$lngStr',
      ttl: CacheKeys.bannersTtl,
      loader: () => api.get(ApiConstants.banners, query: {
        if (hasLoc) 'lat': latStr,
        if (hasLoc) 'lng': lngStr,
      }),
    );
    return (asMap(data)['results'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((b) => b['active'] != false)
        .map((b) {
      final image = (b['image'] ?? '').toString();
      return {
        'image': image.startsWith('http')
            ? image
            : '${AppConstants.mediaBaseUrl}/${image.replaceFirst(RegExp(r'^/+'), '')}',
        'redirect_url': (b['redirect_url'] ?? '').toString(),
        'title': (b['title'] ?? '').toString(),
      };
    }).toList();
  }

  /// The transparent decorative images an admin sets for the very top of the
  /// home screen (festival garland, lights, etc.), read from the same
  /// `user-home-management` document as the promo banners. Returns every
  /// configured top banner in order; empty when none is set. Falls back to the
  /// old single `topImage` field for settings saved before multiple were
  /// supported.
  Future<List<String>> getHomeTopBanners() async {
    final data = await cache.fetch(
      key: CacheKeys.banners,
      ttl: CacheKeys.bannersTtl,
      loader: () => api.get('/user-home-management'),
    );
    final map = asMap(data);

    final list = (map['topBanners'] ?? map['top_banners']);
    if (list is List) {
      final urls = list
          .map((e) {
            if (e is String) return e.trim();
            if (e is Map) {
              return (e['image'] ?? e['imageUrl'] ?? e['url'] ?? '')
                  .toString()
                  .trim();
            }
            return '';
          })
          .where((u) => u.isNotEmpty)
          .toList();
      if (urls.isNotEmpty) return urls;
    }

    // Backward compatibility: a single stored image.
    final single = (map['topImage'] ?? map['top_image'] ?? '').toString().trim();
    return single.isEmpty ? const [] : [single];
  }

  /// Marker art per vehicle type, as `{ vehicleTypeId, icon_types, map_icon }`.
  Future<List<Map<String, dynamic>>> getVehicleMapIcons() async {
    final data = await cache.fetch(
      key: CacheKeys.vehicleMapIcons,
      ttl: CacheKeys.catalogTtl,
      loader: () => api.get(ApiConstants.vehicleMapIcons),
    );
    return asResults(data);
  }

  /// Returns the ETA (in minutes) of the closest available driver for a given
  /// vehicle type near [lat]/[lng], or null if none are currently available.
  Future<int?> getClosestDriverEtaMinutes({
    required double lat,
    required double lng,
    required String vehicleTypeId,
  }) async {
    final data = await api.get(
      ApiConstants.availableDrivers,
      query: {'lat': lat, 'lng': lng, 'vehicleTypeId': vehicleTypeId},
    );
    final map = Map<String, dynamic>.from(data ?? {});
    final eta = map['closestDriverEtaMinutes'];
    if (eta == null) return null;
    return int.tryParse('$eta') ?? double.tryParse('$eta')?.round();
  }
}

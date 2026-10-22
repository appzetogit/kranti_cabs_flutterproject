import 'dart:convert';
import 'dart:developer' as developer;

import 'package:hive/hive.dart';

/// Short-lived cache for catalog responses.
///
/// The vehicle catalog, app modules, set prices and banners barely change
/// between app launches, yet every visit to Home refetched all of them — a
/// visibly slow first paint and needless data on a phone in a moving car.
///
/// Two behaviours, both deliberate:
///   * a fresh entry is served without touching the network at all
///   * when the network fails, a *stale* entry is served rather than an error,
///     so a dropped connection degrades the catalog's freshness instead of
///     emptying the screen
///
/// Only public catalog data is cached. Nothing user-specific goes in here.
class ResponseCache {
  final Box _box;

  ResponseCache(this._box);

  static const String _valueKey = 'v';
  static const String _storedAtKey = 't';

  /// Serves [key] from cache while it is younger than [ttl], otherwise calls
  /// [loader] and stores the result.
  Future<dynamic> fetch({
    required String key,
    required Duration ttl,
    required Future<dynamic> Function() loader,
  }) async {
    final cached = _read(key);
    if (cached != null && cached.age < ttl) return cached.value;

    try {
      final fresh = await loader();
      _write(key, fresh);
      return fresh;
    } catch (error) {
      // Stale beats empty: the catalog the driver saw a minute ago is far more
      // useful than a blank list because one request timed out.
      if (cached != null) {
        developer.log('[cache] $key served stale after error: $error', name: 'ResponseCache');
        return cached.value;
      }
      rethrow;
    }
  }

  /// Drops one entry, for when the app knows the server value just changed.
  Future<void> invalidate(String key) async {
    try {
      await _box.delete(key);
    } catch (_) {}
  }

  ({dynamic value, Duration age})? _read(String key) {
    try {
      final raw = _box.get(key);
      if (raw is! String || raw.isEmpty) return null;

      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;

      final storedAt = DateTime.tryParse('${decoded[_storedAtKey]}');
      if (storedAt == null) return null;

      return (value: decoded[_valueKey], age: DateTime.now().difference(storedAt));
    } catch (error) {
      developer.log('[cache] $key unreadable: $error', name: 'ResponseCache');
      return null;
    }
  }

  void _write(String key, dynamic value) {
    try {
      _box.put(key, jsonEncode({
        _valueKey: value,
        _storedAtKey: DateTime.now().toIso8601String(),
      }));
    } catch (error) {
      // A value that will not encode is simply not cached; the caller already
      // has its fresh copy.
      developer.log('[cache] $key not cacheable: $error', name: 'ResponseCache');
    }
  }
}

/// Cache keys and how long each stays fresh.
///
/// One place on purpose — a TTL buried at a call site is a TTL nobody finds.
class CacheKeys {
  CacheKeys._();

  static const String vehicleTypes = 'catalog:vehicle-types';
  static const String appModules = 'catalog:app-modules';
  static const String setPrices = 'catalog:set-prices';
  static const String banners = 'catalog:banners';
  static const String vehicleMapIcons = 'catalog:vehicle-map-icons';
  static const String bootstrap = 'catalog:bootstrap';

  /// The vehicle list and map icons change rarely and are read constantly.
  static const Duration catalogTtl = Duration(minutes: 10);

  /// Prices are kept far more briefly than the rest of the catalog.
  ///
  /// They were on the 10-minute catalog TTL, and the cache lives on disk, so a
  /// fare an admin corrected kept being quoted for up to ten minutes - closing
  /// and reopening the app did not help. Riders kept seeing a per-minute charge
  /// for ten minutes after it was removed, and the fix looked like it had not
  /// worked. A minute is still enough to stop every map pan or screen change
  /// from refetching.
  static const Duration setPricesTtl = Duration(minutes: 1);

  /// Banners are merchandising — worth picking up sooner.
  static const Duration bannersTtl = Duration(minutes: 5);
}

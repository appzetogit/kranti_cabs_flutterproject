import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../constants/api_constants.dart';
import '../utils/marker_icon_loader.dart';
import '../utils/vehicle_marker_helper.dart';
import 'core_providers.dart';

/// Vehicle marker art served by the backend, decoded once per session.
///
/// Keyed twice per vehicle type: by catalog id (the exact art for the vehicle
/// this driver actually drives) and by `icon_types` family (`bike`/`auto`/
/// `car`). Admins can change the art without shipping an app build.
///
/// No bundled fallback art on purpose: a vehicle type with no `map_icon`
/// leaves callers with no entry for it, which is what tells them to fall
/// back to the map SDK's own default pin rather than a stand-in vehicle
/// photo that isn't the one this driver actually drives.
final vehicleMapIconsProvider = FutureProvider<Map<String, BitmapDescriptor>>((
  ref,
) async {
  final icons = <String, BitmapDescriptor>{};

  try {
    final data = await ref
        .watch(apiClientProvider)
        .get(ApiConstants.vehicleMapIcons);
    final map = data is Map
        ? Map<String, dynamic>.from(data)
        : const <String, dynamic>{};
    final rows = map['results'] as List? ?? const [];

    for (final raw in rows) {
      final row = Map<String, dynamic>.from(raw as Map);
      final descriptor = await MarkerIconLoader.fromSource(
        row['map_icon']?.toString(),
      );
      if (descriptor == null) continue;

      final id = (row['id'] ?? '').toString();
      if (id.isNotEmpty) icons[id] = descriptor;

      final family = VehicleMarkerHelper.familyFor(
        row['icon_types']?.toString(),
      );
      icons.putIfAbsent(family, () => descriptor);
    }
  } catch (_) {
    // Offline or endpoint failure — an empty map here is what makes callers
    // fall back to the map SDK's own default pin.
  }

  return icons;
});

/// Resolves the marker for one vehicle: its own catalog art first, then the
/// family silhouette — both served by the backend. Null when neither is
/// available (offline, endpoint failure, or a vehicle type with no art
/// uploaded), so the marker is drawn with the map SDK's own default pin
/// rather than a bundled stand-in vehicle photo that isn't this driver's.
Future<BitmapDescriptor?> resolveVehicleMarker(
  WidgetRef ref, {
  String? vehicleTypeId,
  String? vehicleType,
  String? serviceType,
}) async {
  Map<String, BitmapDescriptor> icons = const {};
  try {
    icons = await ref.read(vehicleMapIconsProvider.future);
  } catch (_) {
    // No backend art available — the caller's own default pin takes over.
  }

  final byId = vehicleTypeId != null && vehicleTypeId.isNotEmpty
      ? icons[vehicleTypeId]
      : null;
  if (byId != null) return byId;

  return icons[VehicleMarkerHelper.familyFor(vehicleType, serviceType)];
}

import 'dart:ui' show Offset;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../application/booking_controller.dart';
import '../application/home_providers.dart';

/// Live vehicles around the rider, each drawn with its own vehicle-type art
/// and gliding continuously between its last two known fixes (see
/// [NearbyDriverAnimationNotifier]) rather than snapping every 20 seconds.
///
/// Shared by the home map and the finding-driver map so both show the same
/// fleet — the rider should not watch vehicles vanish the moment they start
/// searching for one.
///
/// Renders nothing until both the drivers and the bitmaps have resolved, so a
/// slow icon decode never leaves default red pins on the map.
///
/// [onlyVehicleTypeIds], when given, limits the map to those vehicle types -
/// see [moduleVehicleTypeIds]. A driver whose type the server did not send
/// is still drawn.
Set<Marker> buildNearbyDriverMarkers(WidgetRef ref, {Set<String>? onlyVehicleTypeIds}) {
  final drivers = ref.watch(nearbyDriverAnimationProvider).values;
  final icons = ref.watch(vehicleMarkerIconsProvider).valueOrNull;
  if (drivers.isEmpty || icons == null) return const {};

  return drivers
      .where((driver) =>
          onlyVehicleTypeIds == null ||
          driver.vehicleTypeId.isEmpty ||
          onlyVehicleTypeIds.contains(driver.vehicleTypeId))
      .map((driver) {
        // Exact art for this driver's vehicle type when the backend has it,
        // otherwise the family silhouette.
        final icon = icons[driver.vehicleTypeId] ?? icons[driver.iconFamily];
        if (icon == null) return null;
        return Marker(
          markerId: MarkerId('nearby_driver_${driver.id}'),
          position: driver.current,
          rotation: driver.heading,
          icon: icon,
          anchor: const Offset(0.5, 0.5),
          flat: true,
          zIndexInt: 1,
        );
      })
      .whereType<Marker>()
      .toSet();
}

/// The vehicle types the module the rider is booking under offers (Zi Airport,
/// Zi City Ride ...), or null outside a module. The vehicle list was already
/// scoped this way; the map was not, so an airport booking showed autos
/// driving around that the rider could not book.
Set<String>? moduleVehicleTypeIds(WidgetRef ref) {
  final moduleId = ref.watch(bookingControllerProvider.select((b) => b.moduleId));
  if (moduleId == null || moduleId.isEmpty) return null;
  final vehicles = ref.watch(bookingControllerProvider.select((b) => b.vehicleTypes));
  // The catalog not loaded yet: show nobody rather than everybody.
  return vehicles
      .where((v) => v.isOfferedUnderModule(moduleId))
      .map((v) => v.id)
      .toSet();
}

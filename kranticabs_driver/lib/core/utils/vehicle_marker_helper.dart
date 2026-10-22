import 'dart:ui' show Offset;
import 'package:google_maps_flutter/google_maps_flutter.dart';

class VehicleMarkerHelper {
  VehicleMarkerHelper._();

  static const _defaultFamily = 'car';

  static String familyFor(String? vehicleType, [String? serviceType]) {
    final raw = '${vehicleType ?? ''} ${serviceType ?? ''}'
        .trim()
        .toLowerCase();

    if (raw.contains('bike') ||
        raw.contains('2wheeler') ||
        raw.contains('moto') ||
        raw.contains('scooter') ||
        raw.contains('two_wheeler') ||
        raw.contains('parcel')) {
      return 'bike';
    }
    if (raw.contains('auto') ||
        raw.contains('rickshaw') ||
        raw.contains('tuk') ||
        raw.contains('3wheeler')) {
      return 'auto';
    }
    return _defaultFamily;
  }

  static Marker buildVehicleMarker({
    required LatLng position,
    required double heading,
    BitmapDescriptor? customIcon,
  }) {
    return Marker(
      markerId: const MarkerId('driver_vehicle'),
      position: position,
      icon:
          customIcon ??
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      rotation: heading,
      anchor: const Offset(0.5, 0.5),
      flat: true,
      zIndexInt: 100,
    );
  }
}

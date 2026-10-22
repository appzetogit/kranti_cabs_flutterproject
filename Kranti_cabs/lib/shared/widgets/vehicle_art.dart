import 'package:flutter/material.dart';

import '../../core/utils/image_utils.dart';

/// Vehicle artwork, from the catalog wherever possible.
///
/// Degrades in three steps so it can never fail to render:
///
/// 1. the catalog image — an absolute URL, a server-relative path, or the
///    base64 data URI the admin panel stores on upload
/// 2. a bundled asset for the vehicle family
/// 3. an icon
///
/// Step 3 exists because the fallbacks previously named `assets/booknow.png`,
/// `assets/bike.png` and `assets/allservice.png`, none of which are in the
/// bundle — so `Image.asset` threw "Asset not found" and painted a red error
/// box over the UI instead of quietly falling back.
class VehicleArt extends StatelessWidget {
  /// Catalog value: `image` or, failing that, `map_icon`.
  final String? source;

  /// `icon_types` from the catalog ('bike' | 'auto' | 'car' | …), used to pick
  /// the bundled stand-in.
  final String? iconType;

  /// Vehicle name, read alongside [iconType] when the family is ambiguous.
  final String? name;

  final double width;
  final double height;

  const VehicleArt({
    super.key,
    required this.source,
    this.iconType,
    this.name,
    this.width = 48,
    this.height = 36,
  });

  /// Only assets that actually ship — see the class doc.
  String get _assetPath {
    final key = '${iconType ?? ''} ${name ?? ''}'.toLowerCase();
    if (key.contains('bike') || key.contains('moto') || key.contains('scooter')) {
      return 'assets/bike_service.webp';
    }
    if (key.contains('parcel') || key.contains('delivery')) {
      return 'assets/parcel_service.webp';
    }
    if (key.contains('auto') || key.contains('rickshaw')) {
      return 'assets/markerauto.webp';
    }
    return 'assets/car.webp';
  }

  Widget get _icon => Icon(
        Icons.local_taxi_rounded,
        size: height * 0.8,
        color: const Color(0xFF94A3B8),
      );

  @override
  Widget build(BuildContext context) {
    final provider = buildSafeImageProvider(resolveMediaUrl(source));

    if (provider != null) {
      return Image(
        image: provider,
        width: width,
        height: height,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => _assetOrIcon(),
      );
    }

    return _assetOrIcon();
  }

  Widget _assetOrIcon() => Image.asset(
        _assetPath,
        width: width,
        height: height,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => SizedBox(
          width: width,
          height: height,
          child: Center(child: _icon),
        ),
      );
}

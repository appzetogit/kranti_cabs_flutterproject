import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../constants/app_constants.dart';

/// Turns backend-supplied vehicle art into map markers.
///
/// The catalog stores `map_icon` as a base64 data URI (and occasionally a plain
/// URL), so both forms are handled. Decoding happens once per source and is
/// cached for the process lifetime — the images are hundreds of KB each and
/// re-decoding them on every camera move would stutter the map.
class MarkerIconLoader {
  MarkerIconLoader._();

  /// Fixed width so a marker looks identical on every device instead of
  /// scaling with whatever resolution the admin happened to upload.
  static const double _markerLogicalWidth = 38.0;

  /// Keyed by hash rather than the source string itself — the keys would
  /// otherwise be megabytes of base64 held alongside the decoded bitmaps.
  static final Map<int, BitmapDescriptor> _cache = {};

  /// Decoded PNG bytes, one launch's markers away from the process-lifetime
  /// cache above going cold. Without this every cold start re-fetched and
  /// re-decoded each vehicle's art from scratch before its marker could
  /// appear, which is what made the vehicle marker visibly pop in late —
  /// see [attachDiskCache].
  static Box? _diskCache;

  /// Wires up the disk-backed cache. Called once at startup (see
  /// `main.dart`), after the box it points at has been opened.
  static void attachDiskCache(Box box) {
    _diskCache = box;
  }

  static Future<BitmapDescriptor?> fromSource(String? source) async {
    final trimmed = source?.trim() ?? '';
    if (trimmed.isEmpty) return null;

    final key = trimmed.hashCode;
    final cached = _cache[key];
    if (cached != null) return cached;

    final double pixelRatio = ui.PlatformDispatcher.instance.implicitView?.devicePixelRatio ?? 3.0;

    final diskBytes = _diskCache?.get(key.toString());
    if (diskBytes is Uint8List) {
      final descriptor = BitmapDescriptor.bytes(diskBytes, imagePixelRatio: pixelRatio);
      _cache[key] = descriptor;
      return descriptor;
    }

    try {
      final bytes = await _readBytes(trimmed);
      if (bytes == null || bytes.isEmpty) return null;

      final int targetWidth = (_markerLogicalWidth * pixelRatio).round();

      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: targetWidth,
      );
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return null;

      final pngBytes = data.buffer.asUint8List();
      final descriptor = BitmapDescriptor.bytes(
        pngBytes,
        imagePixelRatio: pixelRatio,
      );
      _cache[key] = descriptor;
      // Fire-and-forget: next launch reads this back instead of fetching
      // over the network again. A write failure just means one more
      // network round trip next time, not a broken marker now.
      unawaited(_diskCache?.put(key.toString(), pngBytes));
      return descriptor;
    } catch (_) {
      // Corrupt or unsupported art must never take the map down — callers fall
      // back to their default marker.
      return null;
    }
  }

  static Future<Uint8List?> _readBytes(String source) async {
    if (source.startsWith('data:')) {
      final comma = source.indexOf(',');
      if (comma < 0) return null;
      return base64Decode(source.substring(comma + 1));
    }

    // The catalog stores `map_icon` inconsistently — some vehicle types carry
    // a full `https://` URL, others just the server-relative upload path
    // (`/uploads/vehicle-types/…`). Treating the latter as "unsupported" and
    // returning null here is what made a driver's own vehicle type silently
    // fall through to a same-family vehicle's photo instead of its own.
    final resolved =
        source.startsWith('http://') || source.startsWith('https://')
        ? source
        : '${AppConstants.mediaBaseUrl}/${source.replaceFirst(RegExp(r'^/+'), '')}';

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(Uri.parse(resolved));
      final response = await request.close();
      if (response.statusCode != 200) return null;
      final chunks = await response.toList();
      return Uint8List.fromList(chunks.expand((c) => c).toList());
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}

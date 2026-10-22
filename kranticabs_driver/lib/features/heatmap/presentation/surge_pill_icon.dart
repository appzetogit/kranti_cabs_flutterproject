import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// The "1.3x" label drawn on a surging hexagon.
///
/// Markers need a bitmap, and drawing one costs a frame, so each distinct
/// label is drawn once and cached: a busy city has many hexagons but only a
/// handful of different multipliers.
class SurgePillIcon {
  SurgePillIcon._();

  static final Map<String, Future<BitmapDescriptor>> _cache = {};

  static String labelFor(double multiplier) {
    final text = multiplier.toStringAsFixed(2);
    // 1.30 -> 1.3, 1.50 -> 1.5, 1.25 stays.
    final trimmed = text.endsWith('0') ? text.substring(0, text.length - 1) : text;
    return '${trimmed}x';
  }

  /// Orange for a mild surge, through to red at the top of the range.
  static Color colorFor(double multiplier, {double max = 1.5}) {
    final span = (max - 1).clamp(0.1, 1.0);
    final t = ((multiplier - 1) / span).clamp(0.0, 1.0);
    return Color.lerp(const Color(0xFFFF9F1C), const Color(0xFFE5383B), t)!;
  }

  static Future<BitmapDescriptor> forMultiplier(double multiplier, {double max = 1.5}) {
    final label = labelFor(multiplier);
    return _cache.putIfAbsent('$label@$max', () => _draw(label, colorFor(multiplier, max: max)));
  }

  static Future<BitmapDescriptor> _draw(String label, Color color) async {
    const double scale = 3; // drawn at 3x so it stays sharp on dense screens
    const double paddingX = 10 * scale;
    const double paddingY = 5 * scale;
    const double radius = 12 * scale;

    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13 * scale,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final width = painter.width + paddingX * 2;
    final height = painter.height + paddingY * 2;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final rect = RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, width, height), const Radius.circular(radius));

    canvas.drawRRect(rect, Paint()..color = color);
    canvas.drawRRect(
      rect,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * scale,
    );
    painter.paint(canvas, Offset(paddingX, paddingY));

    final image = await recorder.endRecording().toImage(width.ceil(), height.ceil());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List(), imagePixelRatio: scale);
  }
}

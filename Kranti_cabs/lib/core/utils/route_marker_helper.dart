import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class RouteMarkerHelper {
  RouteMarkerHelper._();

  static Future<BitmapDescriptor> createCustomPinWithLabel({
    required String labelText,
    required Color pinColor,
    required Color boxBgColor,
    required Color textColor,
    required String prefix,
  }) async {
    final double pixelRatio = ui.PlatformDispatcher.instance.implicitView?.devicePixelRatio ?? 3.0;

    final pictureRecorder = ui.PictureRecorder();
    final canvas = Canvas(pictureRecorder);
    canvas.scale(pixelRatio, pixelRatio);

    const double paddingX = 8;
    const double paddingY = 4;
    const double pinSize = 14;
    const double pointerHeight = 5;
    const double borderRadius = 6;
    const double fontSize = 10.5;
    // Roughly two thirds of a phone's width. The old 130 cut most real
    // addresses down to a few words plus an ellipsis.
    const double maxLabelWidth = 200;

    final prefixStyle = TextStyle(
      color: pinColor,
      fontSize: fontSize,
      // Medium, not heavy: the label only needs the prefix to read as a
      // separate token from the address, not to shout.
      fontWeight: FontWeight.w500,
    );
    final prefixPainter = TextPainter(
      text: TextSpan(text: '$prefix: ', style: prefixStyle),
      textDirection: TextDirection.ltr,
    )..layout();

    final labelStyle = TextStyle(
      color: textColor,
      fontSize: fontSize,
      fontWeight: FontWeight.normal,
    );
    final labelPainter = TextPainter(
      text: TextSpan(text: labelText.trim(), style: labelStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxLabelWidth);

    final totalTextWidth = prefixPainter.width + labelPainter.width;
    final boxWidth = totalTextWidth + (paddingX * 2);
    final boxHeight = prefixPainter.height + (paddingY * 2);
    final totalHeight = boxHeight + pointerHeight + pinSize + 4;
    final totalWidth = boxWidth < 60 ? 60.0 : boxWidth;

    final centerX = totalWidth / 2;

    // 1. Box Shadow
    final shadowPaint = Paint()
      ..color = const Color(0x20000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    final boxRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(centerX - (boxWidth / 2), 2, boxWidth, boxHeight),
      const Radius.circular(borderRadius),
    );
    canvas.drawRRect(boxRect.shift(const Offset(0, 1.5)), shadowPaint);

    // 2. Box Fill
    final bgPaint = Paint()..color = boxBgColor;
    canvas.drawRRect(boxRect, bgPaint);

    // 3. Box Border
    final borderPaint = Paint()
      ..color = pinColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawRRect(boxRect, borderPaint);

    // 4. Paint Text
    final textStartX = centerX - (boxWidth / 2) + paddingX;
    final textStartY = 2 + paddingY;
    prefixPainter.paint(canvas, Offset(textStartX, textStartY));
    labelPainter.paint(canvas, Offset(textStartX + prefixPainter.width, textStartY));

    // 5. Pointer Arrow
    final arrowPath = Path()
      ..moveTo(centerX - 4, 2 + boxHeight)
      ..lineTo(centerX + 4, 2 + boxHeight)
      ..lineTo(centerX, 2 + boxHeight + pointerHeight)
      ..close();
    final arrowPaint = Paint()..color = boxBgColor;
    canvas.drawPath(arrowPath, arrowPaint);

    // 6. Pin Circle
    final pinCenterY = 2 + boxHeight + pointerHeight + (pinSize / 2);
    final pinBgPaint = Paint()..color = pinColor;
    canvas.drawCircle(Offset(centerX, pinCenterY), pinSize / 2, pinBgPaint);

    final pinInnerPaint = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(centerX, pinCenterY), pinSize / 4, pinInnerPaint);

    final image = await pictureRecorder.endRecording().toImage(
          (totalWidth * pixelRatio).ceil(),
          (totalHeight * pixelRatio).ceil(),
        );
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    // `imagePixelRatio` is what keeps the label the size it was drawn at. The
    // bitmap is rendered at device pixel density for sharpness; without telling
    // the map that, it treats those as logical pixels and the whole chip comes
    // out ~3x oversized on a typical phone — which is what made these labels
    // dominate the map.
    return BitmapDescriptor.bytes(
      byteData!.buffer.asUint8List(),
      imagePixelRatio: pixelRatio,
    );
  }
}

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Renders a marker bitmap that always shows the favorite's name above a
/// star-colored pin.
///
/// The Google Maps SDK marker API has no built-in persistent label (the
/// stock [InfoWindow] only appears on tap), so the label is baked directly
/// into the marker bitmap instead.
class FavoriteMarkerIconBuilder {
  FavoriteMarkerIconBuilder._();

  static const double _pixelRatio = 3.0;
  static const double _pinDiameter = 22;
  static const double _maxLabelTextWidth = 140;
  static const double _labelHorizontalPadding = 8;
  static const double _labelVerticalPadding = 4;
  static const double _labelGap = 4;
  static const double _fontSize = 12;

  /// Builds a [BitmapDescriptor] with [name] rendered as a label chip above
  /// a gold pin. Falls back to a plain colored marker if rendering fails.
  static Future<BitmapDescriptor> build(String name) async {
    final textPainter = TextPainter(
      text: TextSpan(
        text: name,
        style: const TextStyle(
          color: Colors.white,
          fontSize: _fontSize,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: _maxLabelTextWidth);

    final labelWidth = textPainter.width + _labelHorizontalPadding * 2;
    final labelHeight = textPainter.height + _labelVerticalPadding * 2;
    final canvasWidth = labelWidth < _pinDiameter ? _pinDiameter : labelWidth;
    final canvasHeight = labelHeight + _labelGap + _pinDiameter;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(_pixelRatio);

    final labelRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(canvasWidth / 2, labelHeight / 2),
        width: labelWidth,
        height: labelHeight,
      ),
      const Radius.circular(6),
    );
    canvas.drawRRect(labelRect, Paint()..color = const Color(0xE6212121));

    textPainter.paint(
      canvas,
      Offset(
        canvasWidth / 2 - textPainter.width / 2,
        labelHeight / 2 - textPainter.height / 2,
      ),
    );

    final pinCenter = Offset(
      canvasWidth / 2,
      labelHeight + _labelGap + _pinDiameter / 2,
    );
    canvas.drawCircle(
      pinCenter,
      _pinDiameter / 2,
      Paint()..color = const Color(0xFFFFC107),
    );
    canvas.drawCircle(
      pinCenter,
      _pinDiameter / 2,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    final starPainter = TextPainter(
      text: const TextSpan(
        text: '★',
        style: TextStyle(color: Colors.white, fontSize: _pinDiameter * 0.55),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    starPainter.paint(
      canvas,
      Offset(
        pinCenter.dx - starPainter.width / 2,
        pinCenter.dy - starPainter.height / 2 - 1,
      ),
    );

    final picture = recorder.endRecording();
    final pixelWidth = (canvasWidth * _pixelRatio).round();
    final pixelHeight = (canvasHeight * _pixelRatio).round();
    final image = await picture.toImage(pixelWidth, pixelHeight);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();

    if (byteData == null) {
      return BitmapDescriptor.defaultMarkerWithHue(
        BitmapDescriptor.hueYellow,
      );
    }

    return BitmapDescriptor.bytes(
      byteData.buffer.asUint8List(),
      imagePixelRatio: _pixelRatio,
    );
  }
}

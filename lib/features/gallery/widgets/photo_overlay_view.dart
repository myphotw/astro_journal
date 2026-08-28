import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/photo_overlay_object.dart';
import '../../../shared/widgets/app_file_image.dart';

@visibleForTesting
Rect photoOverlayContainRect({required Size viewport, required Size source}) {
  final fit = math.min(
    viewport.width / source.width,
    viewport.height / source.height,
  );
  final rendered = Size(source.width * fit, source.height * fit);
  return Alignment.center.inscribe(rendered, Offset.zero & viewport);
}

/// Resolves presentation geometry without changing the catalog-derived ring.
///
/// The ring radii always remain the projected angular radii. A separate center
/// marker identifies objects whose real ring is too small to read on screen.
@visibleForTesting
({double radiusX, double radiusY, bool drawRing, bool drawCenterMarker})
photoOverlayRenderGeometry(
  PhotoOverlayObject object, {
  required double scale,
  double markerThreshold = 4,
}) {
  final major = object.rangeRadiusMajorPixel;
  if (major == null || !major.isFinite || major <= 0 || scale <= 0) {
    return (radiusX: 0, radiusY: 0, drawRing: false, drawCenterMarker: true);
  }

  final minor = object.rangeRadiusMinorPixel;
  final radiusX = major * scale;
  final radiusY = minor != null && minor.isFinite && minor > 0
      ? minor * scale
      : radiusX;
  return (
    radiusX: radiusX,
    radiusY: radiusY,
    drawRing: true,
    drawCenterMarker: math.max(radiusX, radiusY) < markerThreshold,
  );
}

/// 사진 위에 Catalog 천체 Overlay(Marker + Label)를 그리는 위젯.
///
/// 표시는 [BoxFit.contain]과 동일하게
/// source → display 스케일을 맞춘 뒤 그 위에 Overlay를 올린다.
class PhotoOverlayView extends StatelessWidget {
  const PhotoOverlayView({
    super.key,
    required this.photoPath,
    required this.imageWidth,
    required this.imageHeight,
    this.objects = const [],
    this.showTarget = true,
    this.showNearby = true,
  });

  final String photoPath;
  final int imageWidth;
  final int imageHeight;
  final List<PhotoOverlayObject> objects;
  final bool showTarget;
  final bool showNearby;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final srcW = imageWidth > 0 ? imageWidth.toDouble() : 1.0;
        final srcH = imageHeight > 0 ? imageHeight.toDouble() : 1.0;
        final maxW = constraints.maxWidth;
        final maxH = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : maxW * srcH / srcW;

        // BoxFit.contain
        final imageRect = photoOverlayContainRect(
          viewport: Size(maxW, maxH),
          source: Size(srcW, srcH),
        );
        final dispW = imageRect.width;
        final dispH = imageRect.height;

        return SizedBox(
          width: maxW,
          height: maxH.isFinite ? maxH : dispH,
          child: Center(
            child: SizedBox(
              width: dispW,
              height: dispH,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AppFileImage(
                    path: photoPath,
                    fit: BoxFit.fill,
                    memCacheWidth: 1600,
                    filterQuality: FilterQuality.medium,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) => Container(
                      color: AppColors.surface,
                      child: const Center(
                        child: Icon(
                          Icons.broken_image_outlined,
                          size: 64,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  if (objects.isNotEmpty && (showTarget || showNearby))
                    CustomPaint(
                      painter: _PhotoOverlayPainter(
                        objects: objects,
                        imageWidth: imageWidth,
                        imageHeight: imageHeight,
                        showTarget: showTarget,
                        showNearby: showNearby,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PhotoOverlayPainter extends CustomPainter {
  _PhotoOverlayPainter({
    required this.objects,
    required this.imageWidth,
    required this.imageHeight,
    required this.showTarget,
    required this.showNearby,
  });

  final List<PhotoOverlayObject> objects;
  final int imageWidth;
  final int imageHeight;
  final bool showTarget;
  final bool showNearby;

  static const _targetColor = Color(0xFFFFD54F);
  static const _nearbyColor = Color(0xFF80D8FF);
  static const _centerMarkerGap = 2.0;
  static const _centerMarkerExtent = 5.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (imageWidth <= 0 || imageHeight <= 0) return;
    // source → display (SizedBox가 contain 결과이므로 scaleX≈scaleY)
    final scaleX = size.width / imageWidth;
    final scaleY = size.height / imageHeight;
    final scale = (scaleX + scaleY) / 2;

    canvas.save();
    canvas.clipRect(Offset.zero & size);

    final nearby = objects.where((o) => !o.isTarget);
    final targets = objects.where((o) => o.isTarget);

    for (final obj in [...nearby, ...targets]) {
      if (obj.isTarget && !showTarget) continue;
      if (!obj.isTarget && !showNearby) continue;

      final center = Offset(obj.pixelX * scaleX, obj.pixelY * scaleY);

      if (obj.isTarget) {
        _drawTarget(canvas, center, obj, scale, size);
      } else {
        _drawNearby(canvas, center, obj, scale, size);
      }
    }

    canvas.restore();
  }

  void _drawTarget(
    Canvas canvas,
    Offset center,
    PhotoOverlayObject obj,
    double scale,
    Size canvasSize,
  ) {
    final geometry = photoOverlayRenderGeometry(obj, scale: scale);
    final paint = Paint()
      ..color = _targetColor.withValues(alpha: 0.95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15
      ..isAntiAlias = true;

    if (geometry.drawRing) {
      _drawEllipse(
        canvas,
        center,
        geometry.radiusX,
        geometry.radiusY,
        paint,
        dashed: false,
      );
    }
    if (geometry.drawCenterMarker) {
      _drawCenterMarker(canvas, center, _targetColor, strokeWidth: 0.9);
    }

    _drawStellariumLabel(
      canvas,
      center: center,
      radiusX: _labelRadius(geometry.radiusX, geometry.drawCenterMarker),
      radiusY: _labelRadius(geometry.radiusY, geometry.drawCenterMarker),
      label: obj.displayLabel,
      color: _targetColor,
      fontSize: 11,
      bold: true,
      canvasSize: canvasSize,
    );
  }

  void _drawNearby(
    Canvas canvas,
    Offset center,
    PhotoOverlayObject obj,
    double scale,
    Size canvasSize,
  ) {
    final geometry = photoOverlayRenderGeometry(obj, scale: scale);
    final paint = Paint()
      ..color = _nearbyColor.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.95
      ..isAntiAlias = true;

    if (geometry.drawRing) {
      _drawEllipse(
        canvas,
        center,
        geometry.radiusX,
        geometry.radiusY,
        paint,
        dashed: true,
      );
    }
    if (geometry.drawCenterMarker) {
      _drawCenterMarker(canvas, center, _nearbyColor, strokeWidth: 0.75);
    }

    _drawStellariumLabel(
      canvas,
      center: center,
      radiusX: _labelRadius(geometry.radiusX, geometry.drawCenterMarker),
      radiusY: _labelRadius(geometry.radiusY, geometry.drawCenterMarker),
      label: obj.name,
      color: _nearbyColor,
      fontSize: 9.5,
      bold: false,
      canvasSize: canvasSize,
    );
  }

  double _labelRadius(double actualRadius, bool hasCenterMarker) =>
      hasCenterMarker
      ? math.max(actualRadius, _centerMarkerExtent)
      : actualRadius;

  void _drawCenterMarker(
    Canvas canvas,
    Offset center,
    Color color, {
    required double strokeWidth,
  }) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..isAntiAlias = true;
    canvas.drawLine(
      Offset(center.dx - _centerMarkerExtent, center.dy),
      Offset(center.dx - _centerMarkerGap, center.dy),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx + _centerMarkerGap, center.dy),
      Offset(center.dx + _centerMarkerExtent, center.dy),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - _centerMarkerExtent),
      Offset(center.dx, center.dy - _centerMarkerGap),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy + _centerMarkerGap),
      Offset(center.dx, center.dy + _centerMarkerExtent),
      paint,
    );
  }

  void _drawEllipse(
    Canvas canvas,
    Offset center,
    double rx,
    double ry,
    Paint paint, {
    required bool dashed,
  }) {
    final rect = Rect.fromCenter(center: center, width: rx * 2, height: ry * 2);
    if (!dashed) {
      canvas.drawOval(rect, paint);
      return;
    }

    const segments = 32;
    const dashRatio = 0.48;
    for (var i = 0; i < segments; i++) {
      final start = i * 2 * math.pi / segments;
      final sweep = 2 * math.pi / segments * dashRatio;
      canvas.drawArc(rect, start, sweep, false, paint);
    }
  }

  void _drawStellariumLabel(
    Canvas canvas, {
    required Offset center,
    required double radiusX,
    required double radiusY,
    required String label,
    required Color color,
    required double fontSize,
    required bool bold,
    required Size canvasSize,
  }) {
    const pad = 6.0;
    final maxLabelWidth = math.max(
      40.0,
      math.min(
        canvasSize.width * 0.38,
        math.max(center.dx, canvasSize.width - center.dx) - pad,
      ),
    );
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: color.withValues(alpha: 0.95),
          fontSize: fontSize,
          fontWeight: bold ? FontWeight.w600 : FontWeight.w500,
          letterSpacing: 0.2,
          shadows: [
            Shadow(
              color: Colors.black.withValues(alpha: 0.85),
              blurRadius: 2.5,
              offset: const Offset(0.5, 0.5),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxLabelWidth);

    const gap = 3.0;
    const leader = 6.0;
    final tw = textPainter.width;
    final th = textPainter.height;
    final maxX = math.max(pad, canvasSize.width - pad - tw);
    final maxY = math.max(pad, canvasSize.height - pad - th);

    Offset clampPos(Offset o) =>
        Offset(o.dx.clamp(pad, maxX), o.dy.clamp(pad, maxY));

    final candidates = <Offset>[
      clampPos(Offset(center.dx + radiusX + gap + leader, center.dy - th / 2)),
      clampPos(
        Offset(center.dx - radiusX - gap - leader - tw, center.dy - th / 2),
      ),
      clampPos(Offset(center.dx - tw / 2, center.dy + radiusY + gap)),
      clampPos(Offset(center.dx - tw / 2, center.dy - radiusY - gap - th)),
    ];

    Offset labelPos = candidates.first;
    var bestScore = double.infinity;
    for (final c in candidates) {
      final labelCenter = Offset(c.dx + tw / 2, c.dy + th / 2);
      final dx = labelCenter.dx - center.dx;
      final dy = labelCenter.dy - center.dy;
      final score = dx * dx + dy * dy;
      final fullyInside =
          c.dx >= pad - 0.5 &&
          c.dy >= pad - 0.5 &&
          c.dx + tw <= canvasSize.width - pad + 0.5 &&
          c.dy + th <= canvasSize.height - pad + 0.5;
      final adjusted = fullyInside ? score : score + 1e6;
      if (adjusted < bestScore) {
        bestScore = adjusted;
        labelPos = c;
      }
    }

    final labelCenter = Offset(labelPos.dx + tw / 2, labelPos.dy + th / 2);
    final edge = _ellipseEdgeToward(center, radiusX, radiusY, labelCenter);

    final linePaint = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..strokeWidth = bold ? 1.0 : 0.85
      ..style = PaintingStyle.stroke;
    canvas.drawLine(edge, labelCenter, linePaint);
    textPainter.paint(canvas, labelPos);
  }

  Offset _ellipseEdgeToward(
    Offset center,
    double rx,
    double ry,
    Offset target,
  ) {
    final dx = target.dx - center.dx;
    final dy = target.dy - center.dy;
    if (dx.abs() < 1e-6 && dy.abs() < 1e-6) {
      return center.translate(rx, 0);
    }
    final angle = math.atan2(dy, dx);
    return Offset(
      center.dx + rx * math.cos(angle),
      center.dy + ry * math.sin(angle),
    );
  }

  @override
  bool shouldRepaint(covariant _PhotoOverlayPainter oldDelegate) {
    return oldDelegate.objects != objects ||
        oldDelegate.showTarget != showTarget ||
        oldDelegate.showNearby != showNearby ||
        oldDelegate.imageWidth != imageWidth ||
        oldDelegate.imageHeight != imageHeight;
  }
}

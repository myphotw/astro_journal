import 'package:flutter/material.dart';

import '../../../../data/models/sky_map_render_object.dart';
import '../sky_map_visual_style.dart';

/// Layer: Constellation Line — 연결선 + 별자리 이름 라벨.
class ConstellationPainter extends CustomPainter {
  ConstellationPainter({
    required this.constellations,
    required this.viewHeightDeg,
    this.occupiedLabels,
  });

  final List<SkyMapConstellationRender> constellations;
  final double viewHeightDeg;
  final List<Rect>? occupiedLabels;

  TextStyle get labelStyle => TextStyle(
    color: SkyMapVisualStyle.constellationLabel.withValues(alpha: 0.88),
    fontSize: viewHeightDeg <= 40 ? 13 : (viewHeightDeg <= 100 ? 12 : 11),
    fontWeight: FontWeight.w600,
    letterSpacing: 0.35,
    shadows: const [
      Shadow(color: Color(0xCC000000), blurRadius: 4, offset: Offset(0, 1)),
    ],
  );

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = SkyMapVisualStyle.constellationLine.withValues(alpha: 0.62)
      ..strokeWidth = viewHeightDeg <= 45 ? 1.0 : 0.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (final c in constellations) {
      for (final segment in c.segments) {
        final start = Offset(segment.$1.x, segment.$1.y);
        final end = Offset(segment.$2.x, segment.$2.y);
        final startVisibility = SkyMapVisualStyle.visibilityForAltitude(
          segment.$1.altitudeDeg,
        );
        final endVisibility = SkyMapVisualStyle.visibilityForAltitude(
          segment.$2.altitudeDeg,
        );
        final segmentBounds = Rect.fromPoints(start, end);
        final segmentPaint = Paint()
          ..strokeWidth = linePaint.strokeWidth
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;
        if (segmentBounds.width < 0.01 && segmentBounds.height < 0.01) {
          segmentPaint.color = SkyMapVisualStyle.constellationLine.withValues(
            alpha: 0.31 * (startVisibility + endVisibility),
          );
        } else {
          segmentPaint.shader = LinearGradient(
            colors: [
              SkyMapVisualStyle.constellationLine.withValues(
                alpha: 0.62 * startVisibility,
              ),
              SkyMapVisualStyle.constellationLine.withValues(
                alpha: 0.62 * endVisibility,
              ),
            ],
          ).createShader(segmentBounds);
        }
        canvas.drawLine(start, end, segmentPaint);
      }
      if (c.segments.isEmpty || !c.showLabel) continue;
      final painter = TextPainter(
        text: TextSpan(
          text: c.name,
          style: labelStyle.copyWith(
            color: labelStyle.color?.withValues(
              alpha: SkyMapVisualStyle.visibilityForAltitude(
                c.labelAltitudeDeg,
              ),
            ),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final offset = Offset(
        c.labelX - painter.width / 2,
        c.labelY - painter.height / 2,
      );
      final bounds = (offset & painter.size).inflate(3);
      if (!(Offset.zero & size).overlaps(bounds)) continue;
      painter.paint(canvas, offset);
      occupiedLabels?.add(bounds);
    }
  }

  @override
  bool shouldRepaint(covariant ConstellationPainter oldDelegate) {
    return oldDelegate.constellations != constellations ||
        oldDelegate.viewHeightDeg != viewHeightDeg;
  }
}

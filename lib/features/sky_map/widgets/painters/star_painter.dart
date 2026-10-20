import 'package:flutter/material.dart';

import '../../../../data/models/sky_map_render_object.dart';
import '../sky_map_visual_style.dart';

/// Layer 3: 밝은 별 (1~3등성).
class StarPainter extends CustomPainter {
  StarPainter({
    required this.stars,
    required this.showLabels,
    required this.viewHeightDeg,
    this.occupiedLabels,
  });

  final List<SkyMapStarRender> stars;
  final bool showLabels;
  final double viewHeightDeg;
  final List<Rect>? occupiedLabels;

  @override
  void paint(Canvas canvas, Size size) {
    final labelStyle = TextStyle(
      color: SkyMapVisualStyle.coordinateLabel.withValues(alpha: 0.82),
      fontSize: viewHeightDeg <= 30 ? 10 : 9,
      fontWeight: FontWeight.w500,
      shadows: const [Shadow(color: Color(0xCC000000), blurRadius: 3)],
    );

    for (final star in stars) {
      final center = Offset(star.screenX, star.screenY);
      final visibility = SkyMapVisualStyle.visibilityForAltitude(
        star.altitudeDeg,
      );
      final brightness = ((3.5 - star.magnitude) / 4).clamp(0.35, 1.0);
      if (star.magnitude <= 1.5) {
        final glow = Paint()
          ..color = const Color(0xFFEAF2FF).withValues(alpha: 0.11 * visibility)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
        canvas.drawCircle(center, star.markerRadius + 0.9, glow);
      }
      canvas.drawCircle(
        center,
        star.markerRadius,
        Paint()
          ..color = const Color(
            0xFFF2F6FF,
          ).withValues(alpha: (0.64 + brightness * 0.32) * visibility),
      );

      if (showLabels && _shouldLabel(star)) {
        final painter = TextPainter(
          text: TextSpan(
            text: star.name,
            style: labelStyle.copyWith(
              color: labelStyle.color?.withValues(alpha: visibility),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final offset = Offset(
          center.dx - painter.width / 2,
          center.dy - star.markerRadius - painter.height - 2,
        );
        final bounds = (offset & painter.size).inflate(2);
        if (_canPlaceLabel(bounds, size)) {
          painter.paint(canvas, offset);
          occupiedLabels?.add(bounds);
        }
      }
    }
  }

  bool _shouldLabel(SkyMapStarRender star) {
    if (viewHeightDeg <= 25) return star.magnitude <= 3;
    if (viewHeightDeg <= 50) return star.magnitude <= 2;
    return star.magnitude <= 1;
  }

  bool _canPlaceLabel(Rect bounds, Size size) {
    if (!(Offset.zero & size).overlaps(bounds)) return false;
    final occupied = occupiedLabels;
    if (occupied == null) return true;
    return !occupied.any((rect) => rect.overlaps(bounds));
  }

  @override
  bool shouldRepaint(covariant StarPainter oldDelegate) {
    return oldDelegate.stars != stars ||
        oldDelegate.showLabels != showLabels ||
        oldDelegate.viewHeightDeg != viewHeightDeg;
  }
}

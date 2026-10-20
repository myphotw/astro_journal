import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/sky_map_render_object.dart';

/// Layer 3: 밝은 별 (1~3등성).
class StarPainter extends CustomPainter {
  StarPainter({
    required this.stars,
    required this.showLabels,
    this.occupiedLabels,
  });

  final List<SkyMapStarRender> stars;
  final bool showLabels;
  final List<Rect>? occupiedLabels;

  @override
  void paint(Canvas canvas, Size size) {
    final labelStyle = TextStyle(
      color: AppColors.star.withValues(alpha: 0.9),
      fontSize: 10,
      fontWeight: FontWeight.w500,
    );

    for (final star in stars) {
      final center = Offset(star.screenX, star.screenY);
      final glow = Paint()
        ..color = Colors.white.withValues(alpha: 0.12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.8);
      canvas.drawCircle(center, star.markerRadius + 1.2, glow);
      canvas.drawCircle(
        center,
        star.markerRadius,
        Paint()..color = Colors.white.withValues(alpha: 0.95),
      );

      if (showLabels) {
        final painter = TextPainter(
          text: TextSpan(text: star.name, style: labelStyle),
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

  bool _canPlaceLabel(Rect bounds, Size size) {
    if (!(Offset.zero & size).overlaps(bounds)) return false;
    final occupied = occupiedLabels;
    if (occupied == null) return true;
    return !occupied.any((rect) => rect.overlaps(bounds));
  }

  @override
  bool shouldRepaint(covariant StarPainter oldDelegate) {
    return oldDelegate.stars != stars || oldDelegate.showLabels != showLabels;
  }
}

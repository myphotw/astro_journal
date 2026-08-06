import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/sky_map_render_object.dart';

/// Layer 3: 밝은 별 (1~3등성).
class StarPainter extends CustomPainter {
  StarPainter({
    required this.stars,
    required this.showLabels,
  });

  final List<SkyMapStarRender> stars;
  final bool showLabels;

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
        ..color = Colors.white.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawCircle(center, star.markerRadius + 3, glow);
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
        painter.paint(
          canvas,
          Offset(
            center.dx - painter.width / 2,
            center.dy - star.markerRadius - painter.height - 2,
          ),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant StarPainter oldDelegate) {
    return oldDelegate.stars != stars || oldDelegate.showLabels != showLabels;
  }
}

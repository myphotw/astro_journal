import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Layer 5: 장비 FOV Overlay.
class FovPainter extends CustomPainter {
  FovPainter({required this.corners});

  final List<Offset> corners;

  @override
  void paint(Canvas canvas, Size size) {
    if (corners.length != 4) return;

    final path = Path()
      ..moveTo(corners[0].dx, corners[0].dy)
      ..lineTo(corners[1].dx, corners[1].dy)
      ..lineTo(corners[2].dx, corners[2].dy)
      ..lineTo(corners[3].dx, corners[3].dy)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.solar.withValues(alpha: 0.12)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.solar.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8,
    );

    // 모서리 강조
    final cornerPaint = Paint()..color = AppColors.solar;
    for (final c in corners) {
      canvas.drawCircle(c, 2.5, cornerPaint);
    }
  }

  @override
  bool shouldRepaint(covariant FovPainter oldDelegate) {
    return oldDelegate.corners != corners;
  }
}

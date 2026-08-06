import 'package:flutter/material.dart';

import '../../../../data/models/sky_map_render_object.dart';

/// Layer: Constellation Line — 연결선 + 별자리 이름 라벨.
class ConstellationPainter extends CustomPainter {
  ConstellationPainter({required this.constellations});

  final List<SkyMapConstellationRender> constellations;

  /// 배경(#080B14) 대비를 높인 밝은 청록 — 별보다 덜 눈에 띄게 유지.
  static const _lineColor = Color(0xFF9BE7FF);
  static const _labelColor = Color(0xFFB8F0FF);

  static TextStyle get labelStyle => const TextStyle(
        color: _labelColor,
        fontSize: 13,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
        shadows: [
          Shadow(
            color: Color(0xCC000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      );

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = _lineColor.withValues(alpha: 0.88)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (final c in constellations) {
      for (final segment in c.segments) {
        canvas.drawLine(
          Offset(segment.$1.x, segment.$1.y),
          Offset(segment.$2.x, segment.$2.y),
          linePaint,
        );
      }
      if (c.segments.isEmpty) continue;
      final painter = TextPainter(
        text: TextSpan(text: c.name, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        Offset(c.labelX - painter.width / 2, c.labelY - painter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant ConstellationPainter oldDelegate) {
    return oldDelegate.constellations != constellations;
  }
}

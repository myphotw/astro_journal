import 'package:flutter/material.dart';

/// Layer 1: 배경 + 방위.
class SkyMapBackgroundPainter extends CustomPainter {
  const SkyMapBackgroundPainter();

  static const _cardinalColor = Color(0xFFE8F7FF);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final gradient = const RadialGradient(
      center: Alignment(0, -0.15),
      radius: 1.1,
      colors: [
        Color(0xFF12204A),
        Color(0xFF080B14),
        Color(0xFF05070E),
      ],
      stops: [0.0, 0.55, 1.0],
    );
    canvas.drawRect(rect, Paint()..shader = gradient.createShader(rect));

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..strokeWidth = 1;
    const step = 64.0;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final guide = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..strokeWidth = 1.2;
    final cx = size.width / 2;
    final cy = size.height / 2;
    canvas.drawLine(Offset(cx, 22), Offset(cx, size.height - 22), guide);
    canvas.drawLine(Offset(22, cy), Offset(size.width - 22, cy), guide);

    const style = TextStyle(
      color: _cardinalColor,
      fontSize: 15,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.0,
      shadows: [
        Shadow(
          color: Color(0xE6000000),
          blurRadius: 6,
          offset: Offset(0, 1),
        ),
      ],
    );
    _label(canvas, 'N', Offset(cx, 20), style);
    _label(canvas, 'S', Offset(cx, size.height - 20), style);
    _label(canvas, 'W', Offset(20, cy), style);
    _label(canvas, 'E', Offset(size.width - 20, cy), style);
  }

  void _label(Canvas canvas, String text, Offset center, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();

    final bgRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: center,
        width: painter.width + 10,
        height: painter.height + 6,
      ),
      const Radius.circular(6),
    );
    canvas.drawRRect(
      bgRect,
      Paint()..color = const Color(0xCC0D1B3E),
    );
    canvas.drawRRect(
      bgRect,
      Paint()
        ..color = _cardinalColor.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    painter.paint(
      canvas,
      Offset(center.dx - painter.width / 2, center.dy - painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant SkyMapBackgroundPainter oldDelegate) => false;
}

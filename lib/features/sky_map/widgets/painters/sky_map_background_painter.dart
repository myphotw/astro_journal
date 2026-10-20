import 'package:flutter/material.dart';

import '../../../../services/sky_map_horizontal_projection_service.dart';

/// 관측자 수평 좌표계 배경: 차분한 밤하늘 + Alt/Az 곡선 격자.
class SkyMapBackgroundPainter extends CustomPainter {
  const SkyMapBackgroundPainter({
    required this.centerAltitudeDeg,
    required this.centerAzimuthDeg,
    required this.viewHeightDeg,
  });

  final double centerAltitudeDeg;
  final double centerAzimuthDeg;
  final double viewHeightDeg;

  static const _cardinalColor = Color(0xFFD6E8EC);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shader = const RadialGradient(
      center: Alignment(0, -0.08),
      radius: 1.15,
      colors: [Color(0xFF0B1424), Color(0xFF04070D)],
    ).createShader(rect);
    canvas.drawRect(rect, Paint()..shader = shader);

    final minorGrid = Paint()
      ..color = const Color(0xFF7DA1AF).withValues(alpha: 0.13)
      ..strokeWidth = 0.7
      ..style = PaintingStyle.stroke;
    final majorGrid = Paint()
      ..color = const Color(0xFF8EB2BF).withValues(alpha: 0.23)
      ..strokeWidth = 0.9
      ..style = PaintingStyle.stroke;
    final horizonPaint = Paint()
      ..color = const Color(0xFFB3CDD3).withValues(alpha: 0.42)
      ..strokeWidth = 1.25
      ..style = PaintingStyle.stroke;

    for (final altitude in const [0.0, 15.0, 30.0, 45.0, 60.0, 75.0]) {
      final points = <Offset>[];
      for (var azimuth = 0.0; azimuth <= 360; azimuth += 2) {
        points.add(_project(altitude, azimuth, size));
      }
      _drawSampledCurve(
        canvas,
        size,
        points,
        altitude == 0
            ? horizonPaint
            : (altitude % 30 == 0 ? majorGrid : minorGrid),
      );
    }

    for (var azimuth = 0.0; azimuth < 360; azimuth += 30) {
      final points = <Offset>[];
      for (var altitude = -30.0; altitude <= 90; altitude += 2) {
        points.add(_project(altitude, azimuth, size));
      }
      _drawSampledCurve(
        canvas,
        size,
        points,
        azimuth % 90 == 0 ? majorGrid : minorGrid,
      );
    }

    _drawZenith(canvas, size);
    for (final cardinal in const [
      (azimuth: 0.0, label: 'N'),
      (azimuth: 90.0, label: 'E'),
      (azimuth: 180.0, label: 'S'),
      (azimuth: 270.0, label: 'W'),
    ]) {
      final position = _project(0, cardinal.azimuth, size);
      if ((Offset.zero & size).inflate(20).contains(position)) {
        _label(canvas, cardinal.label, position, size);
      }
    }
  }

  Offset _project(double altitude, double azimuth, Size size) =>
      SkyMapHorizontalProjectionService.project(
        altitudeDeg: altitude,
        azimuthDeg: azimuth,
        centerAltitudeDeg: centerAltitudeDeg,
        centerAzimuthDeg: centerAzimuthDeg,
        canvasSize: size,
        viewHeightDeg: viewHeightDeg,
      ).pixel;

  void _drawSampledCurve(
    Canvas canvas,
    Size size,
    List<Offset> points,
    Paint paint,
  ) {
    final expandedBounds = (Offset.zero & size).inflate(30);
    final maxChord = size.longestSide * 0.22;
    final path = Path();
    var started = false;
    Offset? previous;
    for (final point in points) {
      final connected =
          previous != null &&
          (point - previous).distance <= maxChord &&
          (expandedBounds.contains(point) || expandedBounds.contains(previous));
      if (!connected) started = false;
      if (!started) {
        path.moveTo(point.dx, point.dy);
        started = true;
      } else {
        path.lineTo(point.dx, point.dy);
      }
      previous = point;
    }
    canvas.drawPath(path, paint);
  }

  void _drawZenith(Canvas canvas, Size size) {
    final zenith = _project(90, 0, size);
    if (!(Offset.zero & size).inflate(-8).contains(zenith)) return;
    final paint = Paint()
      ..color = const Color(0xFF9FBCC4).withValues(alpha: 0.38)
      ..strokeWidth = 0.9
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(zenith, 3.5, paint);
    canvas.drawLine(
      zenith - const Offset(6, 0),
      zenith + const Offset(6, 0),
      paint,
    );
    canvas.drawLine(
      zenith - const Offset(0, 6),
      zenith + const Offset(0, 6),
      paint,
    );
  }

  void _label(Canvas canvas, String text, Offset center, Size size) {
    const style = TextStyle(
      color: _cardinalColor,
      fontSize: 13,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
      shadows: [Shadow(color: Color(0xE6000000), blurRadius: 4)],
    );
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final safeCenter = Offset(
      center.dx.clamp(
        painter.width / 2 + 4,
        size.width - painter.width / 2 - 4,
      ),
      center.dy.clamp(
        painter.height / 2 + 4,
        size.height - painter.height / 2 - 4,
      ),
    );
    final background = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: safeCenter,
        width: painter.width + 8,
        height: painter.height + 4,
      ),
      const Radius.circular(5),
    );
    canvas.drawRRect(background, Paint()..color = const Color(0x9904080E));
    painter.paint(
      canvas,
      safeCenter - Offset(painter.width / 2, painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant SkyMapBackgroundPainter oldDelegate) =>
      oldDelegate.centerAltitudeDeg != centerAltitudeDeg ||
      oldDelegate.centerAzimuthDeg != centerAzimuthDeg ||
      oldDelegate.viewHeightDeg != viewHeightDeg;
}

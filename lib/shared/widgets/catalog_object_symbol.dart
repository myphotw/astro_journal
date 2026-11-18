import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/constants/catalog_type.dart';
import '../../core/constants/object_type.dart';
import '../../core/theme/pc_design.dart';
import '../../data/models/catalog_object.dart';

/// Illustrations for image placeholders, not positional sky-map glyphs.
enum CatalogSymbolKind {
  galaxy,
  galaxyGroup,
  emissionNebula,
  reflectionNebula,
  darkNebula,
  planetaryNebula,
  openCluster,
  globularCluster,
  supernovaRemnant,
  complexNebula,
  nebulaWithCluster,
  starCloud,
  milkyWay,
  doubleStar,
  star,
  planet,
  moon,
  dwarfPlanet,
  sun,
  comet,
  unknown;

  static CatalogSymbolKind forObject(CatalogObject object) {
    if (object.catalog == CatalogType.solar && object.id == 'solar_1') {
      return sun;
    }
    // These labels already exist in the catalog. Interpret them for painting
    // only; changing the canonical types would also change filters and stats.
    switch ((object.objectType ?? object.type).trim()) {
      case '혜성':
        return comet;
      case '성단과 성운':
        return nebulaWithCluster;
    }
    return switch (object.resolvedObjectType) {
      ObjectType.galaxy => galaxy,
      ObjectType.galaxyGroup => galaxyGroup,
      ObjectType.emissionNebula => emissionNebula,
      ObjectType.reflectionNebula => reflectionNebula,
      ObjectType.darkNebula => darkNebula,
      ObjectType.planetaryNebula => planetaryNebula,
      ObjectType.openCluster => openCluster,
      ObjectType.globularCluster => globularCluster,
      ObjectType.supernovaRemnant => supernovaRemnant,
      ObjectType.complexNebula => complexNebula,
      ObjectType.nebulaWithCluster => nebulaWithCluster,
      ObjectType.starCloud => starCloud,
      ObjectType.milkyWay => milkyWay,
      ObjectType.doubleStar => doubleStar,
      ObjectType.star => star,
      ObjectType.planet => planet,
      ObjectType.moon => moon,
      ObjectType.dwarfPlanet => dwarfPlanet,
      ObjectType.other => unknown,
    };
  }
}

class CatalogObjectSymbol extends StatelessWidget {
  const CatalogObjectSymbol({
    super.key,
    required this.kind,
    required this.size,
  });

  final CatalogSymbolKind kind;
  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: CatalogSymbolPainter(kind), size: Size.square(size));
}

/// All silhouettes use the same 48-unit viewport and steel-blue paint.
class CatalogSymbolPainter extends CustomPainter {
  const CatalogSymbolPainter(this.kind);

  final CatalogSymbolKind kind;
  static const _center = Offset(24, 24);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 48;
    if (scale <= 0) return;
    canvas.save();
    canvas.translate(
      (size.width - 48 * scale) / 2,
      (size.height - 48 * scale) / 2,
    );
    canvas.scale(scale);
    final line = Paint()
      ..color = PcDesign.secondary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final light = Paint()..color = PcDesign.text;
    final soft = Paint()..color = PcDesign.accent.withValues(alpha: .24);

    void draw(Path path) => canvas.drawPath(path, line);
    void dot(double x, double y, [double radius = 1.35]) =>
        canvas.drawCircle(Offset(x, y), radius, light);
    void star(double x, double y, double radius) =>
        canvas.drawPath(_star(Offset(x, y), radius), light);
    void field(List<(double, double, double)> stars) {
      for (final (x, y, radius) in stars) {
        dot(x, y, radius);
      }
    }

    switch (kind) {
      case CatalogSymbolKind.galaxy:
        _spiral(canvas, _center, 1, -.35, line, light);
      case CatalogSymbolKind.galaxyGroup:
        _spiral(canvas, const Offset(18, 17), .56, -.45, line, light);
        _spiral(canvas, const Offset(34, 28), .44, .5, line, light);
        _spiral(canvas, const Offset(17, 35), .35, .3, line, light);
      case CatalogSymbolKind.emissionNebula:
        final cloud = _cloud();
        canvas.drawPath(cloud, soft);
        draw(cloud);
        star(23, 24, 5);
        draw(
          Path()
            ..moveTo(10, 28)
            ..quadraticBezierTo(16, 34, 29, 30),
        );
        dot(32, 19);
      case CatalogSymbolKind.reflectionNebula:
        final cloud = _cloud();
        canvas.drawPath(cloud, soft);
        draw(
          Path()
            ..moveTo(8, 30)
            ..cubicTo(9, 11, 33, 7, 41, 21),
        );
        draw(
          Path()
            ..moveTo(13, 33)
            ..cubicTo(16, 19, 29, 15, 36, 20),
        );
        draw(
          Path()
            ..moveTo(18, 36)
            ..quadraticBezierTo(23, 24, 32, 24),
        );
        star(34, 30, 6);
      case CatalogSymbolKind.darkNebula:
        final cloud = _cloud();
        canvas.drawPath(cloud, soft);
        draw(cloud);
        canvas.drawPath(
          Path()
            ..moveTo(12, 33)
            ..cubicTo(31, 32, 14, 21, 36, 16),
          Paint()
            ..color = PcDesign.background
            ..style = PaintingStyle.stroke
            ..strokeWidth = 6
            ..strokeCap = StrokeCap.round,
        );
        dot(14, 19);
        dot(34, 28);
      case CatalogSymbolKind.planetaryNebula:
        canvas.drawOval(
          Rect.fromCenter(center: _center, width: 33, height: 28),
          soft,
        );
        canvas.drawOval(
          Rect.fromCenter(center: _center, width: 33, height: 28),
          line,
        );
        canvas.drawOval(
          Rect.fromCenter(center: _center, width: 23, height: 18),
          line,
        );
        star(24, 24, 5);
      case CatalogSymbolKind.openCluster:
        star(10, 18, 4);
        star(27, 10, 4.5);
        star(33, 32, 5);
        star(16, 36, 3.5);
        field(const [
          (22, 23, 2.1),
          (38, 20, 1.5),
          (11, 29, 1.35),
          (26, 38, 1),
        ]);
      case CatalogSymbolKind.globularCluster:
        canvas.drawCircle(_center, 16, soft);
        for (var i = 0; i < 38; i++) {
          final r = 16 * math.pow(i / 38, 1.15);
          dot(
            24 + r * math.cos(i * 2.4),
            24 + r * math.sin(i * 2.4),
            i < 9 ? 1.35 : .82,
          );
        }
      case CatalogSymbolKind.supernovaRemnant:
        draw(
          Path()
            ..moveTo(8, 28)
            ..cubicTo(16, 25, 9, 13, 23, 11)
            ..quadraticBezierTo(28, 6, 37, 12),
        );
        draw(
          Path()
            ..moveTo(11, 36)
            ..quadraticBezierTo(16, 39, 23, 33)
            ..cubicTo(27, 19, 36, 31, 41, 19),
        );
        draw(
          Path()
            ..moveTo(18, 31)
            ..cubicTo(23, 32, 20, 17, 31, 16),
        );
        draw(
          Path()
            ..moveTo(28, 37)
            ..cubicTo(34, 38, 40, 33, 41, 28),
        );
        field(const [(9, 19, 1), (35, 7, 1.2), (23, 41, 1.35), (42, 15, 1)]);
      case CatalogSymbolKind.complexNebula:
        for (final (dx, dy) in const [(-5.0, 4.0), (6.0, -6.0)]) {
          canvas.save();
          canvas.translate(dx, dy);
          canvas.scale(.87);
          canvas.drawPath(_cloud(), soft);
          draw(_cloud());
          canvas.restore();
        }
        dot(14, 25);
        dot(30, 18);
      case CatalogSymbolKind.nebulaWithCluster:
        canvas.drawPath(_cloud(), soft);
        draw(_cloud());
        star(20, 20, 4);
        star(30, 26, 3.5);
        field(const [(15, 27, 1.2), (26, 19, 1.2), (23, 30, 1), (29, 15, 1)]);
      case CatalogSymbolKind.starCloud:
        canvas.drawPath(_cloud(), soft);
        field(const [
          (9, 24, 1),
          (13, 18, 1.2),
          (14, 30, 1),
          (16, 23, 1.6),
          (19, 15, 1),
          (20, 25, 1.1),
          (21, 32, 1.15),
          (24, 22, 1.4),
          (26, 30, 1.3),
          (29, 17, 1),
          (30, 24, 1.4),
          (32, 32, 1),
          (34, 22, 1),
          (38, 27, 1),
        ]);
      case CatalogSymbolKind.milkyWay:
        final band = Path()
          ..moveTo(5, 39)
          ..cubicTo(18, 38, 13, 18, 41, 8);
        canvas.drawPath(
          band,
          Paint()
            ..color = soft.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 9
            ..strokeCap = StrokeCap.round,
        );
        draw(band);
        star(16, 28, 3.5);
        star(31, 14, 3);
        field(const [(8, 35, 1.2), (21, 29, 1.2), (22, 18, 1), (38, 11, 1.3)]);
      case CatalogSymbolKind.doubleStar:
        canvas.save();
        canvas.translate(24, 24);
        canvas.rotate(-.5);
        canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: 36, height: 16),
          line,
        );
        canvas.restore();
        star(14, 24, 7);
        star(33, 20, 5);
      case CatalogSymbolKind.star:
        star(24, 24, 14);
        dot(36, 13, 1.1);
      case CatalogSymbolKind.planet:
        canvas.drawCircle(_center, 12, soft);
        canvas.drawCircle(_center, 12, line);
        draw(
          Path()
            ..moveTo(12, 22)
            ..quadraticBezierTo(23, 27, 35, 21),
        );
        draw(
          Path()
            ..moveTo(14, 28)
            ..quadraticBezierTo(23, 32, 32, 28),
        );
        draw(
          Path()
            ..moveTo(12, 24)
            ..cubicTo(-1, 32, 5, 38, 23, 32)
            ..cubicTo(39, 26, 48, 16, 35, 18),
        );
      case CatalogSymbolKind.moon:
        final crescent = Path()
          ..moveTo(31, 9)
          ..cubicTo(12, 4, 6, 28, 18, 36)
          ..quadraticBezierTo(30, 44, 39, 30)
          ..cubicTo(23, 34, 19, 18, 31, 9)
          ..close();
        canvas.drawPath(crescent, soft);
        draw(crescent);
        dot(33, 16);
        dot(37, 21, .9);
      case CatalogSymbolKind.dwarfPlanet:
        canvas.drawCircle(const Offset(21, 27), 10, soft);
        canvas.drawCircle(const Offset(21, 27), 10, line);
        draw(
          Path()
            ..moveTo(14, 22)
            ..quadraticBezierTo(21, 17, 26, 24)
            ..quadraticBezierTo(25, 32, 17, 34),
        );
        dot(36, 15, 2);
      case CatalogSymbolKind.sun:
        canvas.drawCircle(_center, 10, soft);
        canvas.drawCircle(_center, 10, line);
        for (var i = 0; i < 12; i++) {
          final a = i * math.pi / 6;
          final axis = Offset(math.cos(a), math.sin(a));
          canvas.drawLine(
            _center + axis * 14,
            _center + axis * (i.isEven ? 20 : 17),
            line,
          );
        }
      case CatalogSymbolKind.comet:
        draw(
          Path()
            ..moveTo(36, 13)
            ..quadraticBezierTo(19, 14, 12, 31)
            ..quadraticBezierTo(19, 41, 41, 22),
        );
        draw(
          Path()
            ..moveTo(31, 18)
            ..quadraticBezierTo(23, 22, 19, 28),
        );
        canvas.drawCircle(const Offset(15, 33), 3.2, light);
      case CatalogSymbolKind.unknown:
        canvas.drawArc(
          Rect.fromCircle(center: _center, radius: 13),
          .7,
          2.4,
          false,
          line,
        );
        canvas.drawArc(
          Rect.fromCircle(center: _center, radius: 13),
          3.8,
          2.4,
          false,
          line,
        );
        star(24, 24, 5);
    }
    canvas.restore();
  }

  static Path _cloud() => Path()
    ..moveTo(7, 28)
    ..cubicTo(4, 20, 16, 21, 14, 15)
    ..cubicTo(16, 7, 25, 11, 27, 15)
    ..cubicTo(39, 10, 41, 20, 38, 24)
    ..cubicTo(48, 31, 31, 33, 29, 34)
    ..cubicTo(20, 40, 15, 34, 10, 32)
    ..quadraticBezierTo(6, 32, 7, 28)
    ..close();

  static Path _star(Offset center, double radius) => Path()
    ..moveTo(center.dx, center.dy - radius)
    ..quadraticBezierTo(
      center.dx + radius * .18,
      center.dy - radius * .17,
      center.dx + radius,
      center.dy,
    )
    ..quadraticBezierTo(
      center.dx + radius * .18,
      center.dy + radius * .17,
      center.dx,
      center.dy + radius,
    )
    ..quadraticBezierTo(
      center.dx - radius * .18,
      center.dy + radius * .17,
      center.dx - radius,
      center.dy,
    )
    ..quadraticBezierTo(
      center.dx - radius * .18,
      center.dy - radius * .17,
      center.dx,
      center.dy - radius,
    )
    ..close();

  static void _spiral(
    Canvas canvas,
    Offset center,
    double scale,
    double rotation,
    Paint line,
    Paint core,
  ) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);
    for (final phase in [0.0, math.pi]) {
      final arm = Path();
      for (var i = 0; i <= 22; i++) {
        final t = i / 22;
        final angle = phase + 3.35 * t;
        final r = scale * (2 + 18 * t);
        final x = r * math.cos(angle);
        final y = .77 * r * math.sin(angle);
        if (i == 0) {
          arm.moveTo(x, y);
        } else {
          arm.lineTo(x, y);
        }
      }
      canvas.drawPath(arm, line);
    }
    canvas.drawCircle(Offset.zero, 2.5 * scale, core);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CatalogSymbolPainter oldDelegate) =>
      oldDelegate.kind != kind;
}

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../services/sky_map_horizontal_projection_service.dart';
import '../sky_map_visual_style.dart';

/// 관측자 수평 좌표계 배경: 차분한 밤하늘 + Alt/Az 곡선 격자.
class SkyMapBackgroundPainter extends CustomPainter {
  const SkyMapBackgroundPainter({
    required this.centerAltitudeDeg,
    required this.centerAzimuthDeg,
    required this.viewHeightDeg,
    required this.sunAltitudeDeg,
    required this.sunAzimuthDeg,
    this.occupiedLabels,
  });

  final double centerAltitudeDeg;
  final double centerAzimuthDeg;
  final double viewHeightDeg;
  final double sunAltitudeDeg;
  final double sunAzimuthDeg;
  final List<Rect>? occupiedLabels;

  @visibleForTesting
  static double gridIntervalFor(double viewHeightDeg) =>
      SkyMapVisualStyle.gridIntervalFor(viewHeightDeg);

  @visibleForTesting
  static const double cardinalFontSize = 20;

  @visibleForTesting
  static const Color cardinalLabelColor = Color(0xFFFFF8E7);

  @override
  void paint(Canvas canvas, Size size) {
    paintAtmosphereLayer(canvas, size);
    paintCoordinateLayer(canvas, size);
  }

  /// 대기·지면 배경. 은하수는 이 레이어 뒤가 아니라 바로 위에 합성한다.
  void paintAtmosphereLayer(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final centerColor = SkyMapVisualStyle.atmosphericColorFor(
      altitudeDeg: centerAltitudeDeg,
      azimuthDeg: centerAzimuthDeg,
      sunAltitudeDeg: sunAltitudeDeg,
      sunAzimuthDeg: sunAzimuthDeg,
    );
    canvas.drawRect(rect, Paint()..color = centerColor);
    _drawAtmosphere(canvas, size);
  }

  /// Alt/Az 격자, 지평선, 눈금과 방위 라벨.
  void paintCoordinateLayer(Canvas canvas, Size size) {
    final altitudeGrid = Paint()
      ..color = SkyMapVisualStyle.gridColorFor(
        sunAltitudeDeg,
      ).withValues(alpha: 0.64)
      ..strokeWidth = 1.05
      ..style = PaintingStyle.stroke;
    final majorAltitudeGrid = Paint()
      ..color = SkyMapVisualStyle.gridColorFor(
        sunAltitudeDeg,
      ).withValues(alpha: 0.78)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final azimuthGrid = Paint()
      ..color = SkyMapVisualStyle.azimuthGridColorFor(
        sunAltitudeDeg,
      ).withValues(alpha: 0.58)
      ..strokeWidth = 0.9
      ..style = PaintingStyle.stroke;
    final belowGrid = Paint()
      ..color = SkyMapVisualStyle.coordinateColorFor(
        sunAltitudeDeg,
      ).withValues(alpha: 0.22)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;
    final horizonPaint = Paint()
      ..color = const Color(0xFFBAC9D9).withValues(alpha: 0.92)
      ..strokeWidth = 1.65
      ..style = PaintingStyle.stroke;

    final interval = gridIntervalFor(viewHeightDeg);
    for (var altitude = -90.0 + interval; altitude < 90; altitude += interval) {
      final points = <Offset>[];
      for (var azimuth = 0.0; azimuth <= 360; azimuth += _sampleStep) {
        points.add(_project(altitude, azimuth, size));
      }
      _drawSampledCurve(
        canvas,
        size,
        points,
        altitude == 0
            ? horizonPaint
            : altitude < 0
            ? belowGrid
            : (_isMajorTick(altitude) ? majorAltitudeGrid : altitudeGrid),
      );
    }

    for (var azimuth = 0.0; azimuth < 360; azimuth += interval) {
      final belowPoints = <Offset>[];
      for (var altitude = -90.0; altitude <= 0; altitude += _sampleStep) {
        belowPoints.add(_project(altitude, azimuth, size));
      }
      _drawSampledCurve(canvas, size, belowPoints, belowGrid);

      final skyPoints = <Offset>[];
      for (var altitude = 0.0; altitude <= 90; altitude += _sampleStep) {
        skyPoints.add(_project(altitude, azimuth, size));
      }
      _drawSampledCurve(canvas, size, skyPoints, azimuthGrid);
    }

    _drawCoordinateLabels(canvas, size, interval);
    _drawZenith(canvas, size);
  }

  double get _sampleStep => viewHeightDeg <= 45 ? 1 : 2;

  bool _isMajorTick(double value, {double majorInterval = 30}) =>
      (value % majorInterval).abs() < 0.001;

  void _drawAtmosphere(Canvas canvas, Size size) {
    const azimuthStep = 7.5;
    const altitudeBoundaries = <double>[
      -89.5,
      -80,
      -70,
      -60,
      -50,
      -40,
      -30,
      -20,
      -10,
      0,
      10,
      20,
      30,
      40,
      50,
      60,
      70,
      80,
      89.5,
    ];
    final expandedBounds = (Offset.zero & size).inflate(size.longestSide * 0.2);
    final positions = <Offset>[];
    final colors = <Color>[];
    for (var band = 0; band < altitudeBoundaries.length - 1; band++) {
      final lower = altitudeBoundaries[band];
      final upper = altitudeBoundaries[band + 1];
      for (var azimuth = 0.0; azimuth < 360; azimuth += azimuthStep) {
        final nextAzimuth = azimuth + azimuthStep;
        final points = <Offset>[
          _project(lower, azimuth, size),
          _project(lower, nextAzimuth, size),
          _project(upper, nextAzimuth, size),
          _project(upper, azimuth, size),
        ];
        final bounds = _boundsFor(points);
        if (!expandedBounds.overlaps(bounds)) continue;
        if (_largestEdge(points) > size.longestSide * 2.5) continue;
        final cellColors = <Color>[
          _atmosphericColor(lower, azimuth),
          _atmosphericColor(lower, nextAzimuth),
          _atmosphericColor(upper, nextAzimuth),
          _atmosphericColor(upper, azimuth),
        ];
        positions.addAll([
          points[0],
          points[1],
          points[2],
          points[0],
          points[2],
          points[3],
        ]);
        colors.addAll([
          cellColors[0],
          cellColors[1],
          cellColors[2],
          cellColors[0],
          cellColors[2],
          cellColors[3],
        ]);
      }
    }
    if (positions.isEmpty) return;
    final vertices = ui.Vertices(
      ui.VertexMode.triangles,
      positions,
      colors: colors,
    );
    canvas.drawVertices(
      vertices,
      BlendMode.modulate,
      Paint()..color = Colors.white,
    );
    vertices.dispose();
  }

  Color _atmosphericColor(double altitude, double azimuth) =>
      SkyMapVisualStyle.atmosphericColorFor(
        altitudeDeg: altitude,
        azimuthDeg: azimuth,
        sunAltitudeDeg: sunAltitudeDeg,
        sunAzimuthDeg: sunAzimuthDeg,
      );

  Rect _boundsFor(List<Offset> points) {
    var left = points.first.dx;
    var top = points.first.dy;
    var right = left;
    var bottom = top;
    for (final point in points.skip(1)) {
      left = left < point.dx ? left : point.dx;
      top = top < point.dy ? top : point.dy;
      right = right > point.dx ? right : point.dx;
      bottom = bottom > point.dy ? bottom : point.dy;
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  double _largestEdge(List<Offset> points) {
    var largest = 0.0;
    for (var i = 0; i < points.length; i++) {
      final edge = (points[i] - points[(i + 1) % points.length]).distance;
      if (edge > largest) largest = edge;
    }
    return largest;
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
    _label(
      canvas,
      '90°',
      zenith + const Offset(0, 15),
      size,
      fontSize: 12,
      altitudeDeg: 90,
      azimuthDeg: 0,
    );
  }

  void _drawCoordinateLabels(Canvas canvas, Size size, double interval) {
    for (final cardinal in cardinalLabels) {
      final placement = _azimuthLabelPlacement(cardinal.azimuth, size);
      if (placement == null) continue;
      if (placement.auxiliary) {
        _drawBoundaryTick(canvas, placement.boundaryPoint!, size);
      }
      _label(
        canvas,
        cardinal.label,
        placement.position,
        size,
        cardinal: true,
        force: true,
        auxiliary: placement.auxiliary,
        altitudeDeg: placement.altitudeDeg,
        azimuthDeg: cardinal.azimuth,
      );
    }

    final altitudeLabelAzimuth =
        (centerAzimuthDeg / interval).round() * interval;
    final altitudes = <double>[
      for (var altitude = -90.0 + interval; altitude < 90; altitude += interval)
        altitude,
    ];
    final majorAltitudes = altitudes.where(
      (altitude) => altitude == 0 || _isMajorTick(altitude),
    );
    for (final altitude in majorAltitudes) {
      _label(
        canvas,
        '${altitude.round()}°',
        _altitudeLabelPosition(altitude, altitudeLabelAzimuth, size),
        size,
        fontSize: 12,
        altitudeDeg: altitude,
        azimuthDeg: altitudeLabelAzimuth,
      );
    }

    for (var azimuth = 0.0; azimuth < 360; azimuth += interval) {
      if (_isMajorTick(azimuth, majorInterval: 90)) continue;
      final placement = _azimuthLabelPlacement(azimuth, size);
      if (placement == null) continue;
      if (placement.auxiliary) {
        _drawBoundaryTick(canvas, placement.boundaryPoint!, size);
      }
      _label(
        canvas,
        '${azimuth.round()}°',
        placement.position,
        size,
        auxiliary: placement.auxiliary,
        altitudeDeg: placement.altitudeDeg,
        azimuthDeg: azimuth,
      );
    }

    for (final altitude in altitudes.where(
      (altitude) => altitude != 0 && !_isMajorTick(altitude),
    )) {
      _label(
        canvas,
        '${altitude.round()}°',
        _altitudeLabelPosition(altitude, altitudeLabelAzimuth, size),
        size,
        altitudeDeg: altitude,
        azimuthDeg: altitudeLabelAzimuth,
      );
    }
  }

  @visibleForTesting
  static const cardinalLabels = [
    (azimuth: 0.0, label: '북'),
    (azimuth: 90.0, label: '동'),
    (azimuth: 180.0, label: '남'),
    (azimuth: 270.0, label: '서'),
  ];

  @visibleForTesting
  Offset debugAltitudeLabelPosition(
    double altitudeDeg,
    double interval,
    Size size,
  ) {
    final azimuth = (centerAzimuthDeg / interval).round() * interval;
    return _altitudeLabelPosition(altitudeDeg, azimuth, size);
  }

  Offset _altitudeLabelPosition(
    double altitudeDeg,
    double azimuthDeg,
    Size size,
  ) => _project(altitudeDeg, azimuthDeg, size);

  @visibleForTesting
  ({Offset position, double altitudeDeg, bool auxiliary})?
  debugAzimuthLabelPlacement(double azimuthDeg, Size size) {
    final placement = _azimuthLabelPlacement(azimuthDeg, size);
    if (placement == null) return null;
    return (
      position: placement.position,
      altitudeDeg: placement.altitudeDeg,
      auxiliary: placement.auxiliary,
    );
  }

  ({
    Offset position,
    Offset? boundaryPoint,
    double altitudeDeg,
    bool auxiliary,
  })?
  _azimuthLabelPlacement(double azimuthDeg, Size size) {
    final canvasRect = Offset.zero & size;
    final horizon = _project(0, azimuthDeg, size);
    if (canvasRect.inflate(0.5).contains(horizon)) {
      final above = _project(2, azimuthDeg, size);
      final below = _project(-2, azimuthDeg, size);
      final center = canvasRect.center;
      final candidates = [
        above,
        below,
      ].where(canvasRect.inflate(-2).contains).toList(growable: false);
      var position = horizon;
      var labelAltitude = 0.0;
      if (candidates.isNotEmpty) {
        position = candidates.reduce(
          (a, b) => (a - center).distance <= (b - center).distance ? a : b,
        );
        labelAltitude = position == below ? -2 : 2;
      }
      return (
        position: position,
        boundaryPoint: null,
        altitudeDeg: labelAltitude,
        auxiliary: false,
      );
    }

    final boundary = _meridianBoundaryIntersection(azimuthDeg, size);
    if (boundary == null) return null;
    return (
      position: _moveInside(boundary.point, size, 13),
      boundaryPoint: boundary.point,
      altitudeDeg: boundary.altitudeDeg,
      auxiliary: true,
    );
  }

  ({Offset point, double altitudeDeg})? _meridianBoundaryIntersection(
    double azimuthDeg,
    Size size,
  ) {
    final rect = Offset.zero & size;
    final candidates = <({Offset point, double altitudeDeg})>[];
    var previousAltitude = -89.0;
    var previous = _project(previousAltitude, azimuthDeg, size);
    for (var altitude = -87.0; altitude <= 89; altitude += 2) {
      final current = _project(altitude, azimuthDeg, size);
      for (final crossing in _segmentBoundaryIntersections(
        previous,
        current,
        rect,
      )) {
        candidates.add((
          point: crossing.point,
          altitudeDeg:
              previousAltitude +
              (altitude - previousAltitude) * crossing.fraction,
        ));
      }
      previousAltitude = altitude;
      previous = current;
    }
    if (candidates.isEmpty) return null;
    candidates.sort(
      (a, b) => a.altitudeDeg.abs().compareTo(b.altitudeDeg.abs()),
    );
    return candidates.first;
  }

  List<({Offset point, double fraction})> _segmentBoundaryIntersections(
    Offset start,
    Offset end,
    Rect rect,
  ) {
    final result = <({Offset point, double fraction})>[];
    final delta = end - start;

    void addForFraction(double fraction) {
      if (fraction < 0 || fraction > 1) return;
      final point = start + delta * fraction;
      if (point.dx < rect.left - 0.01 ||
          point.dx > rect.right + 0.01 ||
          point.dy < rect.top - 0.01 ||
          point.dy > rect.bottom + 0.01) {
        return;
      }
      if (result.any((item) => (item.point - point).distance < 0.1)) return;
      result.add((point: point, fraction: fraction));
    }

    if (delta.dx.abs() > 1e-9) {
      addForFraction((rect.left - start.dx) / delta.dx);
      addForFraction((rect.right - start.dx) / delta.dx);
    }
    if (delta.dy.abs() > 1e-9) {
      addForFraction((rect.top - start.dy) / delta.dy);
      addForFraction((rect.bottom - start.dy) / delta.dy);
    }
    return result;
  }

  Offset _moveInside(Offset boundary, Size size, double distance) {
    var dx = boundary.dx;
    var dy = boundary.dy;
    if ((boundary.dx - 0).abs() < 0.5) dx += distance;
    if ((boundary.dx - size.width).abs() < 0.5) dx -= distance;
    if ((boundary.dy - 0).abs() < 0.5) dy += distance;
    if ((boundary.dy - size.height).abs() < 0.5) dy -= distance;
    return Offset(dx, dy);
  }

  void _drawBoundaryTick(Canvas canvas, Offset boundary, Size size) {
    final inside = _moveInside(boundary, size, 7);
    canvas.drawLine(
      boundary,
      inside,
      Paint()
        ..color = SkyMapVisualStyle.coordinateColorFor(
          sunAltitudeDeg,
        ).withValues(alpha: 0.62)
        ..strokeWidth = 1,
    );
  }

  void _label(
    Canvas canvas,
    String text,
    Offset center,
    Size size, {
    bool cardinal = false,
    bool force = false,
    bool auxiliary = false,
    double fontSize = 11,
    double altitudeDeg = 0,
    double azimuthDeg = 0,
  }) {
    final coordinateColor = SkyMapVisualStyle.coordinateColorFor(
      sunAltitudeDeg,
    );
    final effectiveFontSize = cardinal
        ? cardinalFontSize
        : (auxiliary ? fontSize - 1 : fontSize);
    final style = TextStyle(
      color: cardinal
          ? cardinalLabelColor
          : coordinateColor.withValues(
              alpha: auxiliary ? 0.76 : (altitudeDeg < 0 ? 0.72 : 0.9),
            ),
      fontSize: effectiveFontSize,
      fontWeight: cardinal ? FontWeight.w900 : FontWeight.w500,
      letterSpacing: cardinal ? 1 : 0.1,
      shadows: const [Shadow(color: Color(0xF0000000), blurRadius: 5)],
    );
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final outlinePainter = cardinal
        ? (TextPainter(
            text: TextSpan(
              text: text,
              style: TextStyle(
                foreground: Paint()
                  ..color = const Color(0xE6000000)
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 3,
                fontSize: effectiveFontSize,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout())
        : null;
    final canvasRect = Offset.zero & size;
    if (!canvasRect.inflate(cardinal ? 20 : -3).contains(center)) return;
    final safeCenter = cardinal
        ? Offset(
            center.dx.clamp(
              painter.width / 2 + 5,
              size.width - painter.width / 2 - 5,
            ),
            center.dy.clamp(
              painter.height / 2 + 5,
              size.height - painter.height / 2 - 5,
            ),
          )
        : center;
    final labelBounds = Rect.fromCenter(
      center: safeCenter,
      width: painter.width + (cardinal ? 8 : 4),
      height: painter.height + (cardinal ? 4 : 2),
    );
    if (!force &&
        occupiedLabels?.any((bounds) => bounds.overlaps(labelBounds)) == true) {
      return;
    }
    final background = RRect.fromRectAndRadius(
      labelBounds,
      Radius.circular(cardinal ? 5 : 3),
    );
    canvas.drawRRect(
      background,
      Paint()
        ..color = cardinal
            ? const Color(0xAA06101B)
            : _atmosphericColor(
                altitudeDeg,
                azimuthDeg,
              ).withValues(alpha: auxiliary ? 0.62 : 0.76),
    );
    final textOffset =
        safeCenter - Offset(painter.width / 2, painter.height / 2);
    outlinePainter?.paint(canvas, textOffset);
    painter.paint(canvas, textOffset);
    occupiedLabels?.add(labelBounds.inflate(2));
  }

  @override
  bool shouldRepaint(covariant SkyMapBackgroundPainter oldDelegate) =>
      oldDelegate.centerAltitudeDeg != centerAltitudeDeg ||
      oldDelegate.centerAzimuthDeg != centerAzimuthDeg ||
      oldDelegate.viewHeightDeg != viewHeightDeg ||
      oldDelegate.sunAltitudeDeg != sunAltitudeDeg ||
      oldDelegate.sunAzimuthDeg != sunAzimuthDeg;
}

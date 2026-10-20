import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../services/sky_map_horizontal_projection_service.dart';
import '../../../../services/sky_map_milky_way_service.dart';

/// 실제 가시광 전천 텍스처를 기존 Alt/Az 투영 위에 그린다.
class MilkyWayPainter extends CustomPainter {
  const MilkyWayPainter({
    required this.mesh,
    required this.centerAltitudeDeg,
    required this.centerAzimuthDeg,
    required this.viewHeightDeg,
    required this.sunAltitudeDeg,
  });

  final SkyMapMilkyWayHorizontalMesh mesh;
  final double centerAltitudeDeg;
  final double centerAzimuthDeg;
  final double viewHeightDeg;
  final double sunAltitudeDeg;

  @visibleForTesting
  static double daylightVisibility(double sunAltitudeDeg) {
    if (sunAltitudeDeg >= -6) return 0;
    if (sunAltitudeDeg < -18) return 1;
    if (sunAltitudeDeg < -12) {
      return _smoothStep(-18, -12, sunAltitudeDeg, 1, 0.34);
    }
    return _smoothStep(-12, -6, sunAltitudeDeg, 0.34, 0);
  }

  @visibleForTesting
  static double horizonVisibility(double altitudeDeg) {
    if (altitudeDeg >= 2) return 1;
    if (altitudeDeg <= -18) return 0;
    final t = ((altitudeDeg + 18) / 20).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  static double _smoothStep(
    double edge0,
    double edge1,
    double value,
    double begin,
    double end,
  ) {
    final t = ((value - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
    final smooth = t * t * (3 - 2 * t);
    return begin + (end - begin) * smooth;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final skyVisibility = daylightVisibility(sunAltitudeDeg);
    final image = mesh.image;
    if (skyVisibility <= 0 || mesh.isEmpty || image == null) return;

    final longitudeCount = mesh.longitudeCount;
    final latitudeCount = mesh.latitudeCount;
    if (longitudeCount < 2 || latitudeCount < 2) return;

    final projected = List<Offset>.generate(mesh.coordinates.length, (index) {
      final coordinate = mesh.coordinates[index];
      return SkyMapHorizontalProjectionService.project(
        altitudeDeg: coordinate.altitude,
        azimuthDeg: coordinate.azimuth,
        centerAltitudeDeg: centerAltitudeDeg,
        centerAzimuthDeg: centerAzimuthDeg,
        canvasSize: size,
        viewHeightDeg: viewHeightDeg,
      ).pixel;
    }, growable: false);
    final vertexColors = List<Color>.generate(mesh.coordinates.length, (index) {
      final altitudeVisibility = horizonVisibility(
        mesh.coordinates[index].altitude,
      );
      return Colors.white.withValues(
        alpha: (0.38 * skyVisibility * altitudeVisibility).clamp(0, 1),
      );
    }, growable: false);

    final positions = <Offset>[];
    final textureCoordinates = <Offset>[];
    final colors = <Color>[];
    final viewport = (Offset.zero & size).inflate(36);
    final maxEdge = size.longestSide * 0.42;
    for (var row = 0; row < latitudeCount - 1; row++) {
      for (var column = 0; column < longitudeCount - 1; column++) {
        final a = row * longitudeCount + column;
        final b = a + 1;
        final d = (row + 1) * longitudeCount + column;
        final c = d + 1;
        final cell = <Offset>[
          projected[a],
          projected[b],
          projected[c],
          projected[d],
        ];
        if (!_cellNearViewport(cell, viewport)) continue;
        if (_largestEdge(cell) > maxEdge) continue;
        if (vertexColors[a].a == 0 &&
            vertexColors[b].a == 0 &&
            vertexColors[c].a == 0 &&
            vertexColors[d].a == 0) {
          continue;
        }
        positions.addAll([
          cell[0],
          cell[1],
          cell[2],
          cell[0],
          cell[2],
          cell[3],
        ]);
        textureCoordinates.addAll([
          mesh.textureCoordinates[a],
          mesh.textureCoordinates[b],
          mesh.textureCoordinates[c],
          mesh.textureCoordinates[a],
          mesh.textureCoordinates[c],
          mesh.textureCoordinates[d],
        ]);
        colors.addAll([
          vertexColors[a],
          vertexColors[b],
          vertexColors[c],
          vertexColors[a],
          vertexColors[c],
          vertexColors[d],
        ]);
      }
    }
    if (positions.isEmpty) return;

    final vertices = ui.Vertices(
      ui.VertexMode.triangles,
      positions,
      textureCoordinates: textureCoordinates,
      colors: colors,
    );
    final shader = ui.ImageShader(
      image,
      ui.TileMode.clamp,
      ui.TileMode.clamp,
      Matrix4.identity().storage,
      filterQuality: FilterQuality.medium,
    );
    canvas.drawVertices(vertices, BlendMode.modulate, Paint()..shader = shader);
    shader.dispose();
    vertices.dispose();
  }

  bool _cellNearViewport(List<Offset> points, Rect viewport) {
    if (points.any(viewport.contains)) return true;
    var left = points.first.dx;
    var right = left;
    var top = points.first.dy;
    var bottom = top;
    for (final point in points.skip(1)) {
      left = math.min(left, point.dx);
      right = math.max(right, point.dx);
      top = math.min(top, point.dy);
      bottom = math.max(bottom, point.dy);
    }
    return viewport.overlaps(Rect.fromLTRB(left, top, right, bottom));
  }

  double _largestEdge(List<Offset> points) {
    var largest = 0.0;
    for (var index = 0; index < points.length; index++) {
      largest = math.max(
        largest,
        (points[index] - points[(index + 1) % points.length]).distance,
      );
    }
    return largest;
  }

  @override
  bool shouldRepaint(covariant MilkyWayPainter oldDelegate) =>
      oldDelegate.mesh != mesh ||
      oldDelegate.centerAltitudeDeg != centerAltitudeDeg ||
      oldDelegate.centerAzimuthDeg != centerAzimuthDeg ||
      oldDelegate.viewHeightDeg != viewHeightDeg ||
      oldDelegate.sunAltitudeDeg != sunAltitudeDeg;
}

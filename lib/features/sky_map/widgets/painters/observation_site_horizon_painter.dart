import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../data/models/site_horizon_profile.dart';
import '../../../../services/horizon_visibility_service.dart';
import '../../../../services/sky_map_horizontal_projection_service.dart';

/// 등록 관측지의 물리적 시야 제한을 실제 Alt/Az 좌표에 고정해 그린다.
///
/// 음영은 천체 레이어 아래에 합성되므로 가려진 천체도 계속 검색하고
/// 선택할 수 있다. 추천/스케줄과 동일한 [HorizonVisibilityService] 보간
/// 계약을 사용하며 별도의 시야값을 만들지 않는다.
class ObservationSiteHorizonPainter extends CustomPainter {
  const ObservationSiteHorizonPainter({
    required this.profile,
    required this.centerAltitudeDeg,
    required this.centerAzimuthDeg,
    required this.viewHeightDeg,
  });

  final SiteHorizonProfile profile;
  final double centerAltitudeDeg;
  final double centerAzimuthDeg;
  final double viewHeightDeg;

  static const maskColor = Color(0x8A020711);
  static const boundaryColor = Color(0xD99AB7C7);
  static const double _azimuthStepDeg = 2;
  static const double _altitudeStepDeg = 3;
  static const HorizonVisibilityService _visibilityService =
      HorizonVisibilityService();
  static _HorizonGeometry? _cachedGeometry;

  @visibleForTesting
  bool isMasked({required double azimuthDeg, required double altitudeDeg}) {
    if (!profile.hasRestrictions || altitudeDeg < 0 || altitudeDeg > 90) {
      return false;
    }
    return !_visibilityService.isVisible(
      profile: profile,
      azimuth: azimuthDeg,
      altitude: altitudeDeg,
    );
  }

  @visibleForTesting
  Offset projectBoundaryPoint({
    required double azimuthDeg,
    required double altitudeDeg,
    required Size size,
  }) => _project(altitudeDeg, azimuthDeg, size);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || !profile.hasRestrictions) return;

    final geometry = _geometryFor(size);
    canvas.drawPath(geometry.mask, Paint()..color = maskColor);
    canvas.drawPath(
      geometry.boundary,
      Paint()
        ..color = boundaryColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.35
        ..strokeJoin = StrokeJoin.round,
    );
  }

  _HorizonGeometry _geometryFor(Size size) {
    final cached = _cachedGeometry;
    if (cached != null &&
        cached.matches(
          profile: profile,
          centerAltitudeDeg: centerAltitudeDeg,
          centerAzimuthDeg: centerAzimuthDeg,
          viewHeightDeg: viewHeightDeg,
          size: size,
        )) {
      return cached;
    }

    final mask = Path();
    if (profile.points.isNotEmpty) {
      _appendProfileMask(mask, size);
    }
    for (final range in profile.blockedRanges) {
      for (final span in _normalizedSpans(
        range.startAzimuth,
        range.endAzimuth,
      )) {
        _appendAzimuthBand(
          mask,
          size,
          startAzimuth: span.$1,
          endAzimuth: span.$2,
          lowerAltitude: (_) => 0,
          upperAltitude: (_) => 90,
        );
      }
    }
    final boundary = Path();
    if (profile.points.isNotEmpty) {
      _appendProfileBoundaries(boundary, size);
    }
    for (final range in profile.blockedRanges) {
      _appendMeridian(boundary, size, range.startAzimuth);
      _appendMeridian(boundary, size, range.endAzimuth);
    }
    return _cachedGeometry = _HorizonGeometry(
      profile: profile,
      centerAltitudeDeg: centerAltitudeDeg,
      centerAzimuthDeg: centerAzimuthDeg,
      viewHeightDeg: viewHeightDeg,
      size: size,
      mask: mask,
      boundary: boundary,
    );
  }

  void _appendProfileMask(Path path, Size size) {
    for (var azimuth = 0.0; azimuth < 360; azimuth += _azimuthStepDeg) {
      final nextAzimuth = math.min(360.0, azimuth + _azimuthStepDeg);
      final minStart = _visibilityService.minimumVisibleAltitude(
        profile,
        azimuth,
      );
      final minEnd = _visibilityService.minimumVisibleAltitude(
        profile,
        nextAzimuth,
      );
      if (minStart > 0 || minEnd > 0) {
        _appendStrip(
          path,
          size,
          startAzimuth: azimuth,
          endAzimuth: nextAzimuth,
          lowerStart: 0,
          lowerEnd: 0,
          upperStart: minStart,
          upperEnd: minEnd,
        );
      }

      final maxStart = _visibilityService.maximumVisibleAltitude(
        profile,
        azimuth,
      );
      final maxEnd = _visibilityService.maximumVisibleAltitude(
        profile,
        nextAzimuth,
      );
      if (maxStart < 90 || maxEnd < 90) {
        _appendStrip(
          path,
          size,
          startAzimuth: azimuth,
          endAzimuth: nextAzimuth,
          lowerStart: maxStart,
          lowerEnd: maxEnd,
          upperStart: 90,
          upperEnd: 90,
        );
      }
    }
  }

  void _appendAzimuthBand(
    Path path,
    Size size, {
    required double startAzimuth,
    required double endAzimuth,
    required double Function(double azimuth) lowerAltitude,
    required double Function(double azimuth) upperAltitude,
  }) {
    final span = endAzimuth - startAzimuth;
    if (span <= 0) return;
    final segmentCount = math.max(1, (span / _azimuthStepDeg).ceil());
    for (var index = 0; index < segmentCount; index++) {
      final start = startAzimuth + span * index / segmentCount;
      final end = startAzimuth + span * (index + 1) / segmentCount;
      _appendStrip(
        path,
        size,
        startAzimuth: start,
        endAzimuth: end,
        lowerStart: lowerAltitude(start),
        lowerEnd: lowerAltitude(end),
        upperStart: upperAltitude(start),
        upperEnd: upperAltitude(end),
      );
    }
  }

  void _appendStrip(
    Path path,
    Size size, {
    required double startAzimuth,
    required double endAzimuth,
    required double lowerStart,
    required double lowerEnd,
    required double upperStart,
    required double upperEnd,
  }) {
    final points = <Offset>[];
    _appendMeridianPoints(
      points,
      size,
      azimuth: startAzimuth,
      fromAltitude: lowerStart,
      toAltitude: upperStart,
    );
    _appendMeridianPoints(
      points,
      size,
      azimuth: endAzimuth,
      fromAltitude: upperEnd,
      toAltitude: lowerEnd,
    );
    if (points.length < 3 ||
        points.any((point) => !point.dx.isFinite || !point.dy.isFinite)) {
      return;
    }
    path.addPolygon(points, true);
  }

  void _appendMeridianPoints(
    List<Offset> points,
    Size size, {
    required double azimuth,
    required double fromAltitude,
    required double toAltitude,
  }) {
    final distance = (toAltitude - fromAltitude).abs();
    final count = math.max(1, (distance / _altitudeStepDeg).ceil());
    for (var index = 0; index <= count; index++) {
      final altitude =
          fromAltitude + (toAltitude - fromAltitude) * index / count;
      points.add(_project(altitude, azimuth, size));
    }
  }

  void _appendProfileBoundaries(Path path, Size size) {
    _appendAzimuthCurve(
      path,
      size,
      (azimuth) => _visibilityService.minimumVisibleAltitude(profile, azimuth),
    );
    final hasUpperBoundary = profile.points.any(
      (point) => (point.maxAltitude ?? 90) < 90,
    );
    if (hasUpperBoundary) {
      _appendAzimuthCurve(
        path,
        size,
        (azimuth) =>
            _visibilityService.maximumVisibleAltitude(profile, azimuth),
      );
    }
  }

  void _appendAzimuthCurve(
    Path path,
    Size size,
    double Function(double azimuth) altitudeFor,
  ) {
    var started = false;
    for (var azimuth = 0.0; azimuth <= 360; azimuth += _azimuthStepDeg) {
      final point = _project(altitudeFor(azimuth), azimuth, size);
      if (!point.dx.isFinite || !point.dy.isFinite) {
        started = false;
        continue;
      }
      if (!started) {
        path.moveTo(point.dx, point.dy);
        started = true;
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
  }

  void _appendMeridian(Path path, Size size, double azimuth) {
    final points = <Offset>[];
    _appendMeridianPoints(
      points,
      size,
      azimuth: azimuth,
      fromAltitude: 0,
      toAltitude: 90,
    );
    var started = false;
    for (final point in points) {
      if (!point.dx.isFinite || !point.dy.isFinite) {
        started = false;
        continue;
      }
      if (!started) {
        path.moveTo(point.dx, point.dy);
        started = true;
      } else {
        path.lineTo(point.dx, point.dy);
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

  List<(double, double)> _normalizedSpans(double start, double end) {
    final normalizedStart = SkyMapHorizontalProjectionService.normalizeAzimuth(
      start,
    );
    final normalizedEnd = SkyMapHorizontalProjectionService.normalizeAzimuth(
      end,
    );
    if ((normalizedStart - normalizedEnd).abs() < 1e-9) return const [];
    if (normalizedStart < normalizedEnd) {
      return [(normalizedStart, normalizedEnd)];
    }
    return [(normalizedStart, 360), (0, normalizedEnd)];
  }

  @override
  bool shouldRepaint(covariant ObservationSiteHorizonPainter oldDelegate) =>
      oldDelegate.profile.points != profile.points ||
      oldDelegate.profile.blockedRanges != profile.blockedRanges ||
      oldDelegate.centerAltitudeDeg != centerAltitudeDeg ||
      oldDelegate.centerAzimuthDeg != centerAzimuthDeg ||
      oldDelegate.viewHeightDeg != viewHeightDeg;
}

class _HorizonGeometry {
  _HorizonGeometry({
    required SiteHorizonProfile profile,
    required this.centerAltitudeDeg,
    required this.centerAzimuthDeg,
    required this.viewHeightDeg,
    required this.size,
    required this.mask,
    required this.boundary,
  }) : points = profile.points,
       blockedRanges = profile.blockedRanges;

  final List<Object> points;
  final List<Object> blockedRanges;
  final double centerAltitudeDeg;
  final double centerAzimuthDeg;
  final double viewHeightDeg;
  final Size size;
  final Path mask;
  final Path boundary;

  bool matches({
    required SiteHorizonProfile profile,
    required double centerAltitudeDeg,
    required double centerAzimuthDeg,
    required double viewHeightDeg,
    required Size size,
  }) =>
      identical(points, profile.points) &&
      identical(blockedRanges, profile.blockedRanges) &&
      this.centerAltitudeDeg == centerAltitudeDeg &&
      this.centerAzimuthDeg == centerAzimuthDeg &&
      this.viewHeightDeg == viewHeightDeg &&
      this.size == size;
}

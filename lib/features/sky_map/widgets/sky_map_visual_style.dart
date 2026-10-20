import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../data/models/sky_map_render_object.dart';

enum SkyMapLightPhase {
  day,
  civilTwilight,
  nauticalTwilight,
  astronomicalTwilight,
  night,
}

/// 성도 V2 전용 시각 토큰.
///
/// 좌표 계산과 무관한 색상·밀도 정책만 한곳에서 공유한다.
abstract final class SkyMapVisualStyle {
  static const background = Color(0xFF0B1221);
  static const grid = Color(0xFF61758E);
  static const coordinateLabel = Color(0xFFE1EAF5);
  static const constellationLine = Color(0xFF507B96);
  static const constellationLabel = Color(0xFFA5B6CB);

  static const galaxy = Color(0xFF72B8F2);
  static const nebula = Color(0xFFDF91B9);
  static const openCluster = Color(0xFFE7C579);
  static const globularCluster = Color(0xFF79CDB6);
  static const planetaryNebula = Color(0xFFAF9BF0);
  static const pointObject = Color(0xFFCBD8E8);

  static const _astronomicalTwilight = Color(0xFF152843);
  static const _nauticalTwilight = Color(0xFF24496F);
  static const _civilTwilight = Color(0xFF426F9B);
  static const _daylight = Color(0xFF78ADD0);

  static Color objectColor(SkyMapShapeKind kind) => switch (kind) {
    SkyMapShapeKind.galaxy => galaxy,
    SkyMapShapeKind.openCluster => openCluster,
    SkyMapShapeKind.globularCluster => globularCluster,
    SkyMapShapeKind.nebula => nebula,
    SkyMapShapeKind.planetaryNebula => planetaryNebula,
    SkyMapShapeKind.point => pointObject,
  };

  /// 화면에 보이는 세로 각도에 맞춘 Alt/Az 격자 간격.
  static double gridIntervalFor(double viewHeightDeg) {
    if (viewHeightDeg <= 20) return 5;
    if (viewHeightDeg <= 45) return 10;
    if (viewHeightDeg <= 90) return 15;
    return 30;
  }

  static SkyMapLightPhase lightPhaseFor(double sunAltitudeDeg) {
    if (sunAltitudeDeg >= 0) return SkyMapLightPhase.day;
    if (sunAltitudeDeg >= -6) return SkyMapLightPhase.civilTwilight;
    if (sunAltitudeDeg >= -12) return SkyMapLightPhase.nauticalTwilight;
    if (sunAltitudeDeg >= -18) {
      return SkyMapLightPhase.astronomicalTwilight;
    }
    return SkyMapLightPhase.night;
  }

  /// 태양 고도 anchor 사이를 연속 보간한 하늘색.
  static Color skyColorFor(double sunAltitudeDeg) {
    if (sunAltitudeDeg <= -18) return background;
    if (sunAltitudeDeg < -12) {
      return _lerp(background, _astronomicalTwilight, sunAltitudeDeg, -18, -12);
    }
    if (sunAltitudeDeg < -6) {
      return _lerp(
        _astronomicalTwilight,
        _nauticalTwilight,
        sunAltitudeDeg,
        -12,
        -6,
      );
    }
    if (sunAltitudeDeg < 0) {
      return _lerp(_nauticalTwilight, _civilTwilight, sunAltitudeDeg, -6, 0);
    }
    return _lerp(_civilTwilight, _daylight, sunAltitudeDeg, 0, 18);
  }

  static Color groundColorFor(double sunAltitudeDeg) =>
      Color.lerp(skyColorFor(sunAltitudeDeg), const Color(0xFF06101B), 0.68)!;

  /// 실제 Alt/Az에 고정되는 대기 배경색.
  ///
  /// 고도에 따른 천정·중간·지평선 색을 먼저 보간하고, 박명 동안에만
  /// 태양과의 구면 각거리에 따라 지평선의 따뜻한 색을 국소적으로 더한다.
  static Color atmosphericColorFor({
    required double altitudeDeg,
    required double azimuthDeg,
    required double sunAltitudeDeg,
    required double sunAzimuthDeg,
  }) {
    if (altitudeDeg < 0) {
      return atmosphericGroundColorFor(
        altitudeDeg: altitudeDeg,
        azimuthDeg: azimuthDeg,
        sunAltitudeDeg: sunAltitudeDeg,
        sunAzimuthDeg: sunAzimuthDeg,
      );
    }

    final anchors = _atmosphereAnchors(sunAltitudeDeg);
    final normalizedAltitude = (altitudeDeg / 90).clamp(0.0, 1.0);
    final base = normalizedAltitude <= 0.42
        ? Color.lerp(
            anchors.horizon,
            anchors.middle,
            _smoothStep(0, 0.42, normalizedAltitude),
          )!
        : Color.lerp(
            anchors.middle,
            anchors.zenith,
            _smoothStep(0.42, 1, normalizedAltitude),
          )!;

    final twilightRise = _smoothStep(-18, -5, sunAltitudeDeg);
    final daylightFade = 1 - _smoothStep(-1, 5, sunAltitudeDeg);
    final horizonWeight = 1 - _smoothStep(0, 38, altitudeDeg);
    final separation = _angularSeparationDeg(
      altitudeDeg,
      azimuthDeg,
      sunAltitudeDeg,
      sunAzimuthDeg,
    );
    final sunDirectionWeight = math
        .pow(math.max(0, math.cos(separation * math.pi / 180)), 2.2)
        .toDouble();
    final warmWeight =
        0.42 * twilightRise * daylightFade * horizonWeight * sunDirectionWeight;
    return Color.lerp(base, const Color(0xFFE5AD82), warmWeight)!;
  }

  static Color atmosphericGroundColorFor({
    required double altitudeDeg,
    required double azimuthDeg,
    required double sunAltitudeDeg,
    required double sunAzimuthDeg,
  }) {
    final horizon = atmosphericColorFor(
      altitudeDeg: 0,
      azimuthDeg: azimuthDeg,
      sunAltitudeDeg: sunAltitudeDeg,
      sunAzimuthDeg: sunAzimuthDeg,
    );
    final daylight = _smoothStep(-12, 6, sunAltitudeDeg);
    final deepGround = Color.lerp(
      const Color(0xFF030914),
      const Color(0xFF172832),
      daylight,
    )!;
    final depth = (-altitudeDeg / 90).clamp(0.0, 1.0);
    return Color.lerp(
      horizon,
      deepGround,
      0.38 + 0.57 * _smoothStep(0, 1, depth),
    )!;
  }

  static Color gridColorFor(double sunAltitudeDeg) =>
      sunAltitudeDeg >= -6 ? const Color(0xFF304A66) : const Color(0xFF7187A2);

  static Color azimuthGridColorFor(double sunAltitudeDeg) =>
      sunAltitudeDeg >= -6 ? const Color(0xFF38536E) : const Color(0xFF627B98);

  static Color coordinateColorFor(double sunAltitudeDeg) =>
      sunAltitudeDeg >= -6 ? const Color(0xFF102840) : coordinateLabel;

  /// 지평선 아래는 30%, -3°~+2° 구간은 연속 보간한다.
  static double visibilityForAltitude(double altitudeDeg) {
    if (altitudeDeg <= -3) return 0.30;
    if (altitudeDeg >= 2) return 1;
    return 0.30 + ((altitudeDeg + 3) / 5) * 0.70;
  }

  static Color _lerp(
    Color begin,
    Color end,
    double value,
    double lower,
    double upper,
  ) => Color.lerp(
    begin,
    end,
    ((value - lower) / (upper - lower)).clamp(0.0, 1.0),
  )!;

  static ({Color zenith, Color middle, Color horizon}) _atmosphereAnchors(
    double sunAltitudeDeg,
  ) {
    const night = (
      zenith: Color(0xFF070F25),
      middle: Color(0xFF101D37),
      horizon: Color(0xFF243952),
    );
    const astronomical = (
      zenith: Color(0xFF101E48),
      middle: Color(0xFF263C61),
      horizon: Color(0xFF4B5874),
    );
    const nautical = (
      zenith: Color(0xFF172D59),
      middle: Color(0xFF34527D),
      horizon: Color(0xFF6B7895),
    );
    const civil = (
      zenith: Color(0xFF234D7D),
      middle: Color(0xFF557FAB),
      horizon: Color(0xFFA2B4C7),
    );
    const day = (
      zenith: Color(0xFF25629B),
      middle: Color(0xFF4D94C5),
      horizon: Color(0xFFA4D3E8),
    );

    if (sunAltitudeDeg <= -18) return night;
    if (sunAltitudeDeg < -12) {
      return _lerpAnchors(night, astronomical, sunAltitudeDeg, -18, -12);
    }
    if (sunAltitudeDeg < -6) {
      return _lerpAnchors(astronomical, nautical, sunAltitudeDeg, -12, -6);
    }
    if (sunAltitudeDeg < 0) {
      return _lerpAnchors(nautical, civil, sunAltitudeDeg, -6, 0);
    }
    return _lerpAnchors(civil, day, sunAltitudeDeg, 0, 12);
  }

  static ({Color zenith, Color middle, Color horizon}) _lerpAnchors(
    ({Color zenith, Color middle, Color horizon}) begin,
    ({Color zenith, Color middle, Color horizon}) end,
    double value,
    double lower,
    double upper,
  ) {
    final t = ((value - lower) / (upper - lower)).clamp(0.0, 1.0);
    return (
      zenith: Color.lerp(begin.zenith, end.zenith, t)!,
      middle: Color.lerp(begin.middle, end.middle, t)!,
      horizon: Color.lerp(begin.horizon, end.horizon, t)!,
    );
  }

  static double _angularSeparationDeg(
    double altitudeA,
    double azimuthA,
    double altitudeB,
    double azimuthB,
  ) {
    final altitudeARad = altitudeA * math.pi / 180;
    final altitudeBRad = altitudeB * math.pi / 180;
    final deltaAzimuth = (azimuthA - azimuthB) * math.pi / 180;
    final cosine =
        math.sin(altitudeARad) * math.sin(altitudeBRad) +
        math.cos(altitudeARad) *
            math.cos(altitudeBRad) *
            math.cos(deltaAzimuth);
    return math.acos(cosine.clamp(-1.0, 1.0)) * 180 / math.pi;
  }

  static double _smoothStep(double edge0, double edge1, double value) {
    final t = ((value - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }
}

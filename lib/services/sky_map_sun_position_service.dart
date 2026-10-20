import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'celestial_position_service.dart';

/// 성도 배경용 태양 고도 계산.
///
/// 태양의 저정밀 황도 좌표를 구한 뒤 앱의 공통 Alt/Az 변환을 사용한다.
/// 배경의 낮·박명 단계 판정에 충분한 정밀도를 목표로 하며, 일식 등 정밀
/// 천문현상 계산에는 사용하지 않는다.
abstract final class SkyMapSunPositionService {
  static AltAz position({
    required DateTime time,
    required double latitudeDeg,
    required double longitudeDeg,
  }) {
    final equatorial = equatorialCoordinates(time);
    return CelestialPositionService.computeAltAz(
      raHours: equatorial.raDeg / 15,
      decDeg: equatorial.decDeg,
      latDeg: latitudeDeg,
      lonDeg: longitudeDeg,
      time: time,
    );
  }

  static double altitudeDeg({
    required DateTime time,
    required double latitudeDeg,
    required double longitudeDeg,
  }) {
    return position(
      time: time,
      latitudeDeg: latitudeDeg,
      longitudeDeg: longitudeDeg,
    ).altitude;
  }

  @visibleForTesting
  static ({double raDeg, double decDeg}) equatorialCoordinates(DateTime time) {
    final days = _julianDay(time.toUtc()) - 2451545.0;
    final meanLongitude = _normalize(280.460 + 0.9856474 * days);
    final meanAnomaly = _normalize(357.528 + 0.9856003 * days);
    final anomalyRadians = _radians(meanAnomaly);
    final eclipticLongitude = _normalize(
      meanLongitude +
          1.915 * math.sin(anomalyRadians) +
          0.020 * math.sin(2 * anomalyRadians),
    );
    final obliquity = 23.439 - 0.0000004 * days;
    final longitudeRadians = _radians(eclipticLongitude);
    final obliquityRadians = _radians(obliquity);
    final ra = math.atan2(
      math.cos(obliquityRadians) * math.sin(longitudeRadians),
      math.cos(longitudeRadians),
    );
    final dec = math.asin(
      math.sin(obliquityRadians) * math.sin(longitudeRadians),
    );
    return (raDeg: _normalize(ra * 180 / math.pi), decDeg: dec * 180 / math.pi);
  }

  static double _julianDay(DateTime utc) =>
      utc.millisecondsSinceEpoch / Duration.millisecondsPerDay + 2440587.5;

  static double _normalize(double degrees) {
    final value = degrees % 360;
    return value < 0 ? value + 360 : value;
  }

  static double _radians(double degrees) => degrees * math.pi / 180;
}

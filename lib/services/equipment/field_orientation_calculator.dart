import 'dart:math' as math;

import '../../data/models/fov_box.dart';
import '../../data/models/representative_framing_size.dart';
import 'fov_framing_engine.dart';

/// 관측 시각·위치에 따른 천체–센서 방향과 FOV 프레이밍.
abstract final class FieldOrientationCalculator {
  static double parallacticAngleDegrees({
    required double latitudeDeg,
    required double hourAngleDeg,
    required double declinationDeg,
  }) {
    final lat = _rad(latitudeDeg);
    final ha = _rad(hourAngleDeg);
    final dec = _rad(declinationDeg);
    final y = math.sin(ha);
    final x = math.cos(ha) * math.sin(lat) - math.tan(dec) * math.cos(lat);
    return _deg(math.atan2(y, x));
  }

  static double hourAngleDegrees({
    required double longitudeDeg,
    required DateTime time,
    required double raHours,
  }) {
    final utc = time.toUtc();
    final jd = _julianDay(utc);
    final gmst = _gmst(jd);
    final lst = (gmst + longitudeDeg + 360) % 360;
    return (lst - raHours * 15 + 360) % 360;
  }

  /// Signed Hour Angle in hours, normalized to -12h..+12h.
  /// The sidereal calculation remains owned by [hourAngleDegrees].
  static double signedHourAngleHours({
    required double longitudeDeg,
    required DateTime time,
    required double raHours,
  }) {
    var degrees = hourAngleDegrees(
      longitudeDeg: longitudeDeg,
      time: time,
      raHours: raHours,
    );
    if (degrees > 180) degrees -= 360;
    return degrees / 15;
  }

  /// Smallest circular distance between two signed Hour Angles, in hours.
  static double hourAngleDistanceHours(double first, double second) {
    var distance = (first - second).abs() % 24;
    if (distance > 12) distance = 24 - distance;
    return distance;
  }

  static double altAzFieldRotationDegrees({
    required double parallacticAngleDeg,
  }) => parallacticAngleDeg;

  /// Total unwrapped Alt-Az field rotation across an observing window.
  ///
  /// The unwrapping avoids a false 360 degree jump around +/-180 degrees.
  static double fieldRotationSpanDuringWindow({
    required double latitudeDeg,
    required double longitudeDeg,
    required double raHours,
    required double declinationDeg,
    required DateTime windowStart,
    required DateTime windowEnd,
    Duration step = const Duration(minutes: 20),
  }) {
    if (!windowEnd.isAfter(windowStart)) return 0;

    final rotations = <double>[];
    var cursor = windowStart;

    while (!cursor.isAfter(windowEnd)) {
      final hourAngle = hourAngleDegrees(
        longitudeDeg: longitudeDeg,
        time: cursor,
        raHours: raHours,
      );
      rotations.add(altAzFieldRotationDegrees(
        parallacticAngleDeg: parallacticAngleDegrees(
          latitudeDeg: latitudeDeg,
          hourAngleDeg: hourAngle,
          declinationDeg: declinationDeg,
        ),
      ));
      cursor = cursor.add(step);
    }
    return unwrappedRotationSpanDegrees(rotations);
  }

  /// Total span of angular samples after removing +/-180 degree wrap jumps.
  static double unwrappedRotationSpanDegrees(Iterable<double> angles) {
    final samples = angles.toList(growable: false);
    if (samples.length < 2) return 0;
    var previous = samples.first;
    var cumulative = 0.0;
    var minimum = 0.0;
    var maximum = 0.0;
    for (final angle in samples.skip(1)) {
      var delta = angle - previous;
      while (delta > 180) {
        delta -= 360;
      }
      while (delta < -180) {
        delta += 360;
      }
      cumulative += delta;
      minimum = math.min(minimum, cumulative);
      maximum = math.max(maximum, cumulative);
      previous = angle;
    }
    return maximum - minimum;
  }

  static FramingCoverageResult bestFramingDuringWindow({
    required RepresentativeFramingSize framing,
    required double fieldOfViewWidthDegrees,
    required double fieldOfViewHeightDegrees,
    required double latitudeDeg,
    required double longitudeDeg,
    required double raHours,
    required double declinationDeg,
    required DateTime windowStart,
    required DateTime windowEnd,
    Duration step = const Duration(minutes: 20),
  }) {
    final target = TargetBox.fromArcmin(
      widthArcmin: framing.widthArcmin,
      heightArcmin: framing.heightArcmin,
      positionAngleDegrees: framing.positionAngleDegrees,
    );
    final fov = FovBox(
      widthDegrees: fieldOfViewWidthDegrees,
      heightDegrees: fieldOfViewHeightDegrees,
    );

    final rotations = <double>[];
    var cursor = windowStart;
    final objectPa = framing.positionAngleDegrees ?? 0;

    while (!cursor.isAfter(windowEnd)) {
      final ha = hourAngleDegrees(
        longitudeDeg: longitudeDeg,
        time: cursor,
        raHours: raHours,
      );
      final q = parallacticAngleDegrees(
        latitudeDeg: latitudeDeg,
        hourAngleDeg: ha,
        declinationDeg: declinationDeg,
      );
      rotations.add(altAzFieldRotationDegrees(parallacticAngleDeg: q));
      cursor = cursor.add(step);
    }

    return FovFramingEngine.evaluateBestDuringWindow(
      target: target,
      fov: fov,
      objectPositionAngleDegrees: objectPa,
      fieldRotationDegreesSamples: rotations,
    );
  }

  static FramingCoverageResult bestFramingFreeRotation({
    required RepresentativeFramingSize framing,
    required double fieldOfViewWidthDegrees,
    required double fieldOfViewHeightDegrees,
  }) {
    return FovFramingEngine.evaluateBestRotation(
      target: TargetBox.fromArcmin(
        widthArcmin: framing.widthArcmin,
        heightArcmin: framing.heightArcmin,
        positionAngleDegrees: framing.positionAngleDegrees,
      ),
      fov: FovBox(
        widthDegrees: fieldOfViewWidthDegrees,
        heightDegrees: fieldOfViewHeightDegrees,
      ),
    );
  }

  /// @deprecated [bestFramingDuringWindow] 사용.
  static double minFillRatioDuringWindow({
    required RepresentativeFramingSize framing,
    required double fieldOfViewWidthDegrees,
    required double fieldOfViewHeightDegrees,
    required double latitudeDeg,
    required double longitudeDeg,
    required double raHours,
    required double declinationDeg,
    required DateTime windowStart,
    required DateTime windowEnd,
    Duration step = const Duration(minutes: 20),
  }) {
    return bestFramingDuringWindow(
      framing: framing,
      fieldOfViewWidthDegrees: fieldOfViewWidthDegrees,
      fieldOfViewHeightDegrees: fieldOfViewHeightDegrees,
      latitudeDeg: latitudeDeg,
      longitudeDeg: longitudeDeg,
      raHours: raHours,
      declinationDeg: declinationDeg,
      windowStart: windowStart,
      windowEnd: windowEnd,
      step: step,
    ).bestCoverage;
  }

  /// @deprecated [bestFramingFreeRotation] 사용.
  static double minFillRatioBestOrientation({
    required RepresentativeFramingSize framing,
    required double fieldOfViewWidthDegrees,
    required double fieldOfViewHeightDegrees,
  }) {
    return bestFramingFreeRotation(
      framing: framing,
      fieldOfViewWidthDegrees: fieldOfViewWidthDegrees,
      fieldOfViewHeightDegrees: fieldOfViewHeightDegrees,
    ).bestCoverage;
  }

  static double _rad(double deg) => deg * math.pi / 180;
  static double _deg(double rad) => rad * 180 / math.pi;

  static double _julianDay(DateTime utc) {
    final y = utc.year;
    final m = utc.month;
    final d = utc.day;
    final h = utc.hour + utc.minute / 60.0 + utc.second / 3600.0;
    final a = (14 - m) ~/ 12;
    final yr = y + 4800 - a;
    final mo = m + 12 * a - 3;
    final jdn =
        d +
        (153 * mo + 2) ~/ 5 +
        365 * yr +
        yr ~/ 4 -
        yr ~/ 100 +
        yr ~/ 400 -
        32045;
    return jdn + (h - 12) / 24.0;
  }

  static double _gmst(double jd) {
    final t = (jd - 2451545.0) / 36525.0;
    final gmst =
        280.46061837 +
        360.98564736629 * (jd - 2451545.0) +
        0.000387933 * t * t -
        t * t * t / 38710000.0;
    return gmst % 360;
  }
}

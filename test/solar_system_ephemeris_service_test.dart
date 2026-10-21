import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:astro_journal/services/solar_system_ephemeris_service.dart';

void main() {
  late SolarSystemEphemerisService service;

  setUp(() {
    service = SolarSystemEphemerisService();
  });

  test('matches JPL Horizons apparent coordinates within one arcminute', () {
    final positions = service.positions(
      time: DateTime.utc(2026, 1, 1),
      latitudeDeg: 37.5665,
      longitudeDeg: 126.9780,
    );

    // JPL Horizons DE441, observer coord@399 (126.9780 E, 37.5665 N),
    // 2026-01-01 00:00:00 UTC, apparent RA/DEC (quantity 2).
    const reference = <SolarSystemBody, (double, double)>{
      SolarSystemBody.sun: (281.49647, -23.01907),
      SolarSystemBody.moon: (63.67252, 25.51737),
      SolarSystemBody.mercury: (268.52510, -24.00269),
      SolarSystemBody.venus: (280.05748, -23.62345),
      SolarSystemBody.mars: (283.88038, -23.72073),
      SolarSystemBody.jupiter: (113.12385, 21.97877),
      SolarSystemBody.saturn: (357.38107, -3.59654),
      SolarSystemBody.uranus: (55.73701, 19.50954),
      SolarSystemBody.neptune: (0.07761, -1.41866),
    };

    for (final position in positions) {
      final expected = reference[position.body]!;
      final errorArcmin =
          _angularSeparationDeg(
            position.raDeg,
            position.decDeg,
            expected.$1,
            expected.$2,
          ) *
          60;
      expect(
        errorArcmin,
        lessThanOrEqualTo(1),
        reason: '${position.body.name}: $errorArcmin arcmin',
      );
    }
  });

  test('all seven planet positions change with date', () {
    final first = service.positions(
      time: DateTime.utc(2026, 1, 1),
      latitudeDeg: 37.5665,
      longitudeDeg: 126.9780,
    );
    final later = service.positions(
      time: DateTime.utc(2026, 2, 1),
      latitudeDeg: 37.5665,
      longitudeDeg: 126.9780,
    );

    for (final body in SolarSystemBody.values.skip(2)) {
      final a = first.singleWhere((value) => value.body == body);
      final b = later.singleWhere((value) => value.body == body);
      expect(
        _angularSeparationDeg(a.raDeg, a.decDeg, b.raDeg, b.decDeg),
        greaterThan(0.05),
        reason: body.name,
      );
    }
  });

  test('observer location changes horizontal coordinates', () {
    final time = DateTime.utc(2026, 1, 1);
    final seoul = service.positions(
      time: time,
      latitudeDeg: 37.5665,
      longitudeDeg: 126.9780,
    );
    final london = service.positions(
      time: time,
      latitudeDeg: 51.5072,
      longitudeDeg: -0.1276,
    );

    for (final body in SolarSystemBody.values) {
      final a = seoul.singleWhere((value) => value.body == body).altAz;
      final b = london.singleWhere((value) => value.body == body).altAz;
      expect(
        (a.altitude - b.altitude).abs() + (a.azimuth - b.azimuth).abs(),
        greaterThan(0.1),
        reason: body.name,
      );
    }
  });

  test('UTC and local DateTime for the same instant are equivalent', () {
    final utc = DateTime.utc(2026, 7, 1, 12, 34, 56);
    final local = DateTime.fromMillisecondsSinceEpoch(
      utc.millisecondsSinceEpoch,
    );
    final a = service.positions(time: utc, latitudeDeg: 35, longitudeDeg: 127);
    final b = service.positions(
      time: local,
      latitudeDeg: 35,
      longitudeDeg: 127,
    );

    for (var index = 0; index < a.length; index++) {
      expect(a[index].raDeg, closeTo(b[index].raDeg, 1e-12));
      expect(a[index].decDeg, closeTo(b[index].decDeg, 1e-12));
      expect(a[index].altAz.azimuth, inInclusiveRange(0.0, 360.0));
    }
  });

  test('supports the 2000 through 2100 contract boundaries', () {
    expect(
      service.positions(
        time: DateTime.utc(2000, 1, 1),
        latitudeDeg: 0,
        longitudeDeg: 0,
      ),
      hasLength(9),
    );
    expect(
      service.positions(
        time: DateTime.utc(2100, 12, 31, 23, 59, 59),
        latitudeDeg: 0,
        longitudeDeg: 0,
      ),
      hasLength(9),
    );
    expect(
      () => service.positions(
        time: DateTime.utc(1999, 12, 31, 23, 59, 59),
        latitudeDeg: 0,
        longitudeDeg: 0,
      ),
      throwsRangeError,
    );
    expect(
      () => service.positions(
        time: DateTime.utc(2101, 1, 1),
        latitudeDeg: 0,
        longitudeDeg: 0,
      ),
      throwsRangeError,
    );
  });

  test('Moon coordinate is topocentric and includes horizontal parallax', () {
    final time = DateTime.utc(2026, 1, 1);
    final seoul = service.position(
      body: SolarSystemBody.moon,
      time: time,
      latitudeDeg: 37.5665,
      longitudeDeg: 126.9780,
    );
    final geocenterLike = service.position(
      body: SolarSystemBody.moon,
      time: time,
      latitudeDeg: 0,
      longitudeDeg: 0,
    );

    expect(seoul.isTopocentric, isTrue);
    expect(seoul.distanceAu, inInclusiveRange(0.002, 0.003));
    expect(
      _angularSeparationDeg(
        seoul.raDeg,
        seoul.decDeg,
        geocenterLike.raDeg,
        geocenterLike.decDeg,
      ),
      greaterThan(0.1),
    );
  });
}

double _angularSeparationDeg(
  double ra1Deg,
  double dec1Deg,
  double ra2Deg,
  double dec2Deg,
) {
  final ra1 = ra1Deg * math.pi / 180;
  final dec1 = dec1Deg * math.pi / 180;
  final ra2 = ra2Deg * math.pi / 180;
  final dec2 = dec2Deg * math.pi / 180;
  final cosine =
      math.sin(dec1) * math.sin(dec2) +
      math.cos(dec1) * math.cos(dec2) * math.cos(ra1 - ra2);
  return math.acos(cosine.clamp(-1.0, 1.0)) * 180 / math.pi;
}

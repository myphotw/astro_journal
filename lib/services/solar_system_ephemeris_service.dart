import 'dart:math' as math;

import 'package:astronomia/base.dart' as astro_base;
import 'package:astronomia/coord.dart' as astro_coord;
import 'package:astronomia/deltat.dart' as astro_deltat;
import 'package:astronomia/elliptic.dart' as astro_elliptic;
import 'package:astronomia/globe.dart' as astro_globe;
import 'package:astronomia/moonposition.dart' as astro_moon;
import 'package:astronomia/nutation.dart' as astro_nutation;
import 'package:astronomia/parallax.dart' as astro_parallax;
import 'package:astronomia/planetposition.dart' as astro_planet;
import 'package:astronomia/solar.dart' as astro_solar;

import 'celestial_position_service.dart';

/// 성도에서 동적으로 표시하는 태양계 천체.
enum SolarSystemBody {
  sun('solar_1'),
  moon('solar_2'),
  mercury('solar_3'),
  venus('solar_4'),
  mars('solar_5'),
  jupiter('solar_6'),
  saturn('solar_7'),
  uranus('solar_8'),
  neptune('solar_9');

  const SolarSystemBody(this.catalogId);

  final String catalogId;

  static SolarSystemBody? fromCatalogId(String id) {
    for (final body in values) {
      if (body.catalogId == id) return body;
    }
    return null;
  }
}

/// 선택 시각과 관측지에 대한 태양계 천체의 동적 좌표.
class SolarSystemPosition {
  const SolarSystemPosition({
    required this.body,
    required this.raDeg,
    required this.decDeg,
    required this.altAz,
    required this.distanceAu,
    required this.isTopocentric,
  });

  final SolarSystemBody body;
  final double raDeg;
  final double decDeg;
  final AltAz altAz;
  final double? distanceAu;
  final bool isTopocentric;
}

/// 태양·달·7개 행성의 오프라인 천체력 계산.
///
/// 행성은 VSOP87B를 기반으로 광행시간, 황도 광행차, FK5 변환과 장동을
/// 적용한 apparent equatorial 좌표를 사용한다. 달은 Meeus 47장의 주기항과
/// 관측지의 지평시차를 적용한다. 천문 계산 범위는 이 기능의 제품 계약인
/// 2000-01-01T00:00Z ~ 2100-12-31T23:59:59Z로 제한한다.
class SolarSystemEphemerisService {
  SolarSystemEphemerisService()
    : _earth = astro_planet.Planet(astro_planet.planetEarth),
      _planets = <SolarSystemBody, astro_planet.Planet>{
        SolarSystemBody.mercury: astro_planet.Planet(
          astro_planet.planetMercury,
        ),
        SolarSystemBody.venus: astro_planet.Planet(astro_planet.planetVenus),
        SolarSystemBody.mars: astro_planet.Planet(astro_planet.planetMars),
        SolarSystemBody.jupiter: astro_planet.Planet(
          astro_planet.planetJupiter,
        ),
        SolarSystemBody.saturn: astro_planet.Planet(astro_planet.planetSaturn),
        SolarSystemBody.uranus: astro_planet.Planet(astro_planet.planetUranus),
        SolarSystemBody.neptune: astro_planet.Planet(
          astro_planet.planetNeptune,
        ),
      };

  static const int minimumYear = 2000;
  static const int maximumYear = 2100;
  static const int _maxCacheEntries = 512;

  final astro_planet.Planet _earth;
  final Map<SolarSystemBody, astro_planet.Planet> _planets;
  final Map<String, List<SolarSystemPosition>> _cache = {};

  /// 같은 초·관측지의 결과를 재사용한다. Slider는 프레임당 한 번만 이
  /// 메서드를 호출하므로 확대·이동만으로 천체력을 다시 계산하지 않는다.
  List<SolarSystemPosition> positions({
    required DateTime time,
    required double latitudeDeg,
    required double longitudeDeg,
  }) {
    final utc = time.toUtc();
    _validateDate(utc);
    final key =
        '${utc.millisecondsSinceEpoch ~/ 1000}:'
        '${(latitudeDeg * 100000).round()}:'
        '${(longitudeDeg * 100000).round()}';
    final cached = _cache[key];
    if (cached != null) return cached;

    final jdUt = _julianDay(utc);
    final jde = jdUt + _deltaTSeconds(utc) / Duration.secondsPerDay;
    final equatorial =
        <
          SolarSystemBody,
          ({double ra, double dec, double? distanceAu, bool topocentric})
        >{};

    equatorial[SolarSystemBody.sun] = _sunEquatorial(jde);
    equatorial[SolarSystemBody.moon] = _moonEquatorial(
      jde: jde,
      jdUt: jdUt,
      latitudeDeg: latitudeDeg,
      longitudeDeg: longitudeDeg,
    );
    for (final entry in _planets.entries) {
      final position = astro_elliptic.position(entry.value, _earth, jde);
      equatorial[entry.key] = (
        ra: position.ra,
        dec: position.dec,
        distanceAu: null,
        topocentric: false,
      );
    }

    final result = <SolarSystemPosition>[];
    for (final body in SolarSystemBody.values) {
      final eq = equatorial[body]!;
      final raDeg = _normalizeDegrees(_degrees(eq.ra));
      final decDeg = _degrees(eq.dec);
      result.add(
        SolarSystemPosition(
          body: body,
          raDeg: raDeg,
          decDeg: decDeg,
          altAz: CelestialPositionService.computeAltAz(
            raHours: raDeg / 15,
            decDeg: decDeg,
            latDeg: latitudeDeg,
            lonDeg: longitudeDeg,
            time: utc,
          ),
          distanceAu: eq.distanceAu,
          isTopocentric: eq.topocentric,
        ),
      );
    }

    if (_cache.length >= _maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
    final immutable = List<SolarSystemPosition>.unmodifiable(result);
    _cache[key] = immutable;
    return immutable;
  }

  SolarSystemPosition position({
    required SolarSystemBody body,
    required DateTime time,
    required double latitudeDeg,
    required double longitudeDeg,
  }) => positions(
    time: time,
    latitudeDeg: latitudeDeg,
    longitudeDeg: longitudeDeg,
  ).firstWhere((position) => position.body == body);

  ({double ra, double dec, double? distanceAu, bool topocentric})
  _sunEquatorial(double jde) {
    final ecliptic = astro_solar.apparentVSOP87(_earth, jde);
    final nutation = astro_nutation.nutation(jde);
    final obliquity = astro_nutation.meanObliquity(jde) + nutation.dEps;
    final equatorial = astro_coord.eclToEq(
      ecliptic.lon,
      ecliptic.lat,
      math.sin(obliquity),
      math.cos(obliquity),
    );
    return (
      ra: equatorial.ra,
      dec: equatorial.dec,
      distanceAu: ecliptic.range,
      topocentric: false,
    );
  }

  ({double ra, double dec, double? distanceAu, bool topocentric})
  _moonEquatorial({
    required double jde,
    required double jdUt,
    required double latitudeDeg,
    required double longitudeDeg,
  }) {
    final ecliptic = astro_moon.position(jde);
    final nutation = astro_nutation.nutation(jde);
    final obliquity = astro_nutation.meanObliquity(jde) + nutation.dEps;
    final geocentric = astro_coord.eclToEq(
      ecliptic.lon + nutation.dPsi,
      ecliptic.lat,
      math.sin(obliquity),
      math.cos(obliquity),
    );

    final observer = astro_globe.parallaxConstants(_radians(latitudeDeg), 0);
    final localSidereal = _radians(
      _normalizeDegrees(_gmstDegrees(jdUt) + longitudeDeg),
    );
    final hourAngle = localSidereal - geocentric.ra;
    final distanceAu = ecliptic.delta / astro_base.au;
    final topocentric = astro_parallax.topocentric(
      geocentric.ra,
      geocentric.dec,
      distanceAu,
      observer.rhsSinPhiPrime,
      observer.rhoCosPrime,
      hourAngle,
      math.sin(astro_moon.parallax(ecliptic.delta)),
    );
    return (
      ra: topocentric.ra,
      dec: topocentric.dec,
      distanceAu: distanceAu,
      topocentric: true,
    );
  }

  static void _validateDate(DateTime utc) {
    if (utc.year < minimumYear || utc.year > maximumYear) {
      throw RangeError.range(
        utc.year,
        minimumYear,
        maximumYear,
        'time.year',
        '태양계 천체력 지원 범위를 벗어났습니다.',
      );
    }
  }

  static double _julianDay(DateTime utc) =>
      utc.microsecondsSinceEpoch / Duration.microsecondsPerDay + 2440587.5;

  static double _deltaTSeconds(DateTime utc) {
    final start = DateTime.utc(utc.year);
    final end = DateTime.utc(utc.year + 1);
    final fraction =
        utc.difference(start).inMicroseconds /
        end.difference(start).inMicroseconds;
    return astro_deltat.polyAfter2000(utc.year + fraction);
  }

  /// 앱 공통 Alt/Az 변환과 같은 mean sidereal time 식을 사용한다.
  static double _gmstDegrees(double jd) {
    final t = (jd - 2451545.0) / 36525;
    return _normalizeDegrees(
      280.46061837 +
          360.98564736629 * (jd - 2451545.0) +
          0.000387933 * t * t -
          t * t * t / 38710000,
    );
  }

  static double _normalizeDegrees(double value) {
    final normalized = value % 360;
    return normalized < 0 ? normalized + 360 : normalized;
  }

  static double _radians(double degrees) => degrees * math.pi / 180;

  static double _degrees(double radians) => radians * 180 / math.pi;
}

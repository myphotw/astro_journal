import 'dart:math' as math;

/// Equatorial coordinates (RA in hours, Dec in degrees).
class EquatorialCoordinates {
  const EquatorialCoordinates({required this.raHours, required this.decDeg});

  final double raHours;
  final double decDeg;
}

/// 특정 시각의 천체 고도·방위각.
class AltAz {
  const AltAz({required this.altitude, required this.azimuth});

  /// 고도 (°), −90 ~ +90
  final double altitude;

  /// 방위각 (°), 0 ~ 360 (북=0, 동=90, 남=180, 서=270)
  final double azimuth;
}

/// 단일 시각의 천체 위치 기록.
class CelestialTimePoint {
  const CelestialTimePoint({
    required this.time,
    required this.altitude,
    required this.azimuth,
  });

  final DateTime time;
  final double altitude;
  final double azimuth;
}

/// 특정 천체의 시계열 위치 데이터.
class CelestialTrajectory {
  const CelestialTrajectory({required this.points});

  final List<CelestialTimePoint> points;
}

/// 천체 고도·방위각 계산 서비스 (외부 API 미사용, 순수 수학 계산).
///
/// 캐시 전략:
///   objectId + 날짜(YYYYMMDD) + 위도(소수점 1자리) + 경도(소수점 1자리) 를
///   키로 사용하여 동일 조건 재계산을 방지한다.
class CelestialPositionService {
  static const _maxMoonCacheEntries = 256;

  final Map<String, CelestialTrajectory> _cache = {};
  final Map<String, EquatorialCoordinates> _moonCache = {};
  final Map<String, _TrajectoryGrid> _trajectoryGrids = {};

  // ── 공개 계산 메서드 ─────────────────────────────────────────────────────

  /// 단일 시각의 고도·방위각을 계산한다.
  static AltAz computeAltAz({
    required double raHours,
    required double decDeg,
    required double latDeg,
    required double lonDeg,
    required DateTime time,
  }) {
    final utc = time.toUtc();
    final jd = _julianDay(utc);
    final gmstDeg = _gmst(jd);
    final lstDeg = (gmstDeg + lonDeg + 360) % 360;

    final haDeg = (lstDeg - raHours * 15 + 360) % 360;
    final haRad = _toRad(haDeg);
    final decRad = _toRad(decDeg);
    final latRad = _toRad(latDeg);

    final sinAlt =
        math.sin(latRad) * math.sin(decRad) +
        math.cos(latRad) * math.cos(decRad) * math.cos(haRad);
    final altRad = math.asin(sinAlt.clamp(-1.0, 1.0));
    final alt = _toDeg(altRad);

    final cosAlt = math.cos(altRad);
    double az;
    if (cosAlt.abs() < 1e-10) {
      az = latDeg >= 0 ? 180.0 : 0.0;
    } else {
      final cosAz =
          (math.sin(decRad) - math.sin(latRad) * sinAlt) /
          (math.cos(latRad) * cosAlt);
      az = _toDeg(math.acos(cosAz.clamp(-1.0, 1.0)));
      if (math.sin(haRad) > 0) az = 360.0 - az;
    }

    return AltAz(altitude: alt, azimuth: az);
  }

  /// [start] ~ [end] 구간을 [interval] 간격으로 시계열 궤적을 반환한다.
  ///
  /// 캐시 키가 일치하면 이전 결과를 즉시 반환한다.
  CelestialTrajectory getTrajectory({
    required String objectId,
    required double raHours,
    required double decDeg,
    required double latitude,
    required double longitude,
    required DateTime start,
    required DateTime end,
    Duration interval = const Duration(minutes: 10),
  }) {
    final key = _cacheKey(objectId, start, end, latitude, longitude);
    final cached = _cache[key];
    if (cached != null) return cached;

    final grid = _trajectoryGrid(
      start: start,
      end: end,
      latitude: latitude,
      longitude: longitude,
      interval: interval,
    );
    final decRad = _toRad(decDeg);
    final sinDec = math.sin(decRad);
    final cosDec = math.cos(decRad);
    final points = <CelestialTimePoint>[];
    for (final frame in grid.frames) {
      final altAz = _computePreparedAltAz(
        raHours: raHours,
        sinDec: sinDec,
        cosDec: cosDec,
        grid: grid,
        lstDeg: frame.lstDeg,
      );
      points.add(
        CelestialTimePoint(
          time: frame.time,
          altitude: altAz.altitude,
          azimuth: altAz.azimuth,
        ),
      );
    }

    final traj = CelestialTrajectory(points: points);
    _cache[key] = traj;
    return traj;
  }

  /// Computes the Moon's geocentric equatorial position (Meeus Ch.47, simplified).
  ///
  /// Results are cached per UTC minute so recommendation loops reuse one lookup.
  EquatorialCoordinates getMoonEquatorial(DateTime time) {
    final utc = time.toUtc();
    final key =
        '${utc.year}${utc.month.toString().padLeft(2, '0')}${utc.day.toString().padLeft(2, '0')}_'
        '${utc.hour.toString().padLeft(2, '0')}${utc.minute.toString().padLeft(2, '0')}';
    final cached = _moonCache[key];
    if (cached != null) return cached;

    final coords = _computeMoonEquatorial(utc);
    if (_moonCache.length >= _maxMoonCacheEntries) {
      _moonCache.remove(_moonCache.keys.first);
    }
    _moonCache[key] = coords;
    return coords;
  }

  /// Great-circle angular separation between two equatorial positions (degrees).
  static double angularSeparationDeg({
    required double ra1Hours,
    required double dec1Deg,
    required double ra2Hours,
    required double dec2Deg,
  }) {
    final ra1 = _toRad(ra1Hours * 15);
    final ra2 = _toRad(ra2Hours * 15);
    final dec1 = _toRad(dec1Deg);
    final dec2 = _toRad(dec2Deg);

    final cosD =
        math.sin(dec1) * math.sin(dec2) +
        math.cos(dec1) * math.cos(dec2) * math.cos(ra1 - ra2);
    return _toDeg(math.acos(cosD.clamp(-1.0, 1.0)));
  }

  /// 날짜/위치 변경 시 캐시를 비운다.
  void clearCache() {
    _cache.clear();
    _moonCache.clear();
    _trajectoryGrids.clear();
  }

  _TrajectoryGrid _trajectoryGrid({
    required DateTime start,
    required DateTime end,
    required double latitude,
    required double longitude,
    required Duration interval,
  }) {
    final key =
        '${start.microsecondsSinceEpoch}_${end.microsecondsSinceEpoch}_'
        '${latitude.toStringAsFixed(6)}_${longitude.toStringAsFixed(6)}_'
        '${interval.inMicroseconds}';
    final cached = _trajectoryGrids[key];
    if (cached != null) return cached;

    final frames = <_TrajectoryFrame>[];
    var cursor = start;
    while (!cursor.isAfter(end)) {
      final utc = cursor.toUtc();
      frames.add(
        _TrajectoryFrame(
          time: cursor,
          lstDeg: (_gmst(_julianDay(utc)) + longitude + 360) % 360,
        ),
      );
      cursor = cursor.add(interval);
    }
    final latRad = _toRad(latitude);
    final grid = _TrajectoryGrid(
      frames: frames,
      sinLat: math.sin(latRad),
      cosLat: math.cos(latRad),
      northernHemisphere: latitude >= 0,
    );
    _trajectoryGrids[key] = grid;
    return grid;
  }

  static AltAz _computePreparedAltAz({
    required double raHours,
    required double sinDec,
    required double cosDec,
    required _TrajectoryGrid grid,
    required double lstDeg,
  }) {
    final haDeg = (lstDeg - raHours * 15 + 360) % 360;
    final haRad = _toRad(haDeg);
    final sinAlt =
        grid.sinLat * sinDec + grid.cosLat * cosDec * math.cos(haRad);
    final altRad = math.asin(sinAlt.clamp(-1.0, 1.0));
    final altitude = _toDeg(altRad);
    final cosAlt = math.cos(altRad);
    double azimuth;
    if (cosAlt.abs() < 1e-10) {
      azimuth = grid.northernHemisphere ? 180.0 : 0.0;
    } else {
      final cosAz = (sinDec - grid.sinLat * sinAlt) / (grid.cosLat * cosAlt);
      azimuth = _toDeg(math.acos(cosAz.clamp(-1.0, 1.0)));
      if (math.sin(haRad) > 0) azimuth = 360.0 - azimuth;
    }
    return AltAz(altitude: altitude, azimuth: azimuth);
  }

  // ── RA / Dec 파싱 ────────────────────────────────────────────────────────

  /// RA 문자열(예: "5h 35m", "5h35m") → 시간(double)
  static double parseRaHours(String ra) {
    final match = RegExp(r'(\d+)h(?:\s*(\d+(?:\.\d+)?)m)?').firstMatch(ra);
    if (match == null) return 0;
    final hours = double.tryParse(match.group(1) ?? '') ?? 0;
    final minutes = double.tryParse(match.group(2) ?? '0') ?? 0;
    return hours + minutes / 60;
  }

  /// Dec 문자열(예: "+30° 00m", "-05d30m") → 도(double)
  static double parseDecDeg(String dec) {
    final match = RegExp(
      r'([+-]?)(\d+)[°d]?\s*(\d+(?:\.\d+)?)?',
    ).firstMatch(dec);
    if (match == null) return 0;
    final sign = match.group(1) == '-' ? -1.0 : 1.0;
    final degrees = double.tryParse(match.group(2) ?? '0') ?? 0;
    final minutes = double.tryParse(match.group(3) ?? '0') ?? 0;
    return sign * (degrees + minutes / 60);
  }

  // ── 내부 천체역학 수식 ────────────────────────────────────────────────────

  static double _toRad(double deg) => deg * math.pi / 180;
  static double _toDeg(double rad) => rad * 180 / math.pi;

  /// UTC DateTime → Julian Day Number
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

  /// Julian Day → Greenwich Mean Sidereal Time (°)
  static double _gmst(double jd) {
    final t = (jd - 2451545.0) / 36525.0;
    final gmst =
        280.46061837 +
        360.98564736629 * (jd - 2451545.0) +
        0.000387933 * t * t -
        t * t * t / 38710000.0;
    return gmst % 360;
  }

  String _cacheKey(
    String objectId,
    DateTime start,
    DateTime end,
    double lat,
    double lon,
  ) {
    return '${objectId}_${start.millisecondsSinceEpoch}_${end.millisecondsSinceEpoch}_${lat.toStringAsFixed(1)}_${lon.toStringAsFixed(1)}';
  }

  static double _normDeg(double deg) {
    var d = deg % 360;
    if (d < 0) d += 360;
    return d;
  }

  static EquatorialCoordinates _computeMoonEquatorial(DateTime utc) {
    final jd = _julianDay(utc);
    final t = (jd - 2451545.0) / 36525.0;

    final lp = _normDeg(
      218.3164477 +
          481267.88123421 * t -
          0.0015786 * t * t +
          t * t * t / 538841 -
          t * t * t * t / 65194000,
    );
    final d = _normDeg(
      297.8501921 +
          445267.1114034 * t -
          0.0018819 * t * t +
          t * t * t / 545868 -
          t * t * t * t / 113065000,
    );
    final m = _normDeg(
      357.5291092 +
          35999.0502909 * t -
          0.0001536 * t * t +
          t * t * t / 24490000,
    );
    final mp = _normDeg(
      134.9633964 +
          477198.8675055 * t +
          0.0086972 * t * t +
          t * t * t / 56260000,
    );
    final f = _normDeg(
      93.2720950 + 483202.0175233 * t - 0.0036539 * t * t - t * t * t / 3526000,
    );

    final dRad = _toRad(d);
    final mRad = _toRad(m);
    final mpRad = _toRad(mp);
    final fRad = _toRad(f);

    var lambda =
        lp +
        6.289 * math.sin(mpRad) +
        1.274 * math.sin(2 * dRad - mpRad) +
        0.658 * math.sin(2 * dRad) +
        0.214 * math.sin(2 * mpRad) -
        0.186 * math.sin(mRad) -
        0.114 * math.sin(2 * fRad) +
        0.067 * math.sin(2 * dRad - 2 * mpRad) +
        0.053 * math.sin(2 * dRad + mpRad) +
        0.041 * math.sin(2 * dRad - mRad);

    var beta =
        5.128 * math.sin(fRad) +
        0.281 * math.sin(mpRad + fRad) +
        0.278 * math.sin(mpRad - fRad) +
        0.173 * math.sin(2 * dRad - fRad) +
        0.055 * math.sin(2 * dRad + fRad - mpRad);

    lambda = _normDeg(lambda);
    beta = beta.clamp(-90.0, 90.0);

    final epsilon = 23.439291 - 0.0130042 * t;
    final lambdaRad = _toRad(lambda);
    final betaRad = _toRad(beta);
    final epsRad = _toRad(epsilon);

    final sinDec =
        math.sin(betaRad) * math.cos(epsRad) +
        math.cos(betaRad) * math.sin(epsRad) * math.sin(lambdaRad);
    final dec = _toDeg(math.asin(sinDec.clamp(-1.0, 1.0)));

    final y =
        math.sin(lambdaRad) * math.cos(epsRad) -
        math.tan(betaRad) * math.sin(epsRad);
    final x = math.cos(lambdaRad);
    var raDeg = _toDeg(math.atan2(y, x));
    if (raDeg < 0) raDeg += 360;

    return EquatorialCoordinates(raHours: raDeg / 15, decDeg: dec);
  }
}

class _TrajectoryFrame {
  const _TrajectoryFrame({required this.time, required this.lstDeg});

  final DateTime time;
  final double lstDeg;
}

class _TrajectoryGrid {
  const _TrajectoryGrid({
    required this.frames,
    required this.sinLat,
    required this.cosLat,
    required this.northernHemisphere,
  });

  final List<_TrajectoryFrame> frames;
  final double sinLat;
  final double cosLat;
  final bool northernHemisphere;
}

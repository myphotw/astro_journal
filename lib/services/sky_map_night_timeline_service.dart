import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'sky_map_sun_position_service.dart';

@immutable
class SkyMapNightTimeline {
  const SkyMapNightTimeline({
    required this.observationDate,
    required this.midnight,
    required this.start,
    required this.end,
    required this.sunset,
    required this.sunrise,
    required this.usedFallback,
  });

  final DateTime observationDate;
  final DateTime midnight;
  final DateTime start;
  final DateTime end;
  final DateTime? sunset;
  final DateTime? sunrise;
  final bool usedFallback;

  int get totalMinutes => end.difference(start).inMinutes;
  int get midnightOffsetMinutes => midnight.difference(start).inMinutes;

  DateTime timeAtOffset(int minutes) =>
      start.add(Duration(minutes: minutes.clamp(0, totalMinutes)));

  DateTime timeAtPosition(double minutes) {
    final clamped = minutes.clamp(0.0, totalMinutes.toDouble());
    return start.add(Duration(milliseconds: (clamped * 60000).round()));
  }

  int offsetFor(DateTime time) =>
      time.difference(start).inMinutes.clamp(0, totalMinutes);

  double positionFor(DateTime time) =>
      (time.difference(start).inMilliseconds / 60000).clamp(
        0.0,
        totalMinutes.toDouble(),
      );

  double fractionFor(DateTime time) {
    if (totalMinutes <= 0) return 0;
    return (time.difference(start).inSeconds / (totalMinutes * 60)).clamp(
      0.0,
      1.0,
    );
  }

  int dayOffsetFor(DateTime time) {
    final date = DateTime.utc(time.year, time.month, time.day);
    final base = DateTime.utc(
      observationDate.year,
      observationDate.month,
      observationDate.day,
    );
    return date.difference(base).inDays;
  }
}

/// 선택한 관측일 저녁부터 다음 날 아침까지의 성도 시간축을 계산한다.
///
/// 일몰과 일출은 태양 중심 고도 -0.833°의 하강/상승 통과 시각을 찾는다.
/// 양쪽에 30분 여유를 더한 뒤 다음 날 자정을 중심으로 좌우 대칭 범위를
/// 만든다. 극지방처럼 통과 시각이 없으면 18:00~다음 날 06:00을 사용한다.
class SkyMapNightTimelineService {
  const SkyMapNightTimelineService();

  static const double sunsetAltitudeDeg = -0.833;
  static const Duration margin = Duration(minutes: 30);
  static const Duration fallbackHalfSpan = Duration(hours: 6);
  static const Duration _sampleStep = Duration(minutes: 10);

  DateTime observationDateFor(DateTime time) {
    final date = _dateOnly(time);
    return time.hour < 12 ? _shiftDate(date, -1) : date;
  }

  SkyMapNightTimeline calculate({
    required DateTime observationDate,
    required double latitudeDeg,
    required double longitudeDeg,
    DateTime? includeTime,
  }) {
    final date = _dateOnly(observationDate);
    final nextDate = _shiftDate(date, 1);
    final midnight = _at(nextDate, 0, 0);
    final sunset = _findCrossing(
      from: _at(date, 12, 0),
      to: midnight,
      latitudeDeg: latitudeDeg,
      longitudeDeg: longitudeDeg,
      rising: false,
    );
    final sunrise = _findCrossing(
      from: midnight,
      to: _at(nextDate, 12, 0),
      latitudeDeg: latitudeDeg,
      longitudeDeg: longitudeDeg,
      rising: true,
    );

    final usedFallback = sunset == null || sunrise == null;
    var halfSpanMinutes = fallbackHalfSpan.inMinutes;
    if (!usedFallback) {
      final eveningMinutes = midnight
          .difference(sunset.subtract(margin))
          .inMinutes;
      final morningMinutes = sunrise.add(margin).difference(midnight).inMinutes;
      halfSpanMinutes = math.max(eveningMinutes, morningMinutes);
      halfSpanMinutes = ((halfSpanMinutes + 9) ~/ 10) * 10;
    }

    if (includeTime != null) {
      final distance = includeTime.difference(midnight).inMinutes.abs();
      if (distance > halfSpanMinutes) {
        halfSpanMinutes = ((distance + 9) ~/ 10) * 10;
      }
    }

    return SkyMapNightTimeline(
      observationDate: date,
      midnight: midnight,
      start: midnight.subtract(Duration(minutes: halfSpanMinutes)),
      end: midnight.add(Duration(minutes: halfSpanMinutes)),
      sunset: sunset,
      sunrise: sunrise,
      usedFallback: usedFallback,
    );
  }

  DateTime? _findCrossing({
    required DateTime from,
    required DateTime to,
    required double latitudeDeg,
    required double longitudeDeg,
    required bool rising,
  }) {
    var previousTime = from;
    var previousAltitude = _altitude(previousTime, latitudeDeg, longitudeDeg);
    for (
      var time = from.add(_sampleStep);
      !time.isAfter(to);
      time = time.add(_sampleStep)
    ) {
      final altitude = _altitude(time, latitudeDeg, longitudeDeg);
      final crossed = rising
          ? previousAltitude < sunsetAltitudeDeg &&
                altitude >= sunsetAltitudeDeg
          : previousAltitude >= sunsetAltitudeDeg &&
                altitude < sunsetAltitudeDeg;
      if (crossed) {
        return _refineCrossing(
          low: previousTime,
          high: time,
          latitudeDeg: latitudeDeg,
          longitudeDeg: longitudeDeg,
          rising: rising,
        );
      }
      previousTime = time;
      previousAltitude = altitude;
    }
    return null;
  }

  DateTime _refineCrossing({
    required DateTime low,
    required DateTime high,
    required double latitudeDeg,
    required double longitudeDeg,
    required bool rising,
  }) {
    var left = low;
    var right = high;
    while (right.difference(left) > const Duration(seconds: 30)) {
      final middle = left.add(right.difference(left) ~/ 2);
      final above =
          _altitude(middle, latitudeDeg, longitudeDeg) >= sunsetAltitudeDeg;
      if (rising ? above : !above) {
        right = middle;
      } else {
        left = middle;
      }
    }
    return left.add(right.difference(left) ~/ 2);
  }

  double _altitude(DateTime time, double latitudeDeg, double longitudeDeg) =>
      SkyMapSunPositionService.altitudeDeg(
        time: time,
        latitudeDeg: latitudeDeg,
        longitudeDeg: longitudeDeg,
      );

  static DateTime _dateOnly(DateTime value) => value.isUtc
      ? DateTime.utc(value.year, value.month, value.day)
      : DateTime(value.year, value.month, value.day);

  static DateTime _shiftDate(DateTime date, int days) => date.isUtc
      ? DateTime.utc(date.year, date.month, date.day + days)
      : DateTime(date.year, date.month, date.day + days);

  static DateTime _at(DateTime date, int hour, int minute) => date.isUtc
      ? DateTime.utc(date.year, date.month, date.day, hour, minute)
      : DateTime(date.year, date.month, date.day, hour, minute);
}

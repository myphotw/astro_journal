import 'package:astro_journal/services/sky_map_night_timeline_service.dart';
import 'package:astro_journal/services/sky_map_sun_position_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = SkyMapNightTimelineService();

  group('SkyMapNightTimelineService', () {
    test('treats early morning as the previous observing date', () {
      expect(
        service.observationDateFor(DateTime(2026, 10, 21, 2, 30)),
        DateTime(2026, 10, 20),
      );
      expect(
        service.observationDateFor(DateTime(2026, 10, 21, 12)),
        DateTime(2026, 10, 21),
      );
    });

    test('keeps midnight exactly centered around sunset and sunrise', () {
      final timeline = service.calculate(
        observationDate: DateTime(2026, 10, 20),
        latitudeDeg: 37.5665,
        longitudeDeg: 126.978,
      );

      expect(timeline.usedFallback, isFalse);
      expect(timeline.sunset, isNotNull);
      expect(timeline.sunrise, isNotNull);
      expect(timeline.midnightOffsetMinutes * 2, timeline.totalMinutes);
      expect(timeline.fractionFor(timeline.midnight), closeTo(0.5, 1e-12));
      expect(timeline.sunset!.isBefore(timeline.midnight), isTrue);
      expect(timeline.sunrise!.isAfter(timeline.midnight), isTrue);
      expect(timeline.start.isBefore(timeline.sunset!), isTrue);
      expect(timeline.end.isAfter(timeline.sunrise!), isTrue);

      final sunsetAltitude = SkyMapSunPositionService.altitudeDeg(
        time: timeline.sunset!,
        latitudeDeg: 37.5665,
        longitudeDeg: 126.978,
      );
      final sunriseAltitude = SkyMapSunPositionService.altitudeDeg(
        time: timeline.sunrise!,
        latitudeDeg: 37.5665,
        longitudeDeg: 126.978,
      );
      expect(sunsetAltitude, closeTo(-0.833, 0.08));
      expect(sunriseAltitude, closeTo(-0.833, 0.08));
    });

    test('season changes the symmetric observing range', () {
      final summer = service.calculate(
        observationDate: DateTime(2026, 6, 21),
        latitudeDeg: 37.5665,
        longitudeDeg: 126.978,
      );
      final winter = service.calculate(
        observationDate: DateTime(2026, 12, 21),
        latitudeDeg: 37.5665,
        longitudeDeg: 126.978,
      );

      expect(summer.totalMinutes, isNot(winter.totalMinutes));
      expect(summer.midnightOffsetMinutes * 2, summer.totalMinutes);
      expect(winter.midnightOffsetMinutes * 2, winter.totalMinutes);
    });

    test('23:50 advances continuously to next-day midnight', () {
      final timeline = service.calculate(
        observationDate: DateTime(2026, 10, 20),
        latitudeDeg: 37.5665,
        longitudeDeg: 126.978,
      );
      final beforeMidnight = timeline.midnightOffsetMinutes - 10;

      expect(
        timeline.timeAtOffset(beforeMidnight),
        DateTime(2026, 10, 20, 23, 50),
      );
      expect(
        timeline.timeAtOffset(beforeMidnight + 10),
        DateTime(2026, 10, 21),
      );
      expect(
        timeline.timeAtOffset(beforeMidnight + 20),
        DateTime(2026, 10, 21, 0, 10),
      );
    });

    test('extends symmetrically to preserve an out-of-range current time', () {
      final current = DateTime(2026, 10, 20, 13, 7);
      final timeline = service.calculate(
        observationDate: DateTime(2026, 10, 20),
        latitudeDeg: 37.5665,
        longitudeDeg: 126.978,
        includeTime: current,
      );

      expect(timeline.start.isAfter(current), isFalse);
      expect(timeline.midnightOffsetMinutes * 2, timeline.totalMinutes);
      expect(timeline.timeAtOffset(timeline.offsetFor(current)), current);
    });

    test('uses a stable fallback when polar day has no crossings', () {
      final timeline = service.calculate(
        observationDate: DateTime(2026, 6, 21),
        latitudeDeg: 89,
        longitudeDeg: 0,
      );

      expect(timeline.usedFallback, isTrue);
      expect(timeline.sunset, isNull);
      expect(timeline.sunrise, isNull);
      expect(timeline.totalMinutes, 12 * 60);
      expect(timeline.midnightOffsetMinutes, 6 * 60);
    });
  });
}

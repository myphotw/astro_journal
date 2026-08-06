import 'package:astro_journal/core/constants/moon_separation_weights.dart';
import 'package:astro_journal/services/celestial_position_service.dart';
import 'package:astro_journal/services/recommendation/feasible_window_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MoonSeparationWeights', () {
    test('applies tier penalties', () {
      expect(MoonSeparationWeights.penaltyForSeparation(10), -40);
      expect(MoonSeparationWeights.penaltyForSeparation(30), -25);
      expect(MoonSeparationWeights.penaltyForSeparation(50), -15);
      expect(MoonSeparationWeights.penaltyForSeparation(75), -5);
      expect(MoonSeparationWeights.penaltyForSeparation(120), 0);
    });
  });

  group('CelestialPositionService moon separation', () {
    test('angular separation is zero for identical coordinates', () {
      final sep = CelestialPositionService.angularSeparationDeg(
        ra1Hours: 5,
        dec1Deg: 20,
        ra2Hours: 5,
        dec2Deg: 20,
      );
      expect(sep, closeTo(0, 0.001));
    });

    test('moon equatorial is cached per minute', () {
      final service = CelestialPositionService();
      final t = DateTime(2026, 6, 24, 22, 15);
      final a = service.getMoonEquatorial(t);
      final b = service.getMoonEquatorial(t.add(const Duration(seconds: 30)));
      expect(a.raHours, b.raHours);
      expect(a.decDeg, b.decDeg);
    });
  });

  group('FeasibleWindowFormatter', () {
    test('merges consecutive slots into ranges', () {
      final slots = [
        DateTime(2026, 7, 1, 22, 0),
        DateTime(2026, 7, 1, 22, 10),
        DateTime(2026, 7, 2, 1, 0),
        DateTime(2026, 7, 2, 1, 10),
      ];

      final ranges = FeasibleWindowFormatter.mergeSlotTimes(slots);

      expect(ranges, hasLength(2));
      expect(ranges.first.start, slots.first);
      expect(ranges.first.end, DateTime(2026, 7, 1, 22, 20));
      expect(ranges.last.start, DateTime(2026, 7, 2, 1, 0));
      expect(ranges.last.end, DateTime(2026, 7, 2, 1, 20));
    });

    test('builds partial-window summary', () {
      final summary = FeasibleWindowFormatter.buildSummary(
        feasibleRanges: [
          (
            start: DateTime(2026, 7, 1, 22, 0),
            end: DateTime(2026, 7, 2, 1, 0),
          ),
        ],
        fullWindowStart: DateTime(2026, 7, 1, 21, 0),
        fullWindowEnd: DateTime(2026, 7, 2, 4, 0),
      );

      expect(summary, '오늘 밤 22:00~01:00만 촬영 가능');
    });

    test('returns null when full window is feasible', () {
      final fullStart = DateTime(2026, 7, 1, 21, 0);
      final fullEnd = DateTime(2026, 7, 2, 4, 0);

      final summary = FeasibleWindowFormatter.buildSummary(
        feasibleRanges: [(start: fullStart, end: fullEnd)],
        fullWindowStart: fullStart,
        fullWindowEnd: fullEnd,
      );

      expect(summary, isNull);
    });
  });
}

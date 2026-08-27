import 'package:astro_journal/services/recommendation/feasible_slot_continuity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FeasibleSlotContinuity', () {
    test('detects minimum 30-minute contiguous feasible blocks', () {
      final slots = [
        DateTime(2026, 7, 1, 22, 0),
        DateTime(2026, 7, 1, 22, 10),
        DateTime(2026, 7, 1, 22, 20),
      ];

      expect(
        FeasibleSlotContinuity.hasMinimumContinuousDuration(slots),
        isTrue,
      );
      expect(FeasibleSlotContinuity.longestContiguousMinutes(slots), 30);
    });

    test('rejects blocks shorter than 30 minutes', () {
      final slots = [
        DateTime(2026, 7, 1, 22, 0),
        DateTime(2026, 7, 1, 22, 10),
      ];

      expect(
        FeasibleSlotContinuity.hasMinimumContinuousDuration(slots),
        isFalse,
      );
    });

    test('filters slots to qualifying contiguous ranges only', () {
      final slots = [
        DateTime(2026, 7, 1, 22, 0),
        DateTime(2026, 7, 1, 22, 10),
        DateTime(2026, 7, 1, 23, 0),
        DateTime(2026, 7, 1, 23, 10),
        DateTime(2026, 7, 1, 23, 20),
      ];

      final allowed = FeasibleSlotContinuity.slotsInRangesAtLeast(slots).toList()
        ..sort();

      expect(allowed, [
        DateTime(2026, 7, 1, 23, 0),
        DateTime(2026, 7, 1, 23, 10),
        DateTime(2026, 7, 1, 23, 20),
      ]);
    });

    test('single-pass analysis preserves continuity results', () {
      final slots = [
        DateTime(2026, 7, 1, 22, 0),
        DateTime(2026, 7, 1, 22, 10),
        DateTime(2026, 7, 1, 23, 0),
        DateTime(2026, 7, 1, 23, 10),
        DateTime(2026, 7, 1, 23, 20),
      ];

      final analysis = FeasibleSlotContinuity.analyze(slots.reversed);

      expect(analysis.hasMinimumContinuousDuration, isTrue);
      expect(analysis.longestMinutes, 30);
      expect(analysis.allowedSlots, slots.skip(2));
      expect(analysis.allowedRanges, [
        (
          start: DateTime(2026, 7, 1, 23, 0),
          end: DateTime(2026, 7, 1, 23, 30),
        ),
      ]);
    });
  });
}

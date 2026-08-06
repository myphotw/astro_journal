import 'package:astro_journal/services/recommendation/feasible_window_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FeasibleWindowFormatter', () {
    test('picks best scoring contiguous range', () {
      final focus = DateTime(2026, 7, 1, 23, 0);
      final range = FeasibleWindowFormatter.bestScoringRange(
        slotScores: {
          DateTime(2026, 7, 1, 22, 0): 40,
          DateTime(2026, 7, 1, 22, 10): 45,
          DateTime(2026, 7, 1, 23, 0): 90,
          DateTime(2026, 7, 1, 23, 10): 85,
        },
        focusTime: focus,
      );

      expect(range?.start, DateTime(2026, 7, 1, 23, 0));
      expect(range?.end, DateTime(2026, 7, 1, 23, 20));
    });
  });
}

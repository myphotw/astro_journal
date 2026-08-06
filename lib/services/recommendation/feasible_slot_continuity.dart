import '../../core/constants/observation_feasibility_config.dart';
import 'feasible_window_formatter.dart';

/// Helpers for contiguous feasible 10-minute slot analysis.
class FeasibleSlotContinuity {
  const FeasibleSlotContinuity._();

  static List<FeasibleTimeRange> mergeRanges(Iterable<DateTime> slotStarts) {
    return FeasibleWindowFormatter.mergeSlotTimes(slotStarts);
  }

  static int longestContiguousMinutes(Iterable<DateTime> slotStarts) {
    final ranges = mergeRanges(slotStarts);
    if (ranges.isEmpty) return 0;

    return ranges
        .map((range) => range.end.difference(range.start).inMinutes)
        .reduce((a, b) => a > b ? a : b);
  }

  static bool hasMinimumContinuousDuration(
    Iterable<DateTime> slotStarts, {
    int minMinutes =
        ObservationFeasibilityConfig.minContinuousShootingMinutes,
  }) {
    final ranges = mergeRanges(slotStarts);
    return ranges.any(
      (range) => range.end.difference(range.start).inMinutes >= minMinutes,
    );
  }

  static Iterable<DateTime> slotsInRangesAtLeast(
    Iterable<DateTime> slotStarts, {
    int minMinutes =
        ObservationFeasibilityConfig.minContinuousShootingMinutes,
  }) {
    final sorted = slotStarts.toList()..sort((a, b) => a.compareTo(b));
    if (sorted.isEmpty) return const [];

    final allowed = <DateTime>{};
    for (final range in mergeRanges(sorted)) {
      if (range.end.difference(range.start).inMinutes < minMinutes) {
        continue;
      }
      for (final slot in sorted) {
        if (!slot.isBefore(range.start) && slot.isBefore(range.end)) {
          allowed.add(slot);
        }
      }
    }
    return allowed;
  }
}

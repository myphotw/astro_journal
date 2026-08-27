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
    int minMinutes = ObservationFeasibilityConfig.minContinuousShootingMinutes,
  }) {
    final ranges = mergeRanges(slotStarts);
    return ranges.any(
      (range) => range.end.difference(range.start).inMinutes >= minMinutes,
    );
  }

  static Iterable<DateTime> slotsInRangesAtLeast(
    Iterable<DateTime> slotStarts, {
    int minMinutes = ObservationFeasibilityConfig.minContinuousShootingMinutes,
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

  static FeasibleSlotAnalysis analyze(
    Iterable<DateTime> slotStarts, {
    int minMinutes = ObservationFeasibilityConfig.minContinuousShootingMinutes,
  }) {
    final sorted = slotStarts.toList()..sort((a, b) => a.compareTo(b));
    return analyzeSorted(sorted, minMinutes: minMinutes);
  }

  static FeasibleSlotAnalysis analyzeSorted(
    List<DateTime> sorted, {
    int minMinutes = ObservationFeasibilityConfig.minContinuousShootingMinutes,
  }) {
    final ranges = FeasibleWindowFormatter.mergeSortedSlotTimes(sorted);
    final allowedRanges = ranges
        .where(
          (range) => range.end.difference(range.start).inMinutes >= minMinutes,
        )
        .toList(growable: false);
    final allowedSlots = <DateTime>[];
    var rangeIndex = 0;
    for (final slot in sorted) {
      while (rangeIndex < allowedRanges.length &&
          !slot.isBefore(allowedRanges[rangeIndex].end)) {
        rangeIndex++;
      }
      if (rangeIndex >= allowedRanges.length) break;
      final range = allowedRanges[rangeIndex];
      if (!slot.isBefore(range.start) && slot.isBefore(range.end)) {
        allowedSlots.add(slot);
      }
    }
    final longestMinutes = ranges.isEmpty
        ? 0
        : ranges
              .map((range) => range.end.difference(range.start).inMinutes)
              .reduce((a, b) => a > b ? a : b);
    return FeasibleSlotAnalysis(
      sortedSlots: sorted,
      ranges: ranges,
      allowedSlots: allowedSlots,
      allowedRanges: allowedRanges,
      longestMinutes: longestMinutes,
    );
  }
}

class FeasibleSlotAnalysis {
  const FeasibleSlotAnalysis({
    required this.sortedSlots,
    required this.ranges,
    required this.allowedSlots,
    required this.allowedRanges,
    required this.longestMinutes,
  });

  final List<DateTime> sortedSlots;
  final List<FeasibleTimeRange> ranges;
  final List<DateTime> allowedSlots;
  final List<FeasibleTimeRange> allowedRanges;
  final int longestMinutes;

  bool get hasMinimumContinuousDuration => allowedRanges.isNotEmpty;
}

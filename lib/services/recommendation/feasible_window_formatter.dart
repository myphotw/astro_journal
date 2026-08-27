import '../scheduler_engine.dart';

/// Time range where target observation is feasible (weather + site constraints).
typedef FeasibleTimeRange = ({DateTime start, DateTime end});

/// Merges slot timestamps and formats user-facing feasibility summaries.
class FeasibleWindowFormatter {
  const FeasibleWindowFormatter._();

  static const _slotDuration = SchedulerEngine.slotDuration;

  static List<FeasibleTimeRange> mergeSlotTimes(Iterable<DateTime> slotStarts) {
    final sorted = slotStarts.toList()..sort((a, b) => a.compareTo(b));
    return mergeSortedSlotTimes(sorted);
  }

  static List<FeasibleTimeRange> mergeSortedSlotTimes(List<DateTime> sorted) {
    if (sorted.isEmpty) return const [];

    final ranges = <FeasibleTimeRange>[];
    var rangeStart = sorted.first;
    var rangeEnd = sorted.first.add(_slotDuration);

    for (var i = 1; i < sorted.length; i++) {
      final slot = sorted[i];
      if (slot.isBefore(rangeEnd) || slot.isAtSameMomentAs(rangeEnd)) {
        rangeEnd = slot.add(_slotDuration);
      } else {
        ranges.add((start: rangeStart, end: rangeEnd));
        rangeStart = slot;
        rangeEnd = slot.add(_slotDuration);
      }
    }
    ranges.add((start: rangeStart, end: rangeEnd));
    return ranges;
  }

  static FeasibleTimeRange? bestScoringRange({
    required Map<DateTime, double> slotScores,
    DateTime? focusTime,
    List<FeasibleTimeRange>? precomputedRanges,
  }) {
    if (slotScores.isEmpty) return null;

    final ranges = precomputedRanges ?? mergeSlotTimes(slotScores.keys);
    FeasibleTimeRange? best;
    var bestScore = -1.0;

    for (final range in ranges) {
      final slots = slotScores.entries.where((entry) {
        return !entry.key.isBefore(range.start) &&
            entry.key.isBefore(range.end);
      });
      if (slots.isEmpty) continue;

      final average =
          slots.map((entry) => entry.value).reduce((a, b) => a + b) /
          slots.length;

      final containsFocus =
          focusTime != null &&
          !focusTime.isBefore(range.start) &&
          focusTime.isBefore(range.end);

      if (average > bestScore || (average == bestScore && containsFocus)) {
        bestScore = average;
        best = range;
      }
    }

    return best ?? ranges.first;
  }

  /// e.g. "오늘 밤 22:00~01:00만 촬영 가능" or null when full window is feasible.
  static String? buildSummary({
    required List<FeasibleTimeRange> feasibleRanges,
    DateTime? fullWindowStart,
    DateTime? fullWindowEnd,
  }) {
    if (feasibleRanges.isEmpty) return '오늘 밤 촬영 가능 시간 없음';

    if (fullWindowStart != null &&
        fullWindowEnd != null &&
        feasibleRanges.length == 1) {
      final range = feasibleRanges.first;
      if (!range.start.isAfter(
            fullWindowStart.add(const Duration(minutes: 10)),
          ) &&
          !range.end.isBefore(fullWindowEnd)) {
        return null;
      }
    }

    final windows = feasibleRanges
        .map((range) => '${_formatTime(range.start)}~${_formatTime(range.end)}')
        .join(', ');

    if (feasibleRanges.length == 1 &&
        fullWindowStart != null &&
        fullWindowEnd != null) {
      return '오늘 밤 $windows만 촬영 가능';
    }

    return '오늘 밤 $windows 촬영 가능';
  }

  static String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }
}

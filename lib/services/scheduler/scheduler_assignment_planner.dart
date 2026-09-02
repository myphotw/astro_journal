import '../../data/models/imaging_suitability_assessment.dart';
import '../../data/models/object_observation_window.dart';
import '../../data/models/observation_context.dart';
import '../../data/models/recommendation_result.dart';
import '../../data/models/scheduler_models.dart';
import '../../data/models/scored_observation_target.dart';
import '../celestial_position_service.dart';
import '../equipment/alt_az_imaging_policy.dart';
import '../scheduler_engine.dart';

class _TargetAssignmentPlan {
  const _TargetAssignmentPlan({required this.target, required this.priority});

  final ScoredObservationTarget target;
  final double priority;
}

/// Assigns shooting blocks to 10-minute slots without overlap.
abstract final class SchedulerAssignmentPlanner {
  static List<ScheduleItem> assign({
    required List<ScheduleSlot> slots,
    required List<ScoredObservationTarget> targets,
    required Map<String, RecommendationResult> resultsById,
    required ObservationContext context,
  }) {
    final occupied = <DateTime>{};
    final items = <ScheduleItem>[];

    final plans =
        targets
            .map(
              (target) => _TargetAssignmentPlan(
                target: target,
                priority: target.schedulerPriority,
              ),
            )
            .toList()
          ..sort((a, b) => b.priority.compareTo(a.priority));

    for (final plan in plans) {
      final target = plan.target;
      final window = target.window;
      final recommendStart = window.recommendStartTime;
      final observationEnd = window.observationEndTime;
      if (recommendStart == null || observationEnd == null) continue;

      final minSlots = _slotCountFor(target.minimumExposure);
      final assessment = target.imagingAssessment;
      final scheduledRecommendedExposure =
          assessment?.trackingMode == TrackingMode.altAz
              ? assessment?.recommendedDailyExposure ??
                  target.recommendedExposure
              : target.recommendedExposure;
      if (scheduledRecommendedExposure <= Duration.zero) continue;
      final recSlots = _slotCountFor(scheduledRecommendedExposure);
      final targetSlotStarts = window.slotObservationScores.keys.toSet();

      final candidateCenters = _rankCandidateCenters(
        window: window,
        slots: slots,
        occupied: occupied,
        recommendStart: recommendStart,
        observationEnd: observationEnd,
        context: context,
        target: target,
        targetSlotStarts: targetSlotStarts,
      );

      List<ScheduleSlot>? selected;
      DateTime? chosenOptimal;

      for (final center in candidateCenters) {
        final block = _findBestBlock(
          slots: slots,
          occupied: occupied,
          recommendStart: recommendStart,
          observationEnd: observationEnd,
          optimalTime: center.time,
          minSlots: minSlots,
          maxSlots: recSlots,
          targetSlotStarts: targetSlotStarts,
        );
        if (block.length >= minSlots) {
          selected = block;
          chosenOptimal = center.time;
          break;
        }
      }

      if (selected == null || chosenOptimal == null) continue;

      for (final slot in selected) {
        occupied.add(slot.start);
      }

      final startTime = selected.first.start;
      final endTime = selected.last.end;
      final shootingDuration = Duration(
        minutes: selected.length * SchedulerEngine.slotDuration.inMinutes,
      );
      final status = _resolveStatus(
        shootingDuration: shootingDuration,
        minimumExposure: target.minimumExposure,
        recommendedExposure: scheduledRecommendedExposure,
        windowMinutes: window.totalObservableMinutes,
      );

      final result = resultsById[target.object.id];
      if (result == null) continue;

      items.add(
        ScheduleItem(
          target: target,
          startTime: startTime,
          endTime: endTime,
          shootingDuration: shootingDuration,
          recommendedDuration: scheduledRecommendedExposure,
          optimalTime: chosenOptimal,
          optimalAltitude: window.optimalAltitude ?? window.peakAltitude ?? 0,
          recommendationScore: target.score,
          schedulerPriority: target.schedulerPriority,
          urgencyScore: target.urgencyScore,
          status: status,
          result: result,
          haMatchQuality: _haMatchQualityForBlock(
            target: target,
            context: context,
            start: startTime,
            end: endTime,
          ),
        ),
      );
    }

    items.sort((a, b) {
      final cmp = a.startTime.compareTo(b.startTime);
      if (cmp != 0) return cmp;
      return b.schedulerPriority.compareTo(a.schedulerPriority);
    });

    return items;
  }

  static List<({DateTime time, double score})> _rankCandidateCenters({
    required ObjectObservationWindow window,
    required List<ScheduleSlot> slots,
    required Set<DateTime> occupied,
    required DateTime recommendStart,
    required DateTime observationEnd,
    required ObservationContext context,
    required ScoredObservationTarget target,
    required Set<DateTime> targetSlotStarts,
  }) {
    final windowEnd = observationEnd.add(SchedulerEngine.slotDuration);
    final candidates = <({DateTime time, double score})>[];

    for (final slot in slots) {
      if (slot.start.isBefore(recommendStart) ||
          !slot.end.isBefore(windowEnd) ||
          occupied.contains(slot.start) ||
          (targetSlotStarts.isNotEmpty &&
              !targetSlotStarts.contains(slot.start))) {
        continue;
      }

      final observationScore =
          window.slotObservationScores[slot.start] ??
          context.siteSlotScores[slot.start] ??
          window.bestObservationScore;
      final haMatchQuality = _haMatchQualityAt(
        target: target,
        context: context,
        time: slot.start,
      );
      final score = observationScore +
          (haMatchQuality ?? 0) * AltAzImagingPolicy.schedulerHaBonusWeight;
      candidates.add((time: slot.start, score: score));
    }

    candidates.sort((a, b) => b.score.compareTo(a.score));
    return candidates;
  }

  static List<ScheduleSlot> _findBestBlock({
    required List<ScheduleSlot> slots,
    required Set<DateTime> occupied,
    required DateTime recommendStart,
    required DateTime observationEnd,
    required DateTime optimalTime,
    required int minSlots,
    required int maxSlots,
    required Set<DateTime> targetSlotStarts,
  }) {
    final windowEnd = observationEnd.add(SchedulerEngine.slotDuration);
    final freeInWindow = slots
        .where(
          (slot) =>
              !slot.start.isBefore(recommendStart) &&
              slot.end.isBefore(windowEnd) &&
              !occupied.contains(slot.start) &&
              (targetSlotStarts.isEmpty ||
                  targetSlotStarts.contains(slot.start)),
        )
        .toList();

    final runs = _contiguousRuns(freeInWindow);
    for (final run in runs) {
      if (run.length < minSlots) continue;

      final optimalIndex = run.indexWhere(
        (slot) =>
            !optimalTime.isBefore(slot.start) && optimalTime.isBefore(slot.end),
      );
      if (optimalIndex < 0) continue;

      return _expandWithinRun(
        run: run,
        centerIndex: optimalIndex,
        minSlots: minSlots,
        maxSlots: maxSlots.clamp(minSlots, run.length),
      );
    }

    return const [];
  }

  static List<List<ScheduleSlot>> _contiguousRuns(List<ScheduleSlot> slots) {
    if (slots.isEmpty) return const [];

    final runs = <List<ScheduleSlot>>[];
    var current = <ScheduleSlot>[slots.first];

    for (var i = 1; i < slots.length; i++) {
      if (slots[i].start == current.last.end) {
        current.add(slots[i]);
      } else {
        runs.add(current);
        current = [slots[i]];
      }
    }
    runs.add(current);
    return runs;
  }

  static List<ScheduleSlot> _expandWithinRun({
    required List<ScheduleSlot> run,
    required int centerIndex,
    required int minSlots,
    required int maxSlots,
  }) {
    final selected = <ScheduleSlot>[run[centerIndex]];
    var left = centerIndex - 1;
    var right = centerIndex + 1;
    final targetCount = maxSlots.clamp(minSlots, run.length);

    while (selected.length < targetCount) {
      final canLeft = left >= 0;
      final canRight = right < run.length;
      if (!canLeft && !canRight) break;

      if (canLeft && canRight) {
        if (selected.length.isOdd) {
          selected.insert(0, run[left]);
          left--;
        } else {
          selected.add(run[right]);
          right++;
        }
      } else if (canLeft) {
        selected.insert(0, run[left]);
        left--;
      } else {
        selected.add(run[right]);
        right++;
      }
    }

    while (selected.length < minSlots) {
      if (left >= 0) {
        selected.insert(0, run[left]);
        left--;
      } else if (right < run.length) {
        selected.add(run[right]);
        right++;
      } else {
        break;
      }
    }

    return selected;
  }

  static int _slotCountFor(Duration duration) {
    final minutes = duration.inMinutes;
    if (minutes <= 0) return 1;
    return (minutes / SchedulerEngine.slotDuration.inMinutes).ceil();
  }

  static double? _haMatchQualityAt({
    required ScoredObservationTarget target,
    required ObservationContext context,
    required DateTime time,
  }) {
    final assessment = target.imagingAssessment;
    final preferred = assessment?.preferredHaWindow;
    if (assessment == null ||
        assessment.trackingMode != TrackingMode.altAz ||
        preferred == null) {
      return null;
    }
    return AltAzImagingPolicy.haMatchQuality(
      preferred: preferred,
      longitudeDeg: context.longitude,
      candidateCenter: time,
      raHours: CelestialPositionService.parseRaHours(target.object.ra),
    );
  }

  static double? _haMatchQualityForBlock({
    required ScoredObservationTarget target,
    required ObservationContext context,
    required DateTime start,
    required DateTime end,
  }) {
    final center = start.add(
      Duration(minutes: end.difference(start).inMinutes ~/ 2),
    );
    return _haMatchQualityAt(
      target: target,
      context: context,
      time: center,
    );
  }

  static ScheduleItemStatus _resolveStatus({
    required Duration shootingDuration,
    required Duration minimumExposure,
    required Duration recommendedExposure,
    required int windowMinutes,
  }) {
    if (shootingDuration >= recommendedExposure) {
      return ScheduleItemStatus.optimal;
    }

    final recommendedRatio =
        shootingDuration.inMinutes / recommendedExposure.inMinutes;
    if (recommendedRatio >= 0.85) {
      return ScheduleItemStatus.recommended;
    }

    if (shootingDuration >= minimumExposure) {
      if (windowMinutes <= minimumExposure.inMinutes + 10) {
        return ScheduleItemStatus.minimumOnly;
      }
      return ScheduleItemStatus.belowRecommended;
    }

    return ScheduleItemStatus.excluded;
  }
}

import '../core/services/performance_probe.dart';
import '../data/models/observation_status.dart';
import '../data/models/scheduler_models.dart';
import '../data/models/scored_observation_target.dart';
import '../data/models/tonight_observation_session.dart';
import 'scheduler/scheduler_assignment_planner.dart';
import 'scheduler/scheduler_priority_calculator.dart';

/// Builds a 10-minute slot grid and assigns targets to shooting blocks.
class SchedulerEngine {
  const SchedulerEngine({SchedulerPriorityCalculator? priorityCalculator})
    : _priorityCalculator =
          priorityCalculator ?? const SchedulerPriorityCalculator();

  static const slotDuration = Duration(minutes: 10);
  static const assignmentEmptyMessage =
      '최소 촬영시간을 만족하는 연속 촬영 구간을 배정할 수 없습니다.';
  static const weatherLimitedMessage = '기상 예보상 자동 촬영 추천이 제한됩니다.';

  final SchedulerPriorityCalculator _priorityCalculator;

  List<ScheduleSlot> generateSlots(TonightObservationSession session) {
    final slots = <ScheduleSlot>[];
    var cursor = _alignToSlot(session.start);

    while (cursor.isBefore(session.end)) {
      final end = cursor.add(slotDuration);
      if (end.isAfter(session.end)) {
        break;
      }
      slots.add(ScheduleSlot(start: cursor, end: end));
      cursor = end;
    }

    return slots;
  }

  ScheduleResult buildSchedule(SchedulerInput input) =>
      PerformanceProbe.measure(
        'scheduler.build',
        () => _buildSchedule(input),
        state: 'targets=${input.targets.length}',
      );

  ScheduleResult _buildSchedule(SchedulerInput input) {
    // Weather affects target scores, but not the astronomical slot grid.
    final slots = PerformanceProbe.measure(
      'scheduler.visible_slots',
      () => _generateFeasibleSlots(input),
      state: 'targets=${input.targets.length}',
    );
    final prioritizedTargets = PerformanceProbe.measure(
      'scheduler.candidate_preparation',
      () => _applySchedulerPriorities(input),
      state: 'targets=${input.targets.length}',
    );
    final hasTargets = input.targets.isNotEmpty;
    final isEmptyDueToFeasibility = hasTargets && slots.isEmpty;

    if (!input.context.observationStatus.allowsScheduling) {
      return ScheduleResult(
        slots: slots,
        targets: prioritizedTargets,
        items: const [],
        isEmptyDueToFeasibility: hasTargets,
        emptyMessage: weatherLimitedMessage,
      );
    }

    if (isEmptyDueToFeasibility) {
      return ScheduleResult(
        slots: slots,
        targets: prioritizedTargets,
        items: const [],
        isEmptyDueToFeasibility: true,
        emptyMessage: assignmentEmptyMessage,
      );
    }

    final items = PerformanceProbe.measure(
      'scheduler.assignment_planner',
      () => SchedulerAssignmentPlanner.assign(
        slots: slots,
        targets: prioritizedTargets,
        resultsById: input.resultsById,
        context: input.context,
        suitabilityByObjectId: input.suitabilityByObjectId,
        occupiedWindows: input.occupiedWindows,
      ),
      state: 'targets=${input.targets.length} slots=${slots.length}',
    );
    final hasUsableItems = items.any(
      (item) => item.status != ScheduleItemStatus.excluded,
    );

    return ScheduleResult(
      slots: slots,
      targets: prioritizedTargets,
      items: items,
      emptyMessage: hasTargets && !hasUsableItems
          ? assignmentEmptyMessage
          : null,
    );
  }

  List<ScheduleSlot> _generateFeasibleSlots(SchedulerInput input) {
    return generateSlots(input.session)
        .where((slot) => !slot.start.isBefore(input.referenceTime))
        .toList();
  }

  List<ScoredObservationTarget> _applySchedulerPriorities(
    SchedulerInput input,
  ) {
    return input.targets.map((target) {
      final priority = _priorityCalculator.calculate(
        target: target,
        context: input.context,
        referenceTime: input.referenceTime,
      );

      return target.copyWith(
        schedulerPriority: priority.schedulerPriority,
        urgencyScore: priority.urgencyScore,
        window: target.window.copyWith(
          urgencyScore: priority.urgencyScore,
          schedulerPriority: priority.schedulerPriority,
        ),
      );
    }).toList();
  }

  DateTime _alignToSlot(DateTime time) {
    final remainder = time.minute % slotDuration.inMinutes;
    if (remainder == 0 && time.second == 0 && time.millisecond == 0) {
      return time;
    }

    final addMinutes = remainder == 0
        ? slotDuration.inMinutes
        : slotDuration.inMinutes - remainder;
    return time
        .add(Duration(minutes: addMinutes))
        .copyWith(second: 0, millisecond: 0, microsecond: 0);
  }
}

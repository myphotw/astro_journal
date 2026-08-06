import '../data/models/observation_status.dart';
import '../data/models/scheduler_models.dart';
import '../data/models/scored_observation_target.dart';
import '../data/models/tonight_observation_session.dart';
import 'recommendation/feasibility_exclusion_messages.dart';
import 'recommendation/feasible_slot_continuity.dart';
import 'scheduler/scheduler_assignment_planner.dart';
import 'scheduler/scheduler_priority_calculator.dart';

/// Builds a 10-minute slot grid and assigns targets to shooting blocks.
class SchedulerEngine {
  const SchedulerEngine({
    SchedulerPriorityCalculator? priorityCalculator,
  }) : _priorityCalculator = priorityCalculator ?? const SchedulerPriorityCalculator();

  static const slotDuration = Duration(minutes: 10);

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

  ScheduleResult buildSchedule(SchedulerInput input) {
    // 관측 불가여도 기상 무시 슬롯으로 스케줄은 계속 계산한다.
    final slots = _generateFeasibleSlots(input);
    final prioritizedTargets = _applySchedulerPriorities(input);
    final hasTargets = input.targets.isNotEmpty;
    final isEmptyDueToFeasibility = hasTargets && slots.isEmpty;

    if (isEmptyDueToFeasibility) {
      return ScheduleResult(
        slots: slots,
        targets: prioritizedTargets,
        items: const [],
        isEmptyDueToFeasibility: true,
        emptyMessage: FeasibilityExclusionMessages.scheduleEmptyMessage,
      );
    }

    final items = SchedulerAssignmentPlanner.assign(
      slots: slots,
      targets: prioritizedTargets,
      resultsById: input.resultsById,
      siteSlotScores: input.context.siteSlotScores,
    );

    return ScheduleResult(
      slots: slots,
      targets: prioritizedTargets,
      items: items,
    );
  }

  List<ScheduleSlot> _generateFeasibleSlots(SchedulerInput input) {
    final slots = generateSlots(input.session);
    // 관측 불가(기상) 시에는 전체 세션 슬롯을 사용해 촬영 순서를 제안한다.
    if (input.context.observationStatus == ObservationStatus.unavailable) {
      return slots;
    }
    final feasibility = input.context.siteSlotFeasibility;
    if (feasibility.isEmpty) {
      return slots;
    }

    final feasibleStarts = slots
        .where((slot) => feasibility[slot.start]?.canObserve ?? false)
        .map((slot) => slot.start);
    final allowed =
        FeasibleSlotContinuity.slotsInRangesAtLeast(feasibleStarts).toSet();

    return slots.where((slot) => allowed.contains(slot.start)).toList();
  }

  List<ScoredObservationTarget> _applySchedulerPriorities(SchedulerInput input) {
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

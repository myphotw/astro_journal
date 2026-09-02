import '../../services/observation_score_service.dart';
import 'catalog_object.dart';
import 'observation_context.dart';
import 'recommendation_result.dart';
import 'scored_observation_target.dart';
import 'tonight_observation_session.dart';

class ScheduleSlot {
  const ScheduleSlot({
    required this.start,
    required this.end,
  });

  final DateTime start;
  final DateTime end;
}

class ScheduledTarget {
  const ScheduledTarget({
    required this.catalogId,
    required this.slot,
    required this.target,
  });

  final String catalogId;
  final ScheduleSlot slot;
  final ScoredObservationTarget target;
}

enum ScheduleItemStatus {
  optimal,
  recommended,
  belowRecommended,
  minimumOnly,
  excluded,
}

extension ScheduleItemStatusLabel on ScheduleItemStatus {
  String get label => switch (this) {
        ScheduleItemStatus.optimal => '최적',
        ScheduleItemStatus.recommended => '권장',
        ScheduleItemStatus.belowRecommended => '권장 미달',
        ScheduleItemStatus.minimumOnly => '최소 촬영만 가능',
        ScheduleItemStatus.excluded => '추천 제외',
      };
}

class ScheduleItem {
  const ScheduleItem({
    required this.target,
    required this.startTime,
    required this.endTime,
    required this.shootingDuration,
    required this.recommendedDuration,
    required this.optimalTime,
    required this.optimalAltitude,
    required this.recommendationScore,
    required this.schedulerPriority,
    required this.urgencyScore,
    required this.status,
    required this.result,
    this.haMatchQuality,
  });

  final ScoredObservationTarget target;
  final DateTime startTime;
  final DateTime endTime;
  final Duration shootingDuration;
  final Duration recommendedDuration;
  final DateTime optimalTime;
  final double optimalAltitude;
  final double recommendationScore;
  final double schedulerPriority;
  final double urgencyScore;
  final ScheduleItemStatus status;
  final RecommendationResult result;
  final double? haMatchQuality;

  CatalogObject get catalogObject => target.object;

  String get displayName => target.object.displayName;

  String get displayCommonName => target.object.displayCommonName;

  double get score => recommendationScore;

  int get starCount =>
      ObservationScoreService.recommendationStarCount(recommendationScore.round());

  String get durationLabel {
    final minutes = shootingDuration.inMinutes;
    if (shootingDuration >= recommendedDuration) {
      return '$minutes분(권장 충족)';
    }
    return '$minutes분(권장 ${recommendedDuration.inMinutes}분)';
  }
}

class SchedulerInput {
  const SchedulerInput({
    required this.context,
    required this.session,
    required this.targets,
    required this.resultsById,
    required this.referenceTime,
    this.currentAltitudes = const {},
    this.meridianPassTimes = const {},
    this.settingTimes = const {},
  });

  final ObservationContext context;
  final TonightObservationSession session;
  final List<ScoredObservationTarget> targets;
  final Map<String, RecommendationResult> resultsById;
  final DateTime referenceTime;
  final Map<String, double> currentAltitudes;
  final Map<String, DateTime> meridianPassTimes;
  final Map<String, DateTime> settingTimes;
}

class ScheduleResult {
  const ScheduleResult({
    required this.slots,
    this.targets = const [],
    this.items = const [],
    this.assignments = const [],
    this.isEmptyDueToFeasibility = false,
    this.emptyMessage,
  });

  final List<ScheduleSlot> slots;
  final List<ScoredObservationTarget> targets;
  final List<ScheduleItem> items;
  final List<ScheduledTarget> assignments;
  final bool isEmptyDueToFeasibility;
  final String? emptyMessage;
}

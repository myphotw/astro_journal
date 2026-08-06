import '../../../core/constants/scheduler_priority_weights.dart';
import '../../../data/models/observation_context.dart';
import '../../../data/models/scored_observation_target.dart';
import 'scoring/exposure_priority.dart';
import 'scoring/light_pollution_priority.dart';
import 'scoring/moon_priority.dart';
import 'scoring/urgency_score.dart';

/// Computes shooting order priority independent from recommendation ranking.
class SchedulerPriorityCalculator {
  const SchedulerPriorityCalculator({
    this.urgencyScore = const UrgencyScore(),
    this.moonPriority = const MoonPriority(),
    this.lightPollutionPriority = const LightPollutionPriority(),
    this.exposurePriority = const ExposurePriority(),
  });

  final UrgencyScore urgencyScore;
  final MoonPriority moonPriority;
  final LightPollutionPriority lightPollutionPriority;
  final ExposurePriority exposurePriority;

  SchedulerPriorityResult calculate({
    required ScoredObservationTarget target,
    required ObservationContext context,
    required DateTime referenceTime,
  }) {
    final window = target.window;
    final urgency = urgencyScore.calculate(
      window: window,
      recommendedExposure: target.recommendedExposure,
      referenceTime: referenceTime,
    );
    final moon = moonPriority.calculate(
      profile: target.profile,
      moonSafeMinutes: window.moonSafeMinutes,
    );
    final lightPollution = lightPollutionPriority.calculate(
      profile: target.profile,
      context: context,
    );
    final observation = window.bestObservationScore;
    final exposure = exposurePriority.calculate(
      window: window,
      recommendedExposure: target.recommendedExposure,
    );
    final recommendation = target.score;

    final priority = urgency * SchedulerPriorityWeights.urgency +
        moon * SchedulerPriorityWeights.moon +
        lightPollution * SchedulerPriorityWeights.lightPollution +
        observation * SchedulerPriorityWeights.observation +
        exposure * SchedulerPriorityWeights.exposure +
        recommendation * SchedulerPriorityWeights.recommendation;

    return SchedulerPriorityResult(
      schedulerPriority: priority.clamp(0.0, 100.0),
      urgencyScore: urgency,
      moonPriority: moon,
      lightPollutionPriority: lightPollution,
      observationScore: observation,
      exposurePriority: exposure,
    );
  }
}

class SchedulerPriorityResult {
  const SchedulerPriorityResult({
    required this.schedulerPriority,
    required this.urgencyScore,
    required this.moonPriority,
    required this.lightPollutionPriority,
    required this.observationScore,
    required this.exposurePriority,
  });

  final double schedulerPriority;
  final double urgencyScore;
  final double moonPriority;
  final double lightPollutionPriority;
  final double observationScore;
  final double exposurePriority;
}

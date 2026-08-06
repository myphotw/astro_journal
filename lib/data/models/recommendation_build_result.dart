import 'observation_session.dart';

import 'recommendation_result.dart';

import 'scheduler_models.dart';

import 'scored_observation_target.dart';

import 'tonight_observation_session.dart';



/// Output of [RecommendationEngine.build].

class RecommendationBuildResult {

  const RecommendationBuildResult({

    required this.session,

    required this.recommendations,

    required this.allRecommendations,

    required this.scheduleItems,

    required this.exclusionReasons,

    required this.scheduleResult,

    required this.scoredTargets,

  });



  final TonightObservationSession session;

  final List<RecommendationResult> recommendations;

  final List<RecommendationResult> allRecommendations;

  final List<ScheduleItem> scheduleItems;

  final List<String> exclusionReasons;

  final ScheduleResult scheduleResult;

  final List<ScoredObservationTarget> scoredTargets;



  @Deprecated('Use scheduleItems instead')

  List<ObservationSession> get sessions => const [];

}


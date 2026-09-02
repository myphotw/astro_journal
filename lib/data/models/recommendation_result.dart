import '../../services/observation_score_service.dart';
import 'object_observation_window.dart';
import 'recommendation_reason.dart';
import 'catalog_object.dart';
import 'imaging_suitability_assessment.dart';

/// Output of the target recommendation algorithm (v2.1).
class RecommendationResult {
  const RecommendationResult({
    required this.object,
    required this.reasons,
    required this.season,
    required this.score,
    required this.moonSeparation,
    this.observationWindow,
    this.imagingAssessment,
    this.minimumExposure,
    this.recommendedExposure,
    this.observingConditionScore = 0,
  });

  final CatalogObject object;
  final List<RecommendationReason> reasons;
  final String season;

  /// Composite score (0–100) including moon-separation penalty.
  final double score;

  /// Angular distance from the Moon at recommendation time (degrees).
  final double moonSeparation;

  final ObjectObservationWindow? observationWindow;
  final ImagingSuitabilityAssessment? imagingAssessment;
  final Duration? minimumExposure;
  final Duration? recommendedExposure;
  final double observingConditionScore;

  Duration? get recommendedTotalIntegration => recommendedExposure;

  Duration? get recommendedDailyIntegration =>
      imagingAssessment?.recommendedDailyExposure ?? recommendedExposure;

  /// Primary reason label (backward compatibility).
  String get reason => reasons.isNotEmpty ? reasons.first.label : '오늘 밤 관측 가능';

  double get successRate => score.clamp(0, 100);

  int get starCount =>
      ObservationScoreService.recommendationStarCount(score.round());

  RecommendationResult copyWith({
    double? score,
    ImagingSuitabilityAssessment? imagingAssessment,
  }) {
    return RecommendationResult(
      object: object,
      reasons: reasons,
      season: season,
      score: score ?? this.score,
      moonSeparation: moonSeparation,
      observationWindow: observationWindow,
      imagingAssessment: imagingAssessment ?? this.imagingAssessment,
      minimumExposure: minimumExposure,
      recommendedExposure: recommendedExposure,
      observingConditionScore: observingConditionScore,
    );
  }
}

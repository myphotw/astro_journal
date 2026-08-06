import '../../services/observation_score_service.dart';
import 'object_observation_window.dart';
import 'recommendation_reason.dart';
import 'catalog_object.dart';

/// Output of the target recommendation algorithm (v2.1).
class RecommendationResult {
  const RecommendationResult({
    required this.object,
    required this.reasons,
    required this.season,
    required this.score,
    required this.moonSeparation,
    this.observationWindow,
  });

  final CatalogObject object;
  final List<RecommendationReason> reasons;
  final String season;

  /// Composite score (0–100) including moon-separation penalty.
  final double score;

  /// Angular distance from the Moon at recommendation time (degrees).
  final double moonSeparation;

  final ObjectObservationWindow? observationWindow;

  /// Primary reason label (backward compatibility).
  String get reason =>
      reasons.isNotEmpty ? reasons.first.label : '오늘 밤 관측 가능';

  double get successRate => score.clamp(0, 100);

  int get starCount =>
      ObservationScoreService.recommendationStarCount(score.round());
}

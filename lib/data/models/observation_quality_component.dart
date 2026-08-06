import '../../services/observation_score_service.dart';

/// A single environmental quality factor contributing to OQI.
class ObservationQualityComponent {
  const ObservationQualityComponent({
    required this.category,
    required this.quality,
  });

  final String category;
  final double quality;

  int get qualityPoints => quality.round().clamp(0, 100);

  int get starCount =>
      ObservationScoreService.recommendationStarCount(qualityPoints);

  String get starLabel => '★' * starCount + '☆' * (5 - starCount);
}

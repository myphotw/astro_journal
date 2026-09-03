import 'catalog_object.dart';
import 'object_observation_window.dart';
import 'recommendation_result.dart';

/// A site-specific, reusable availability projection for one catalog target.
///
/// It deliberately retains the [RecommendationResult] produced by the shared
/// recommendation engine so mobile and future desktop clients present the
/// same visibility and imaging policy.
class TargetImagingAvailability {
  const TargetImagingAvailability({
    required this.object,
    required this.referenceDate,
    required this.isAvailableTonight,
    this.recommendation,
    this.primaryReason,
    this.tomorrow,
    this.observableSeasonLabel,
    this.optimalSeasonLabel,
  });

  final CatalogObject object;
  final DateTime referenceDate;
  final bool isAvailableTonight;
  final RecommendationResult? recommendation;
  final String? primaryReason;
  /// Tomorrow uses the same astronomical pipeline without weather inputs.
  final TargetImagingAvailability? tomorrow;
  final String? observableSeasonLabel;
  final String? optimalSeasonLabel;

  ObjectObservationWindow? get window => recommendation?.observationWindow;

  bool get isDifficultTonight =>
      isAvailableTonight &&
      (recommendation?.imagingAssessment?.quality.index ?? 2) <= 1;

  String get tonightStatusLabel {
    if (!isAvailableTonight) return '촬영 불가';
    return isDifficultTonight ? '촬영 어려움' : '촬영 가능';
  }
}

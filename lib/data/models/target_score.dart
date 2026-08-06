import 'catalog_object.dart';

/// Evaluation result for a single catalog target.
class TargetScore {
  const TargetScore({
    required this.catalogId,
    required this.catalogObject,
    required this.score,
    required this.recommendReason,
    required this.visibleStart,
    required this.visibleEnd,
    required this.minimumExposure,
    required this.recommendedExposure,
    required this.recommended,
  });

  final String catalogId;
  final CatalogObject catalogObject;
  final double score;
  final String recommendReason;
  final DateTime visibleStart;
  final DateTime visibleEnd;
  final Duration minimumExposure;
  final Duration recommendedExposure;
  final bool recommended;
}

import 'catalog_object.dart';
import 'recommendation_result.dart';

/// Ordered shooting slot for tonight's observation session.
class ObservationSession {
  const ObservationSession({
    required this.target,
    required this.startTime,
    required this.bestTime,
    required this.endTime,
    required this.maxAltitude,
    required this.score,
    required this.result,
  });

  final CatalogObject target;
  final DateTime startTime;
  final DateTime bestTime;
  final DateTime endTime;
  final double maxAltitude;
  final double score;
  final RecommendationResult result;
}

import 'observation_quality_component.dart';

/// Observation Quality Index — site-level environmental observation quality.
class ObservationQualityIndex {
  const ObservationQualityIndex({
    required this.components,
    this.oqi,
    this.isObservable = true,
    this.primaryInfeasibleReason,
    this.userMessage,
  });

  const ObservationQualityIndex.infeasible({
    required this.primaryInfeasibleReason,
    required this.userMessage,
    this.components = const [],
  })  : oqi = null,
        isObservable = false;

  final double? oqi;
  final bool isObservable;
  final List<ObservationQualityComponent> components;
  final String? primaryInfeasibleReason;
  final String? userMessage;

  int get score => oqi?.round().clamp(0, 100) ?? 0;

  int get starCount {
    if (!isObservable) return 0;
    if (score >= 90) return 5;
    if (score >= 75) return 4;
    if (score >= 60) return 3;
    if (score >= 40) return 2;
    return 1;
  }

  ObservationQualityComponent? componentFor(String category) {
    for (final item in components) {
      if (item.category == category) return item;
    }
    return null;
  }
}

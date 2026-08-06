/// Structured recommendation reason — decouples algorithm labels from UI.
enum RecommendationReasonType {
  uncaptured,
  currentAltitude,
  currentlyVisible,
  shootingWindow,
  moonSeparation,
  cloud,
  wind,
  season,
  settings,
  observableTime,
}

class RecommendationReason {
  const RecommendationReason({
    required this.type,
    required this.label,
  });

  final RecommendationReasonType type;
  final String label;
}

/// Variability of observation scores across a time window.
class ObservationStability {
  const ObservationStability({
    required this.score,
    required this.starCount,
    required this.label,
    required this.description,
    required this.standardDeviation,
  });

  final int score;
  final int starCount;
  final String label;
  final String description;
  final double standardDeviation;
}

/// Display row for how a factor contributed to the observation score.
class ObservationScoreContribution {
  const ObservationScoreContribution({
    required this.category,
    required this.points,
    required this.starCount,
    this.label = '',
  });

  final String category;
  final int points;
  final int starCount;
  final String label;
}

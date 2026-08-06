/// Admin-configurable recommendation list sort strategy.
enum RecommendationPriorityMode {
  /// Uncaptured targets always rank above captured ones.
  uncapturedFirst('uncaptured_first', '미촬영 우선'),

  /// Highest recommendation score first.
  scoreFirst('score_first', '점수 우선'),

  /// Score plus a bonus for uncaptured targets.
  mixed('mixed', '혼합');

  const RecommendationPriorityMode(this.storageValue, this.label);

  final String storageValue;
  final String label;

  static RecommendationPriorityMode fromStorageValue(String? value) {
    return RecommendationPriorityMode.values.firstWhere(
      (mode) => mode.storageValue == value,
      orElse: () => RecommendationPriorityMode.uncapturedFirst,
    );
  }
}

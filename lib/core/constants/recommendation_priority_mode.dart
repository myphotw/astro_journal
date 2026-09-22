/// Legacy persisted recommendation sort values.
///
/// Capture history no longer changes recommendation ordering. These values
/// remain readable so existing preferences do not break deserialization.
enum RecommendationPriorityMode {
  /// Legacy uncaptured-first preference.
  uncapturedFirst('uncaptured_first', '미촬영 우선'),

  /// Highest recommendation score first.
  scoreFirst('score_first', '점수 우선'),

  /// Legacy mixed preference.
  mixed('mixed', '혼합');

  const RecommendationPriorityMode(this.storageValue, this.label);

  final String storageValue;
  final String label;

  static RecommendationPriorityMode fromStorageValue(String? value) {
    return RecommendationPriorityMode.values.firstWhere(
      (mode) => mode.storageValue == value,
      orElse: () => RecommendationPriorityMode.scoreFirst,
    );
  }
}

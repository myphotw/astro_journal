abstract final class RecommendationExclusionMessages {
  static List<String> build({
    required int altitudeExcluded,
    required int azimuthExcluded,
    required int noWindow,
    required int lightPollutionExcluded,
    int insufficientDuration = 0,
    int limitedDifficultyExcluded = 0,
  }) {
    final reasons = <String>[];
    if (altitudeExcluded > 0) {
      reasons.add('고도 조건 불만족 ($altitudeExcluded개)');
    }
    if (azimuthExcluded > 0) {
      reasons.add('방위각 조건 불만족 ($azimuthExcluded개)');
    }
    if (lightPollutionExcluded > 0) {
      reasons.add('광해 조건 불만족 ($lightPollutionExcluded개)');
    }
    if (insufficientDuration > 0) {
      reasons.add('관측 가능 시간 부족 ($insufficientDuration개)');
    }
    if (limitedDifficultyExcluded > 0) {
      reasons.add('오늘 조건상 어려운 대상 제외 ($limitedDifficultyExcluded개)');
    }
    if (noWindow > 0) {
      reasons.add('오늘 밤 관측 가능한 대상 없음');
    }
    if (reasons.isEmpty) {
      reasons.add('조건을 만족하는 추천 대상이 없습니다');
    }
    return reasons;
  }
}

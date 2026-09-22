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
      reasons.add('오늘은 대상의 고도가 촬영 조건을 만족하지 않습니다.');
    }
    if (azimuthExcluded > 0) {
      reasons.add('오늘은 대상이 관측 가능한 시야 범위를 벗어납니다.');
    }
    if (lightPollutionExcluded > 0) {
      reasons.add('현재 광해 환경에서는 추천하기 어려운 대상입니다.');
    }
    if (insufficientDuration > 0) {
      reasons.add('연속 촬영시간을 충분히 확보하기 어렵습니다.');
    }
    if (limitedDifficultyExcluded > 0) {
      reasons.add('오늘 조건에서 실용적인 결과를 기대하기 어려운 대상입니다.');
    }
    if (noWindow > 0) {
      reasons.add('오늘은 고도·방위·시야 조건을 만족하는 시간대가 없습니다.');
    }
    if (reasons.isEmpty) {
      reasons.add('조건을 만족하는 추천 대상이 없습니다');
    }
    return reasons;
  }
}

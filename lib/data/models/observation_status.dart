/// Tonight's site-level observation suitability for recommendations.
enum ObservationStatus { good, limited, unavailable }

extension ObservationStatusMessages on ObservationStatus {
  String get headline => switch (this) {
    ObservationStatus.good => '오늘 밤은 대체로 맑은 날씨가 예상됩니다.',
    ObservationStatus.limited => '구름이 일부 예상됩니다. 실제 하늘 상태를 확인해 주세요.',
    ObservationStatus.unavailable => '예보상 기상 조건을 확인해 주세요.',
  };

  String get limitedRecommendationNotice => '기상 예보는 참고 정보이며 추천 순위에는 반영하지 않습니다.';

  int get homeStarCount => switch (this) {
    ObservationStatus.good => 5,
    ObservationStatus.limited => 3,
    ObservationStatus.unavailable => 0,
  };

  bool get allowsRecommendations => true;

  bool get allowsScheduling => true;
}

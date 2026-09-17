/// Tonight's site-level observation suitability for recommendations.
enum ObservationStatus {
  good,
  limited,
  unavailable,
}

extension ObservationStatusMessages on ObservationStatus {
  String get headline => switch (this) {
        ObservationStatus.good => '오늘은 관측하기 좋은 날입니다.',
        ObservationStatus.limited => '기상 조건을 반영해 추천 순서를 조정합니다.',
        ObservationStatus.unavailable => '오늘 밤 기상 조건을 확인해 주세요.',
      };

  String get limitedRecommendationNotice => '예보상 촬영 조건이 좋지 않을 수 있습니다.';

  int get homeStarCount => switch (this) {
        ObservationStatus.good => 5,
        ObservationStatus.limited => 3,
        ObservationStatus.unavailable => 0,
      };

  bool get allowsRecommendations => true;

  bool get allowsScheduling => this != ObservationStatus.unavailable;
}

/// Tonight's site-level observation suitability for recommendations.
enum ObservationStatus {
  good,
  limited,
  unavailable,
}

extension ObservationStatusMessages on ObservationStatus {
  String get headline => switch (this) {
        ObservationStatus.good => '오늘은 관측하기 좋은 날입니다.',
        ObservationStatus.limited => '조건이 좋지 않아 쉬운 대상 위주로 추천합니다.',
        ObservationStatus.unavailable => '오늘 밤은 관측을 권장하지 않습니다.',
      };

  String get limitedRecommendationNotice => '오늘은 관측 조건이 좋지 않습니다.';

  int get homeStarCount => switch (this) {
        ObservationStatus.good => 5,
        ObservationStatus.limited => 3,
        ObservationStatus.unavailable => 0,
      };

  bool get allowsRecommendations => this != ObservationStatus.unavailable;

  bool get allowsScheduling => this != ObservationStatus.unavailable;
}

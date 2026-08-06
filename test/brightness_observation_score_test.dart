import 'package:astro_journal/services/observation_score_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ObservationScoreService.brightnessToObservationScore', () {
    test('maps brightness tiers', () {
      expect(ObservationScoreService.brightnessToObservationScore(0.1), 100);
      expect(ObservationScoreService.brightnessToObservationScore(0.2), 100);
      expect(ObservationScoreService.brightnessToObservationScore(0.3), 98);
      expect(ObservationScoreService.brightnessToObservationScore(0.84), 95);
      expect(ObservationScoreService.brightnessToObservationScore(1.5), 90);
      expect(ObservationScoreService.brightnessToObservationScore(2.5), 80);
      expect(ObservationScoreService.brightnessToObservationScore(5.5), 50);
      expect(ObservationScoreService.brightnessToObservationScore(9.5), 10);
    });

    test('computeSiteObservationScore returns null without brightness', () {
      expect(
        ObservationScoreService.computeSiteObservationScore(brightness: null),
        isNull,
      );
    });

    test('computeSiteObservationScore uses brightness only', () {
      expect(
        ObservationScoreService.computeSiteObservationScore(brightness: 0.83),
        95,
      );
    });
  });
}

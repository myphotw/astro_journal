import 'package:astro_journal/data/models/fov_box.dart';
import 'package:astro_journal/services/equipment/screen_fill_scoring.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ScreenFillScoring', () {
    test('scores 60-100% range at maximum', () {
      expect(ScreenFillScoring.score(0.60), 100);
      expect(ScreenFillScoring.score(0.82), 100);
      expect(ScreenFillScoring.score(1.0), 100);
    });

    test('penalizes too small and too large fill', () {
      expect(ScreenFillScoring.score(0.20), lessThan(ScreenFillScoring.score(0.70)));
      expect(ScreenFillScoring.score(3.2), lessThan(ScreenFillScoring.score(0.80)));
    });

    test('formats fill percent label', () {
      expect(ScreenFillScoring.fillPercent(0.82), 82);
      expect(ScreenFillScoring.fillPercentLabel(1.45), '화면의 145%');
    });

    test('fillRatioFromFramingWithBestOrientation uses rotated alignment', () {
      expect(
        ScreenFillScoring.fillRatioFromFramingWithBestOrientation(
          targetWidthDegrees: 190 / 60,
          targetHeightDegrees: 60 / 60,
          fieldOfViewWidthDegrees: 2.24,
          fieldOfViewHeightDegrees: 3.99,
        ),
        closeTo(0.79, 0.02),
      );
    });

    test('fillRatioFromFraming delegates to 2D rotation engine', () {
      expect(
        ScreenFillScoring.fillRatioFromFraming(
          targetWidthDegrees: 3.2,
          targetHeightDegrees: 1.0,
          fieldOfViewWidthDegrees: 2.24,
          fieldOfViewHeightDegrees: 3.99,
        ),
        closeTo(0.79, 0.02),
      );
    });

    test('fillRatioFromSquareFov treats circular FOV as square', () {
      expect(
        ScreenFillScoring.fillRatioFromSquareFov(
          targetWidthDegrees: 65 / 60,
          targetHeightDegrees: 50 / 60,
          fieldOfViewDegrees: 4.6,
        ),
        closeTo((65 / 60) / 4.6, 0.001),
      );
    });

    test('returns fill notes for imaging and visual', () {
      expect(
        ScreenFillScoring.imagingFillNote(
          FramingRecommendation.mosaicRequired,
        ),
        '모자이크 권장',
      );
      expect(
        ScreenFillScoring.visualFillNote(3.2),
        '전체 모습 확인 어려움',
      );
    });
  });
}

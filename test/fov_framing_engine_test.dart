import 'package:astro_journal/data/models/fov_box.dart';
import 'package:astro_journal/services/equipment/fov_framing_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FovFramingEngine', () {
    const s30Fov = FovBox(widthDegrees: 2.24, heightDegrees: 3.99);
    const m31Target = TargetBox(
      widthDegrees: 3.2,
      heightDegrees: 1.0,
    );

    test('M31 on S30 Pro best coverage near 79% not 141%', () {
      final result = FovFramingEngine.evaluateBestRotation(
        target: m31Target,
        fov: s30Fov,
      );

      expect(result.bestCoverage, closeTo(0.79, 0.02));
      expect(result.coveragePercent, lessThan(100));
      expect(result.recommendation, FramingRecommendation.good);
      expect(result.bestAngleDegrees, closeTo(90, 5));
    });

    test('naive width-only ratio would be wrong (141%)', () {
      final wrong1d = m31Target.widthDegrees / s30Fov.widthDegrees;
      expect(wrong1d, greaterThan(1.4));
      expect(
        FovFramingEngine.evaluateBestRotation(
          target: m31Target,
          fov: s30Fov,
        ).bestCoverage,
        lessThan(1.0),
      );
    });

    test('coverageAtAngle uses 2D rotated bounding box', () {
      final at90 = FovFramingEngine.coverageAtAngle(
        target: m31Target,
        fov: s30Fov,
        angleDegrees: 90,
      );
      expect(at90, closeTo(3.2 / 3.99, 0.02));
    });

    test('recommendation tiers', () {
      expect(
        FovFramingEngine.recommendationFor(0.8),
        FramingRecommendation.good,
      );
      expect(
        FovFramingEngine.recommendationFor(1.1),
        FramingRecommendation.optimal,
      );
      expect(
        FovFramingEngine.recommendationFor(1.45),
        FramingRecommendation.tight,
      );
      expect(
        FovFramingEngine.recommendationFor(1.7),
        FramingRecommendation.mosaicRequired,
      );
    });

    test('scans 0-180 for best angle', () {
      final result = FovFramingEngine.evaluateBestRotation(
        target: const TargetBox(widthDegrees: 2.0, heightDegrees: 0.8),
        fov: const FovBox(widthDegrees: 1.5, heightDegrees: 2.5),
        angleStepDegrees: 1,
      );
      expect(result.bestAngleDegrees, greaterThanOrEqualTo(0));
      expect(result.bestAngleDegrees, lessThanOrEqualTo(180));
    });
  });
}

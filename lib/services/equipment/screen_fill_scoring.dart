import '../../data/models/fov_box.dart';
import 'fov_framing_engine.dart';

/// 장비 FOV 대비 천체 화면 점유율 — [FovFramingEngine] 기반.
abstract final class ScreenFillScoring {
  static const double idealMinRatio = 0.60;
  static const double idealMaxRatio = 1.00;

  /// @deprecated 1D 비율 — 신규 코드에서 사용 금지. [FovFramingEngine] 사용.
  @Deprecated('Use FovFramingEngine.evaluateBestRotation')
  static double fillRatio({
    required double targetSizeDegrees,
    required double fieldOfViewDegrees,
  }) {
    return FovFramingEngine.evaluateBestRotation(
      target: TargetBox.squareDegrees(targetSizeDegrees),
      fov: FovBox(
        widthDegrees: fieldOfViewDegrees,
        heightDegrees: fieldOfViewDegrees,
      ),
    ).bestCoverage;
  }

  /// 2D 프레이밍 엔진으로 최적 회전 coverage 반환.
  static double fillRatioFromFraming({
    required double targetWidthDegrees,
    required double targetHeightDegrees,
    required double fieldOfViewWidthDegrees,
    required double fieldOfViewHeightDegrees,
  }) {
    return FovFramingEngine.evaluateBestRotation(
      target: TargetBox(
        widthDegrees: targetWidthDegrees,
        heightDegrees: targetHeightDegrees,
      ),
      fov: FovBox(
        widthDegrees: fieldOfViewWidthDegrees,
        heightDegrees: fieldOfViewHeightDegrees,
      ),
    ).bestCoverage;
  }

  static FramingCoverageResult framingResult({
    required double targetWidthDegrees,
    required double targetHeightDegrees,
    required double fieldOfViewWidthDegrees,
    required double fieldOfViewHeightDegrees,
    double? positionAngleDegrees,
  }) {
    return FovFramingEngine.evaluateBestRotation(
      target: TargetBox(
        widthDegrees: targetWidthDegrees,
        heightDegrees: targetHeightDegrees,
        positionAngleDegrees: positionAngleDegrees,
      ),
      fov: FovBox(
        widthDegrees: fieldOfViewWidthDegrees,
        heightDegrees: fieldOfViewHeightDegrees,
      ),
    );
  }

  static double fillRatioFromFramingAtRotation({
    required double targetWidthDegrees,
    required double targetHeightDegrees,
    required double fieldOfViewWidthDegrees,
    required double fieldOfViewHeightDegrees,
    required double rotationDegrees,
  }) {
    return FovFramingEngine.coverageAtAngle(
      target: TargetBox(
        widthDegrees: targetWidthDegrees,
        heightDegrees: targetHeightDegrees,
      ),
      fov: FovBox(
        widthDegrees: fieldOfViewWidthDegrees,
        heightDegrees: fieldOfViewHeightDegrees,
      ),
      angleDegrees: rotationDegrees,
    );
  }

  static double fillRatioFromFramingWithBestOrientation({
    required double targetWidthDegrees,
    required double targetHeightDegrees,
    required double fieldOfViewWidthDegrees,
    required double fieldOfViewHeightDegrees,
  }) {
    return fillRatioFromFraming(
      targetWidthDegrees: targetWidthDegrees,
      targetHeightDegrees: targetHeightDegrees,
      fieldOfViewWidthDegrees: fieldOfViewWidthDegrees,
      fieldOfViewHeightDegrees: fieldOfViewHeightDegrees,
    );
  }

  /// 원형·정사각 시야 (안시 아이피스).
  static double fillRatioFromSquareFov({
    required double targetWidthDegrees,
    required double targetHeightDegrees,
    required double fieldOfViewDegrees,
  }) {
    return fillRatioFromFraming(
      targetWidthDegrees: targetWidthDegrees,
      targetHeightDegrees: targetHeightDegrees,
      fieldOfViewWidthDegrees: fieldOfViewDegrees,
      fieldOfViewHeightDegrees: fieldOfViewDegrees,
    );
  }

  static int fillPercent(double fillRatio) => (fillRatio * 100).round();

  static String fillPercentLabel(double fillRatio) =>
      '화면의 ${fillPercent(fillRatio)}%';

  static double score(double fillRatio) {
    if (fillRatio <= 0) return 10;
    if (fillRatio >= idealMinRatio && fillRatio <= idealMaxRatio) {
      return 100;
    }
    if (fillRatio < idealMinRatio) {
      final distance = idealMinRatio - fillRatio;
      return (100 - distance * 180).clamp(15, 100);
    }
    final distance = fillRatio - idealMaxRatio;
    return (100 - distance * 70).clamp(15, 100);
  }

  static String? imagingFillNote(FramingRecommendation recommendation) {
    return switch (recommendation) {
      FramingRecommendation.mosaicRequired => '모자이크 권장',
      FramingRecommendation.tight => '프레임 꽉 참',
      _ => null,
    };
  }

  static String? imagingFillNoteFromCoverage(double coverage) =>
      imagingFillNote(FovFramingEngine.recommendationFor(coverage));

  static String? visualFillNote(double fillRatio) {
    if (fillRatio > FovFramingEngine.tightUpperBound) {
      return '전체 모습 확인 어려움';
    }
    if (fillRatio > FovFramingEngine.optimalUpperBound) {
      return '프레임 꽉 참';
    }
    return null;
  }

  static String reasonFromRecommendation(FramingRecommendation recommendation) {
    return switch (recommendation) {
      FramingRecommendation.mosaicRequired => '모자이크 권장',
      FramingRecommendation.tight => '프레임 꽉 참',
      FramingRecommendation.optimal => '프레임 적합',
      FramingRecommendation.good => '촬영 가능',
    };
  }
}

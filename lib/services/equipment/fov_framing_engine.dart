import 'dart:math' as math;

import '../../data/models/fov_box.dart';

/// 천체–장비 FOV 매칭: 회전 가능한 2D bounding box 최적화.
///
/// 1D width/width 비율은 사용하지 않는다.
abstract final class FovFramingEngine {
  static const double optimalUpperBound = 1.3;
  static const double tightUpperBound = 1.6;
  static const double defaultAngleStepDegrees = 1.0;

  /// θ에서의 coverage = max(rotated_w/fov.w, rotated_h/fov.h)
  static double coverageAtAngle({
    required TargetBox target,
    required FovBox fov,
    required double angleDegrees,
  }) {
    if (!target.isValid || !fov.isValid) return 0;

    final rad = angleDegrees * math.pi / 180;
    final cos = math.cos(rad).abs();
    final sin = math.sin(rad).abs();

    final rotatedWidth =
        target.widthDegrees * cos + target.heightDegrees * sin;
    final rotatedHeight =
        target.widthDegrees * sin + target.heightDegrees * cos;

    final fillX = rotatedWidth / fov.widthDegrees;
    final fillY = rotatedHeight / fov.heightDegrees;
    return fillX > fillY ? fillX : fillY;
  }

  /// θ ∈ [0°, 180°]에서 coverage 최소(=가장 잘 맞는 방향).
  static FramingCoverageResult evaluateBestRotation({
    required TargetBox target,
    required FovBox fov,
    double angleStepDegrees = defaultAngleStepDegrees,
  }) {
    if (!target.isValid || !fov.isValid) return FramingCoverageResult.empty;

    var bestCoverage = double.infinity;
    var bestAngle = 0.0;

    for (var theta = 0.0; theta <= 180.0; theta += angleStepDegrees) {
      final coverage = coverageAtAngle(
        target: target,
        fov: fov,
        angleDegrees: theta,
      );
      if (coverage < bestCoverage) {
        bestCoverage = coverage;
        bestAngle = theta;
      }
    }

    return FramingCoverageResult(
      bestCoverage: bestCoverage,
      bestAngleDegrees: bestAngle,
      recommendation: recommendationFor(bestCoverage),
    );
  }

  /// 하늘 방위가 고정된 각도(°)에서의 coverage.
  static FramingCoverageResult evaluateAtSkyAngle({
    required TargetBox target,
    required FovBox fov,
    required double skyRotationDegrees,
  }) {
    final coverage = coverageAtAngle(
      target: target,
      fov: fov,
      angleDegrees: _normalizeAngle180(skyRotationDegrees),
    );
    return FramingCoverageResult(
      bestCoverage: coverage,
      bestAngleDegrees: _normalizeAngle180(skyRotationDegrees),
      recommendation: recommendationFor(coverage),
    );
  }

  /// 관측 창 동안 최소 coverage (시야 회전 + 천체 시위각 반영).
  static FramingCoverageResult evaluateBestDuringWindow({
    required TargetBox target,
    required FovBox fov,
    required double objectPositionAngleDegrees,
    required Iterable<double> fieldRotationDegreesSamples,
  }) {
    if (!target.isValid || !fov.isValid) return FramingCoverageResult.empty;

    var bestCoverage = double.infinity;
    var bestAngle = 0.0;
    var hasSample = false;

    for (final fieldRotation in fieldRotationDegreesSamples) {
      hasSample = true;
      final skyAngle = objectPositionAngleDegrees - fieldRotation;
      final coverage = coverageAtAngle(
        target: target,
        fov: fov,
        angleDegrees: skyAngle,
      );
      if (coverage < bestCoverage) {
        bestCoverage = coverage;
        bestAngle = _normalizeAngle180(skyAngle);
      }
    }

    if (!hasSample) {
      return evaluateBestRotation(target: target, fov: fov);
    }

    return FramingCoverageResult(
      bestCoverage: bestCoverage,
      bestAngleDegrees: bestAngle,
      recommendation: recommendationFor(bestCoverage),
    );
  }

  static FramingRecommendation recommendationFor(double coverage) {
    if (coverage < 1.0) return FramingRecommendation.good;
    if (coverage < optimalUpperBound) return FramingRecommendation.optimal;
    if (coverage < tightUpperBound) return FramingRecommendation.tight;
    return FramingRecommendation.mosaicRequired;
  }

  static double _normalizeAngle180(double degrees) {
    var angle = degrees % 180;
    if (angle < 0) angle += 180;
    return angle;
  }
}

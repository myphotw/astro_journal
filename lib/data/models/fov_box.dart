/// 장비 시야(FOV) 또는 천체 크기(°) 2D 박스.
class FovBox {
  const FovBox({
    required this.widthDegrees,
    required this.heightDegrees,
  });

  final double widthDegrees;
  final double heightDegrees;

  bool get isValid => widthDegrees > 0 && heightDegrees > 0;
}

/// 천체 대표 프레이밍 크기(°).
class TargetBox {
  const TargetBox({
    required this.widthDegrees,
    required this.heightDegrees,
    this.positionAngleDegrees,
  });

  final double widthDegrees;
  final double heightDegrees;

  /// 하늘에서 주축 시위각(°). null이면 자유 회전 가정.
  final double? positionAngleDegrees;

  bool get isValid => widthDegrees > 0 && heightDegrees > 0;

  factory TargetBox.fromArcmin({
    required double widthArcmin,
    required double heightArcmin,
    double? positionAngleDegrees,
  }) {
    return TargetBox(
      widthDegrees: widthArcmin / 60,
      heightDegrees: heightArcmin / 60,
      positionAngleDegrees: positionAngleDegrees,
    );
  }

  factory TargetBox.squareDegrees(double degrees) => TargetBox(
        widthDegrees: degrees,
        heightDegrees: degrees,
      );
}

/// 2D 회전 최적화 기반 프레이밍 판정.
enum FramingRecommendation {
  /// coverage < 1.0 — 여유 있게 들어옴
  good,

  /// 1.0 ≤ coverage < 1.3 — 최적 프레이밍
  optimal,

  /// 1.3 ≤ coverage < 1.6 — 꽉 참
  tight,

  /// coverage ≥ 1.6 — 모자이크 필요
  mosaicRequired;

  String get labelKo => switch (this) {
        FramingRecommendation.good => '여유 있음',
        FramingRecommendation.optimal => '최적 프레이밍',
        FramingRecommendation.tight => '프레임 꽉 참',
        FramingRecommendation.mosaicRequired => '모자이크 필요',
      };
}

/// FOV 프레이밍 엔진 결과.
class FramingCoverageResult {
  const FramingCoverageResult({
    required this.bestCoverage,
    required this.bestAngleDegrees,
    required this.recommendation,
  });

  /// min_θ max(fill_x, fill_y)
  final double bestCoverage;

  /// coverage가 최소인 회전각(°), 0~180
  final double bestAngleDegrees;

  final FramingRecommendation recommendation;

  int get coveragePercent => (bestCoverage * 100).round();

  static const empty = FramingCoverageResult(
    bestCoverage: 0,
    bestAngleDegrees: 0,
    recommendation: FramingRecommendation.good,
  );
}

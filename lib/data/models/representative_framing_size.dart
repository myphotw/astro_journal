/// 장비 추천용 대표 촬영·안시 프레이밍 크기 (가로 × 세로).
class RepresentativeFramingSize {
  const RepresentativeFramingSize({
    required this.widthArcmin,
    required this.heightArcmin,
    this.positionAngleDegrees,
  });

  final double widthArcmin;
  final double heightArcmin;

  /// 주축의 시위각(°). 북→동. null이면 방향 미지정.
  final double? positionAngleDegrees;

  double get widthDegrees => widthArcmin / 60;
  double get heightDegrees => heightArcmin / 60;

  factory RepresentativeFramingSize.squareArcmin(double arcmin) {
    return RepresentativeFramingSize(
      widthArcmin: arcmin,
      heightArcmin: arcmin,
    );
  }

  factory RepresentativeFramingSize.squareDegrees(double degrees) {
    return RepresentativeFramingSize.squareArcmin(degrees * 60);
  }
}

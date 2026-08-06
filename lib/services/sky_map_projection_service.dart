import 'dart:math' as math;
import 'dart:ui';

import 'plate_solve_projection.dart';

/// RA/DEC → Sky Map Canvas 픽셀 좌표 변환.
///
/// **단일 스케일 규칙 (plate carrée)**
/// - Zoom = [viewHeightDeg] (화면에 보이는 하늘 세로 각도)
/// - `px = skyDegrees / (viewHeightDeg / canvasHeight)`
/// - RA·DEC를 **동일한 °/px** 로 매핑 (center Dec의 cos 보정 없음)
///   → 남북 pan 시 가로가 줄어들며 “줌처럼” 보이는 왜곡을 방지
/// - Catalog Object 각크기 · Equipment FOV · 별 위치 모두 이 식만 사용
///
/// Zoom Out(viewHeight↑) → 같은 각도 크기의 픽셀↓ (작게 보임)
/// Zoom In(viewHeight↓) → 같은 각도 크기의 픽셀↑ (크게 보임)
class SkyMapProjectionService {
  SkyMapProjectionService._();

  static double _toRad(double deg) => deg * math.pi / 180;

  /// 각크기가 없거나 너무 작은 천체도 FOV와 같은 °→px 스케일로 그리기 위한 최소 표시 각크기.
  static const double minDisplayArcmin = 6.0;

  static double deltaRaDeg(double raDeg, double centerRaDeg) {
    var d = raDeg - centerRaDeg;
    while (d > 180) {
      d -= 360;
    }
    while (d < -180) {
      d += 360;
    }
    return d;
  }

  /// 두 RA 사이의 최단 호 길이(°). 항상 [0, 180].
  static double shortestRaDeltaDeg(double raADeg, double raBDeg) {
    return deltaRaDeg(raADeg, raBDeg).abs();
  }

  /// 두 점의 천구 각거리(°).
  static double angularSeparationDeg({
    required double raADeg,
    required double decADeg,
    required double raBDeg,
    required double decBDeg,
  }) {
    final ra1 = _toRad(raADeg);
    final dec1 = _toRad(decADeg);
    final ra2 = _toRad(raBDeg);
    final dec2 = _toRad(decBDeg);
    final cosSep = math.sin(dec1) * math.sin(dec2) +
        math.cos(dec1) * math.cos(dec2) * math.cos(ra1 - ra2);
    return math.acos(cosSep.clamp(-1.0, 1.0)) * 180 / math.pi;
  }

  /// RA 최단 호가 0°/360° 경계를 지나치면 true.
  static bool isRaWrapCrossing(double raADeg, double raBDeg) {
    return (raADeg - raBDeg).abs() > 180;
  }

  /// 별자리 선분을 그릴지 여부.
  ///
  /// RA wrap + 접평면 투영 때문에 실제 각거리보다 화면 코드가 훨씬 길어지면
  /// 가로지르는 가짜 직선이므로 그리지 않는다.
  static bool shouldDrawConstellationSegment({
    required double raADeg,
    required double decADeg,
    required double raBDeg,
    required double decBDeg,
    required Offset projectedA,
    required Offset projectedB,
    required Size canvasSize,
    required double viewHeightDeg,
  }) {
    final sep = angularSeparationDeg(
      raADeg: raADeg,
      decADeg: decADeg,
      raBDeg: raBDeg,
      decBDeg: decBDeg,
    );
    if (sep < 1e-3) return false;

    final expectedPx = angularDegreesToPixels(
      degrees: sep,
      canvasSize: canvasSize,
      viewHeightDeg: viewHeightDeg,
    );
    final actualPx = (projectedA - projectedB).distance;
    if (expectedPx <= 0) return false;

    // 투영 왜곡으로 코드가 각거리 대비 과도하게 길면 wrap 아티팩트
    if (actualPx > expectedPx * 2.5 &&
        actualPx > canvasSize.shortestSide * 0.25) {
      return false;
    }
    return true;
  }

  /// °/px — Zoom의 유일한 스케일 소스.
  static double degreesPerPixel({
    required Size canvasSize,
    required double viewHeightDeg,
  }) {
    if (canvasSize.height <= 0 || viewHeightDeg <= 0) return 1;
    return viewHeightDeg / canvasSize.height;
  }

  /// 천구 각도(°) → 픽셀. clamp 없음.
  static double angularDegreesToPixels({
    required double degrees,
    required Size canvasSize,
    required double viewHeightDeg,
  }) {
    final dpp = degreesPerPixel(
      canvasSize: canvasSize,
      viewHeightDeg: viewHeightDeg,
    );
    return degrees / dpp;
  }

  /// RA/DEC → Canvas 픽셀 (plate carrée, cos(Dec) 보정 없음).
  static Offset project({
    required double raDeg,
    required double decDeg,
    required double centerRaDeg,
    required double centerDecDeg,
    required Size canvasSize,
    required double viewHeightDeg,
  }) {
    final dpp = degreesPerPixel(
      canvasSize: canvasSize,
      viewHeightDeg: viewHeightDeg,
    );
    final eastDeg = deltaRaDeg(raDeg, centerRaDeg);
    final northDeg = decDeg - centerDecDeg;

    return Offset(
      canvasSize.width / 2 + eastDeg / dpp,
      canvasSize.height / 2 - northDeg / dpp,
    );
  }

  static ({double raDeg, double decDeg}) unproject({
    required Offset pixel,
    required double centerRaDeg,
    required double centerDecDeg,
    required Size canvasSize,
    required double viewHeightDeg,
  }) {
    final dpp = degreesPerPixel(
      canvasSize: canvasSize,
      viewHeightDeg: viewHeightDeg,
    );
    final eastDeg = (pixel.dx - canvasSize.width / 2) * dpp;
    final northDeg = -(pixel.dy - canvasSize.height / 2) * dpp;
    final ra = (centerRaDeg + eastDeg) % 360;
    return (
      raDeg: ra < 0 ? ra + 360 : ra,
      decDeg: (centerDecDeg + northDeg).clamp(-90.0, 90.0),
    );
  }

  /// 장비 FOV 사각형.
  ///
  /// FOV는 **천구 각도(°)** 로만 관리한다. 네 꼭짓점을 RA/DEC로 만든 뒤
  /// Catalog Object / 별과 **동일한 [project]** 로 그린다.
  /// 고정 픽셀 폭·높이·별도 스케일 변환을 쓰지 않는다.
  static List<Offset> projectFovCorners({
    required double objectRaDeg,
    required double objectDecDeg,
    required double centerRaDeg,
    required double centerDecDeg,
    required double fovWidthDeg,
    required double fovHeightDeg,
    required double rotationDeg,
    required Size canvasSize,
    required double viewHeightDeg,
  }) {
    assert(fovWidthDeg > 0 && fovHeightDeg > 0);

    final halfW = fovWidthDeg / 2;
    final halfH = fovHeightDeg / 2;
    // 천구 접평면: +x=동, +y=북 (화면 y는 project에서 반전)
    final local = <Offset>[
      Offset(-halfW, halfH),
      Offset(halfW, halfH),
      Offset(halfW, -halfH),
      Offset(-halfW, -halfH),
    ];

    final theta = _toRad(rotationDeg);
    final cosT = math.cos(theta);
    final sinT = math.sin(theta);

    return local.map((c) {
      final east = c.dx * cosT - c.dy * sinT;
      final north = c.dx * sinT + c.dy * cosT;
      // project()와 동일한 plate carrée (° = °)
      final ra = objectRaDeg + east;
      final dec = (objectDecDeg + north).clamp(-90.0, 90.0);
      return project(
        raDeg: ra,
        decDeg: dec,
        centerRaDeg: centerRaDeg,
        centerDecDeg: centerDecDeg,
        canvasSize: canvasSize,
        viewHeightDeg: viewHeightDeg,
      );
    }).toList(growable: false);
  }

  /// 각크기(arcmin) → 픽셀 폭·높이. Object/FOV 공통 스케일.
  static Size projectObjectSizePx({
    required double majorArcmin,
    required double minorArcmin,
    required Size canvasSize,
    required double viewHeightDeg,
  }) {
    return Size(
      angularDegreesToPixels(
        degrees: majorArcmin / 60.0,
        canvasSize: canvasSize,
        viewHeightDeg: viewHeightDeg,
      ),
      angularDegreesToPixels(
        degrees: minorArcmin / 60.0,
        canvasSize: canvasSize,
        viewHeightDeg: viewHeightDeg,
      ),
    );
  }

  static ({
    double screenX,
    double screenY,
    double renderWidth,
    double renderHeight,
  }) projectWithSize({
    required double raDeg,
    required double decDeg,
    required double centerRaDeg,
    required double centerDecDeg,
    required Size canvasSize,
    required double viewHeightDeg,
    double? majorArcmin,
    double? minorArcmin,
  }) {
    final pixel = project(
      raDeg: raDeg,
      decDeg: decDeg,
      centerRaDeg: centerRaDeg,
      centerDecDeg: centerDecDeg,
      canvasSize: canvasSize,
      viewHeightDeg: viewHeightDeg,
    );
    // 고정 픽셀 점 사용 금지 — 최소 각크기로 FOV와 동일 스케일 유지
    final rawMajor = majorArcmin ?? 0;
    final rawMinor = minorArcmin ?? rawMajor;
    final major = math.max(rawMajor, minDisplayArcmin);
    final minor = math.max(rawMinor > 0 ? rawMinor : major, minDisplayArcmin);
    final size = projectObjectSizePx(
      majorArcmin: major,
      minorArcmin: minor,
      canvasSize: canvasSize,
      viewHeightDeg: viewHeightDeg,
    );
    return (
      screenX: pixel.dx,
      screenY: pixel.dy,
      renderWidth: size.width,
      renderHeight: size.height,
    );
  }

  static TangentPlaneOffset tangentOffsetDeg({
    required double centerRaDeg,
    required double centerDecDeg,
    required double targetRaDeg,
    required double targetDecDeg,
    double rotationDeg = 0,
  }) {
    return PlateSolveProjection.tangentPlaneOffsetDeg(
      centerRaDeg: centerRaDeg,
      centerDecDeg: centerDecDeg,
      targetRaDeg: targetRaDeg,
      targetDecDeg: targetDecDeg,
      rotationDeg: rotationDeg,
    );
  }
}

import 'dart:math' as math;
import 'dart:ui';

import 'package:astro_journal/services/sky_map_projection_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// cos(centerDec) 보정 검증용 — 프로덕션 투영은 변경하지 않음.
Offset _projectWithCosCenterDec({
  required double raDeg,
  required double decDeg,
  required double centerRaDeg,
  required double centerDecDeg,
  required Size canvasSize,
  required double viewHeightDeg,
}) {
  final dpp = SkyMapProjectionService.degreesPerPixel(
    canvasSize: canvasSize,
    viewHeightDeg: viewHeightDeg,
  );
  final eastDeg = SkyMapProjectionService.deltaRaDeg(raDeg, centerRaDeg) *
      math.cos(centerDecDeg * math.pi / 180);
  final northDeg = decDeg - centerDecDeg;
  return Offset(
    canvasSize.width / 2 + eastDeg / dpp,
    canvasSize.height / 2 - northDeg / dpp,
  );
}

double _screenSep(Offset a, Offset b) => (a - b).distance;

void main() {
  const canvas = Size(400, 800);
  const viewHeight = 60.0;

  group('Projection verification: cos(centerDec) candidate', () {
    test('적도(centerDec=0): cos 보정 전후 픽셀 간격 동일', () {
      const centerRa = 83.8;
      const centerDec = 0.0;
      // Orion belt-ish ΔRA ~1°
      final a0 = SkyMapProjectionService.project(
        raDeg: 83.0,
        decDeg: -0.3,
        centerRaDeg: centerRa,
        centerDecDeg: centerDec,
        canvasSize: canvas,
        viewHeightDeg: viewHeight,
      );
      final b0 = SkyMapProjectionService.project(
        raDeg: 84.0,
        decDeg: -0.3,
        centerRaDeg: centerRa,
        centerDecDeg: centerDec,
        canvasSize: canvas,
        viewHeightDeg: viewHeight,
      );
      final a1 = _projectWithCosCenterDec(
        raDeg: 83.0,
        decDeg: -0.3,
        centerRaDeg: centerRa,
        centerDecDeg: centerDec,
        canvasSize: canvas,
        viewHeightDeg: viewHeight,
      );
      final b1 = _projectWithCosCenterDec(
        raDeg: 84.0,
        decDeg: -0.3,
        centerRaDeg: centerRa,
        centerDecDeg: centerDec,
        canvasSize: canvas,
        viewHeightDeg: viewHeight,
      );
      expect(_screenSep(a0, b0), closeTo(_screenSep(a1, b1), 0.01));
    });

    test('고위도(centerDec=60): cos 보정은 RA 간격을 ~50%로 압축', () {
      const centerRa = 0.0;
      const centerDec = 60.0;
      final a0 = SkyMapProjectionService.project(
        raDeg: -5,
        decDeg: 60,
        centerRaDeg: centerRa,
        centerDecDeg: centerDec,
        canvasSize: canvas,
        viewHeightDeg: viewHeight,
      );
      final b0 = SkyMapProjectionService.project(
        raDeg: 5,
        decDeg: 60,
        centerRaDeg: centerRa,
        centerDecDeg: centerDec,
        canvasSize: canvas,
        viewHeightDeg: viewHeight,
      );
      final a1 = _projectWithCosCenterDec(
        raDeg: -5,
        decDeg: 60,
        centerRaDeg: centerRa,
        centerDecDeg: centerDec,
        canvasSize: canvas,
        viewHeightDeg: viewHeight,
      );
      final b1 = _projectWithCosCenterDec(
        raDeg: 5,
        decDeg: 60,
        centerRaDeg: centerRa,
        centerDecDeg: centerDec,
        canvasSize: canvas,
        viewHeightDeg: viewHeight,
      );
      final without = _screenSep(a0, b0);
      final withCos = _screenSep(a1, b1);
      final ratio = withCos / without;
      expect(ratio, closeTo(0.5, 0.02)); // cos(60°)=0.5
      // 보정은 간격을 줄임(더 붙여 보임) — "붙어 보인다" 체감의 반대 방향이 아님, 동일 방향 강화
      expect(withCos, lessThan(without));
    });

    test('현재(무보정)는 진각거리보다 RA를 과장(늘림)', () {
      // ΔRA=10°, Dec=60° → 진각거리 ≈ 10*cos(60)=5°
      const trueApproxDeg = 5.0;
      final sep = SkyMapProjectionService.angularSeparationDeg(
        raADeg: 0,
        decADeg: 60,
        raBDeg: 10,
        decBDeg: 60,
      );
      expect(sep, closeTo(trueApproxDeg, 0.05));

      final a = SkyMapProjectionService.project(
        raDeg: 0,
        decDeg: 60,
        centerRaDeg: 5,
        centerDecDeg: 60,
        canvasSize: canvas,
        viewHeightDeg: viewHeight,
      );
      final b = SkyMapProjectionService.project(
        raDeg: 10,
        decDeg: 60,
        centerRaDeg: 5,
        centerDecDeg: 60,
        canvasSize: canvas,
        viewHeightDeg: viewHeight,
      );
      final px = _screenSep(a, b);
      final expectedTruePx = SkyMapProjectionService.angularDegreesToPixels(
        degrees: sep,
        canvasSize: canvas,
        viewHeightDeg: viewHeight,
      );
      // 무보정 plate carrée: ΔRA=10°를 10°처럼 그림 → 진각(5°)보다 ~2배 큼
      expect(px / expectedTruePx, closeTo(2.0, 0.05));
    });

    test('cos(centerDec) 보정 시 로컬 RA 간격은 진각에 근접', () {
      final sep = SkyMapProjectionService.angularSeparationDeg(
        raADeg: 0,
        decADeg: 60,
        raBDeg: 10,
        decBDeg: 60,
      );
      final a = _projectWithCosCenterDec(
        raDeg: 0,
        decDeg: 60,
        centerRaDeg: 5,
        centerDecDeg: 60,
        canvasSize: canvas,
        viewHeightDeg: viewHeight,
      );
      final b = _projectWithCosCenterDec(
        raDeg: 10,
        decDeg: 60,
        centerRaDeg: 5,
        centerDecDeg: 60,
        canvasSize: canvas,
        viewHeightDeg: viewHeight,
      );
      final px = _screenSep(a, b);
      final expectedTruePx = SkyMapProjectionService.angularDegreesToPixels(
        degrees: sep,
        canvasSize: canvas,
        viewHeightDeg: viewHeight,
      );
      expect(px / expectedTruePx, closeTo(1.0, 0.05));
    });

    test('남북 pan 시 cos 보정은 가로 스케일 변경(줌 착시) 발생', () {
      // 동일 천체쌍, centerDec만 변경
      final at0 = _projectWithCosCenterDec(
        raDeg: 90,
        decDeg: 0,
        centerRaDeg: 80,
        centerDecDeg: 0,
        canvasSize: canvas,
        viewHeightDeg: 90,
      );
      final at60 = _projectWithCosCenterDec(
        raDeg: 90,
        decDeg: 0,
        centerRaDeg: 80,
        centerDecDeg: 60,
        canvasSize: canvas,
        viewHeightDeg: 90,
      );
      final dx0 = (at0.dx - canvas.width / 2).abs();
      final dx60 = (at60.dx - canvas.width / 2).abs();
      expect(dx60 / dx0, closeTo(0.5, 0.02));
    });

    test('FOV corner path는 project()에 의존 — cos만 넣으면 이중 스케일 위험', () {
      // projectFovCorners는 로컬 east(°)를 RA 가산 후 project() 호출.
      // project()에만 cos를 넣으면 FOV 가로가 cos만큼 또 줄어든다.
      final corners = SkyMapProjectionService.projectFovCorners(
        objectRaDeg: 10,
        objectDecDeg: 60,
        centerRaDeg: 10,
        centerDecDeg: 60,
        fovWidthDeg: 2.0,
        fovHeightDeg: 1.0,
        rotationDeg: 0,
        canvasSize: canvas,
        viewHeightDeg: viewHeight,
      );
      final widthPx = (corners[1] - corners[0]).distance;
      final heightPx = (corners[0] - corners[3]).distance;
      final expectedW = SkyMapProjectionService.angularDegreesToPixels(
        degrees: 2.0,
        canvasSize: canvas,
        viewHeightDeg: viewHeight,
      );
      final expectedH = SkyMapProjectionService.angularDegreesToPixels(
        degrees: 1.0,
        canvasSize: canvas,
        viewHeightDeg: viewHeight,
      );
      // 현재(무보정): FOV °가 픽셀에 1:1 반영
      expect(widthPx, closeTo(expectedW, 0.5));
      expect(heightPx, closeTo(expectedH, 0.5));
    });
  });
}

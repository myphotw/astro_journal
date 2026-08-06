import 'dart:ui';

import 'package:astro_journal/services/sky_map_angular_size.dart';
import 'package:astro_journal/services/sky_map_projection_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const canvas = Size(400, 800);

  test('object/FOV pixel ratio is preserved across zoom', () {
    const objectMajorArcmin = 190.0;
    const fovWidthDeg = 1.28;

    double ratioAt(double viewHeightDeg) {
      final objPx = SkyMapProjectionService.projectObjectSizePx(
        majorArcmin: objectMajorArcmin,
        minorArcmin: 60,
        canvasSize: canvas,
        viewHeightDeg: viewHeightDeg,
      ).width;
      final fovPx = SkyMapProjectionService.angularDegreesToPixels(
        degrees: fovWidthDeg,
        canvasSize: canvas,
        viewHeightDeg: viewHeightDeg,
      );
      return objPx / fovPx;
    }

    final wide = ratioAt(120);
    final mid = ratioAt(40);
    final close = ratioAt(8);

    expect(wide, closeTo(2.474, 0.01));
    expect(mid, closeTo(wide, 0.001));
    expect(close, closeTo(wide, 0.001));
  });

  test('FOV grows on zoom-in and shrinks on zoom-out', () {
    double fovHeightPx(double viewHeightDeg) {
      final corners = SkyMapProjectionService.projectFovCorners(
        objectRaDeg: 10.68,
        objectDecDeg: 41.27,
        centerRaDeg: 10.68,
        centerDecDeg: 41.27,
        fovWidthDeg: 1.28,
        fovHeightDeg: 0.72,
        rotationDeg: 0,
        canvasSize: canvas,
        viewHeightDeg: viewHeightDeg,
      );
      return (corners[2] - corners[1]).distance;
    }

    final zoomedOut = fovHeightPx(120);
    final mid = fovHeightPx(40);
    final zoomedIn = fovHeightPx(10);

    expect(zoomedOut, lessThan(mid));
    expect(mid, lessThan(zoomedIn));
    // 전체 하늘(120°)에서 S50 FOV(0.72°)는 화면의 0.6%만 차지
    expect(zoomedOut / canvas.height, closeTo(0.72 / 120, 0.001));
  });

  test('arcmin equipment FOV is normalized to degrees', () {
    final n = SkyMapAngularSize.normalizeEquipmentFovDeg(
      width: 128,
      height: 72,
    );
    expect(n.widthDeg, closeTo(128 / 60, 0.001));
    expect(n.heightDeg, closeTo(72 / 60, 0.001));
  });

  test('shortestRaDeltaDeg folds across 0/360', () {
    expect(
      SkyMapProjectionService.shortestRaDeltaDeg(346.19, 3.31),
      closeTo(17.12, 0.01),
    );
    expect(
      SkyMapProjectionService.isRaWrapCrossing(346.19, 3.31),
      isTrue,
    );
    expect(
      SkyMapProjectionService.isRaWrapCrossing(84.05, 85.19),
      isFalse,
    );
  });

  test('wrap-crossing Pegasus edge is skipped when view is far from RA 0', () {
    // markab ↔ algenib (Great Square side across RA wrap)
    const markabRa = 346.1902;
    const markabDec = 15.2053;
    const algenibRa = 3.3089;
    const algenibDec = 15.1836;

    final a = SkyMapProjectionService.project(
      raDeg: markabRa,
      decDeg: markabDec,
      centerRaDeg: 180,
      centerDecDeg: 20,
      canvasSize: canvas,
      viewHeightDeg: 90,
    );
    final b = SkyMapProjectionService.project(
      raDeg: algenibRa,
      decDeg: algenibDec,
      centerRaDeg: 180,
      centerDecDeg: 20,
      canvasSize: canvas,
      viewHeightDeg: 90,
    );

    expect(
      SkyMapProjectionService.shouldDrawConstellationSegment(
        raADeg: markabRa,
        decADeg: markabDec,
        raBDeg: algenibRa,
        decBDeg: algenibDec,
        projectedA: a,
        projectedB: b,
        canvasSize: canvas,
        viewHeightDeg: 90,
      ),
      isFalse,
    );
  });

  test('NS pan does not change horizontal scale (plate carree)', () {
    // 같은 ΔRA가 center Dec와 무관하게 동일 픽셀 폭
    final atEq = SkyMapProjectionService.project(
      raDeg: 90,
      decDeg: 0,
      centerRaDeg: 80,
      centerDecDeg: 0,
      canvasSize: canvas,
      viewHeightDeg: 90,
    );
    final atHigh = SkyMapProjectionService.project(
      raDeg: 90,
      decDeg: 0,
      centerRaDeg: 80,
      centerDecDeg: 60,
      canvasSize: canvas,
      viewHeightDeg: 90,
    );
    final dxEq = atEq.dx - canvas.width / 2;
    final dxHigh = atHigh.dx - canvas.width / 2;
    expect(dxEq, closeTo(dxHigh, 0.001));
  });

  test('tiny object marker scales with FOV across zoom', () {
    double markerOverFov(double viewHeightDeg) {
      final obj = SkyMapProjectionService.projectWithSize(
        raDeg: 270,
        decDeg: -17,
        centerRaDeg: 270,
        centerDecDeg: -17,
        canvasSize: canvas,
        viewHeightDeg: viewHeightDeg,
        majorArcmin: 1, // M18-like tiny / unknown → minDisplayArcmin
        minorArcmin: 1,
      );
      final fovH = SkyMapProjectionService.angularDegreesToPixels(
        degrees: 0.72,
        canvasSize: canvas,
        viewHeightDeg: viewHeightDeg,
      );
      return obj.renderHeight / fovH;
    }

    final a = markerOverFov(120);
    final b = markerOverFov(40);
    final c = markerOverFov(10);
    expect(a, closeTo(b, 0.001));
    expect(b, closeTo(c, 0.001));
    // minDisplay 6' / 0.72° = 0.1 / 0.72
    expect(
      a,
      closeTo(SkyMapProjectionService.minDisplayArcmin / 60 / 0.72, 0.001),
    );
  });

  test('Orion belt segment is kept', () {
    const mintakaRa = 83.0017;
    const mintakaDec = -0.2991;
    const alnilamRa = 84.0534;
    const alnilamDec = -1.2019;

    final a = SkyMapProjectionService.project(
      raDeg: mintakaRa,
      decDeg: mintakaDec,
      centerRaDeg: 83.5,
      centerDecDeg: 0,
      canvasSize: canvas,
      viewHeightDeg: 40,
    );
    final b = SkyMapProjectionService.project(
      raDeg: alnilamRa,
      decDeg: alnilamDec,
      centerRaDeg: 83.5,
      centerDecDeg: 0,
      canvasSize: canvas,
      viewHeightDeg: 40,
    );

    expect(
      SkyMapProjectionService.shouldDrawConstellationSegment(
        raADeg: mintakaRa,
        decADeg: mintakaDec,
        raBDeg: alnilamRa,
        decBDeg: alnilamDec,
        projectedA: a,
        projectedB: b,
        canvasSize: canvas,
        viewHeightDeg: 40,
      ),
      isTrue,
    );
  });
}

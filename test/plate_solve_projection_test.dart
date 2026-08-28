import 'dart:math' as math;

import 'package:astro_journal/services/plate_solve/fits_wcs_parser.dart';
import 'package:astro_journal/services/plate_solve_projection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FitsWcsHeader', () {
    test('parses CD + CRVAL/CRPIX from FITS cards', () {
      final cards = [
        "SIMPLE  =                    T /",
        "CRVAL1  =            279.09975 /",
        "CRVAL2  =           -23.904308 /",
        "CRPIX1  =                800.5 /",
        "CRPIX2  =                600.5 /",
        "CD1_1   =         -0.000277778 /",
        "CD1_2   =                   0. /",
        "CD2_1   =                   0. /",
        "CD2_2   =          0.000277778 /",
        "END",
      ];
      final text = cards.map((c) => c.padRight(80)).join();
      final wcs = FitsWcsHeader.tryParseText(text)!;
      expect(wcs.crval1, closeTo(279.09975, 1e-6));
      expect(wcs.crval2, closeTo(-23.904308, 1e-6));
      expect(wcs.crpix1, closeTo(800.5, 1e-6));
      expect(wcs.cd11, closeTo(-0.000277778, 1e-9));
    });

    test('scaleToOriginal preserves pixel-center CRPIX', () {
      const wcs = FitsWcsHeader(
        crval1: 100,
        crval2: 0,
        crpix1: 500.5,
        crpix2: 400.5,
        cd11: -0.001,
        cd12: 0,
        cd21: 0,
        cd22: 0.001,
      );
      final scaled = wcs.scaleToOriginal(
        uploadWidth: 1000,
        uploadHeight: 800,
        originalWidth: 2000,
        originalHeight: 1600,
      );
      expect(scaled.crpix1, closeTo(1000.5, 1e-9));
      expect(scaled.crpix2, closeTo(800.5, 1e-9));
      expect(scaled.cd11, closeTo(-0.0005, 1e-12));
      expect(scaled.cd22, closeTo(0.0005, 1e-12));
    });
  });

  group('PlateSolveProjection WCS', () {
    test('worldToPixelFromWcs maps CRVAL to CRPIX display center', () {
      const wcs = FitsWcsHeader(
        crval1: 279.09975,
        crval2: -23.904308,
        crpix1: 2000.5,
        crpix2: 1500.5,
        cd11: -0.0002,
        cd12: 0,
        cd21: 0,
        cd22: 0.0002,
      );
      final pixel = PlateSolveProjection.worldToPixelFromWcs(
        wcs: wcs,
        targetRaDeg: 279.09975,
        targetDecDeg: -23.904308,
      );
      expect(pixel.x, closeTo(2000.0, 1e-6));
      expect(pixel.y, closeTo(1500.0, 1e-6));
    });

    test('worldToPixelFromWcs places M22 east of CRVAL correctly', () {
      // ~1"/px, north up, east left (typical photo parity)
      const wcs = FitsWcsHeader(
        crval1: 279.1,
        crval2: -23.9,
        crpix1: 2000.5,
        crpix2: 1500.5,
        cd11: -0.000277778,
        cd12: 0,
        cd21: 0,
        cd22: 0.000277778,
      );
      // +0.1° RA ≈ east → smaller X when CD1_1 < 0
      final east = PlateSolveProjection.worldToPixelFromWcs(
        wcs: wcs,
        targetRaDeg: 279.2,
        targetDecDeg: -23.9,
      );
      expect(east.x, lessThan(2000));
      expect(east.y, closeTo(1500, 2));
    });

    test('center target maps to image center', () {
      final pixel = PlateSolveProjection.worldToPixel(
        centerRaDeg: 180,
        centerDecDeg: 20,
        targetRaDeg: 180,
        targetDecDeg: 20,
        orientationDeg: 35,
        pixelScaleArcsec: 1.5,
        imageWidth: 4000,
        imageHeight: 3000,
        parity: 1,
      );
      expect(pixel.x, closeTo(2000, 1e-6));
      expect(pixel.y, closeTo(1500, 1e-6));
    });

    test('east and west land on opposite sides of center', () {
      final east = PlateSolveProjection.worldToPixel(
        centerRaDeg: 180,
        centerDecDeg: 0,
        targetRaDeg: 180.1,
        targetDecDeg: 0,
        orientationDeg: 0,
        pixelScaleArcsec: 36,
        imageWidth: 1000,
        imageHeight: 1000,
        parity: 1,
      );
      final west = PlateSolveProjection.worldToPixel(
        centerRaDeg: 180,
        centerDecDeg: 0,
        targetRaDeg: 179.9,
        targetDecDeg: 0,
        orientationDeg: 0,
        pixelScaleArcsec: 36,
        imageWidth: 1000,
        imageHeight: 1000,
        parity: 1,
      );
      expect((east.x - 500) * (west.x - 500), lessThan(0));
      expect(east.y, closeTo(500, 2));
      expect(west.y, closeTo(500, 2));
    });

    test('north and south land on opposite sides of center', () {
      final north = PlateSolveProjection.worldToPixel(
        centerRaDeg: 180,
        centerDecDeg: 0,
        targetRaDeg: 180,
        targetDecDeg: 0.1,
        orientationDeg: 0,
        pixelScaleArcsec: 36,
        imageWidth: 1000,
        imageHeight: 1000,
        parity: 1,
      );
      final south = PlateSolveProjection.worldToPixel(
        centerRaDeg: 180,
        centerDecDeg: 0,
        targetRaDeg: 180,
        targetDecDeg: -0.1,
        orientationDeg: 0,
        pixelScaleArcsec: 36,
        imageWidth: 1000,
        imageHeight: 1000,
        parity: 1,
      );
      expect((north.y - 500) * (south.y - 500), lessThan(0));
      expect(north.x, closeTo(500, 2));
      expect(south.x, closeTo(500, 2));
    });

    test('parity -1 mirrors east/west relative to parity +1', () {
      const args = (
        centerRa: 180.0,
        centerDec: 10.0,
        targetRa: 180.2,
        targetDec: 10.0,
        orient: 15.0,
        scale: 2.0,
        w: 2000,
        h: 1500,
      );
      final pPos = PlateSolveProjection.worldToPixel(
        centerRaDeg: args.centerRa,
        centerDecDeg: args.centerDec,
        targetRaDeg: args.targetRa,
        targetDecDeg: args.targetDec,
        orientationDeg: args.orient,
        pixelScaleArcsec: args.scale,
        imageWidth: args.w,
        imageHeight: args.h,
        parity: 1,
      );
      final pNeg = PlateSolveProjection.worldToPixel(
        centerRaDeg: args.centerRa,
        centerDecDeg: args.centerDec,
        targetRaDeg: args.targetRa,
        targetDecDeg: args.targetDec,
        orientationDeg: args.orient,
        pixelScaleArcsec: args.scale,
        imageWidth: args.w,
        imageHeight: args.h,
        parity: -1,
      );
      final dxPos = pPos.x - args.w / 2;
      final dxNeg = pNeg.x - args.w / 2;
      expect(dxPos * dxNeg, lessThan(0));
    });

    test('CD reconstruction matches tan_get_orientation', () {
      for (final orient in [0.0, 35.0, -80.0, 170.0]) {
        for (final parity in [1.0, -1.0]) {
          final cd = PlateSolveProjection.cdMatrix(
            pixelScaleArcsec: 1.25,
            orientationDeg: orient,
            parity: parity,
          );
          final det = cd.cd11 * cd.cd22 - cd.cd12 * cd.cd21;
          final p = det >= 0 ? 1.0 : -1.0;
          expect(p, parity);
          final t = p * cd.cd11 + cd.cd22;
          final a = p * cd.cd21 - cd.cd12;
          final recovered = -math.atan2(a, t) * 180 / math.pi;
          var diff = (recovered - orient + 540) % 360 - 180;
          expect(diff.abs(), lessThan(1e-6));
        }
      }
    });

    test('edge offset grows roughly linearly with angular distance', () {
      final near = PlateSolveProjection.worldToPixel(
        centerRaDeg: 100,
        centerDecDeg: 20,
        targetRaDeg: 100.05,
        targetDecDeg: 20,
        orientationDeg: 10,
        pixelScaleArcsec: 1.0,
        imageWidth: 3000,
        imageHeight: 2000,
        parity: 1,
      );
      final far = PlateSolveProjection.worldToPixel(
        centerRaDeg: 100,
        centerDecDeg: 20,
        targetRaDeg: 100.20,
        targetDecDeg: 20,
        orientationDeg: 10,
        pixelScaleArcsec: 1.0,
        imageWidth: 3000,
        imageHeight: 2000,
        parity: 1,
      );
      final dNear = (near.x - 1500).abs();
      final dFar = (far.x - 1500).abs();
      expect(dFar / dNear, closeTo(4.0, 0.15));
    });

    test('RA wrap-around crosses 360 degrees through the short path', () {
      final eastAcrossZero = PlateSolveProjection.worldToPixel(
        centerRaDeg: 359.9,
        centerDecDeg: 0,
        targetRaDeg: 0.0,
        targetDecDeg: 0,
        orientationDeg: 0,
        pixelScaleArcsec: 36,
        imageWidth: 1000,
        imageHeight: 1000,
        parity: 1,
      );
      final ordinaryEast = PlateSolveProjection.worldToPixel(
        centerRaDeg: 180,
        centerDecDeg: 0,
        targetRaDeg: 180.1,
        targetDecDeg: 0,
        orientationDeg: 0,
        pixelScaleArcsec: 36,
        imageWidth: 1000,
        imageHeight: 1000,
        parity: 1,
      );

      expect(eastAcrossZero.x, closeTo(ordinaryEast.x, 0.01));
      expect(eastAcrossZero.y, closeTo(ordinaryEast.y, 0.01));
    });

    test('TAN projection applies cos(dec) to small RA offsets', () {
      final equator = PlateSolveProjection.tangentIwcDeg(
        centerRaDeg: 180,
        centerDecDeg: 0,
        targetRaDeg: 180.1,
        targetDecDeg: 0,
      );
      final highDeclination = PlateSolveProjection.tangentIwcDeg(
        centerRaDeg: 180,
        centerDecDeg: 60,
        targetRaDeg: 180.1,
        targetDecDeg: 60,
      );

      expect(highDeclination.xDeg / equator.xDeg, closeTo(0.5, 0.002));
    });

    test('rotation 0 90 180 follows reconstructed CD contract', () {
      PixelOffset northAt(double orientation) =>
          PlateSolveProjection.worldToPixel(
            centerRaDeg: 180,
            centerDecDeg: 0,
            targetRaDeg: 180,
            targetDecDeg: 0.1,
            orientationDeg: orientation,
            pixelScaleArcsec: 36,
            imageWidth: 1000,
            imageHeight: 1000,
            parity: 1,
          );

      final at0 = northAt(0);
      final at90 = northAt(90);
      final at180 = northAt(180);
      expect(at0.y, greaterThan(500));
      expect(at90.x, lessThan(500));
      expect(at180.y, lessThan(500));
    });

    test('rotation moves north vector around the image', () {
      PixelOffset at(double orient) => PlateSolveProjection.worldToPixel(
        centerRaDeg: 180,
        centerDecDeg: 0,
        targetRaDeg: 180,
        targetDecDeg: 0.1,
        orientationDeg: orient,
        pixelScaleArcsec: 36,
        imageWidth: 1000,
        imageHeight: 1000,
        parity: 1,
      );

      final o0 = at(0);
      final o90 = at(90);
      // 90° rotation should swap dominant axis of the offset
      final d0x = (o0.x - 500).abs();
      final d0y = (o0.y - 500).abs();
      final d90x = (o90.x - 500).abs();
      final d90y = (o90.y - 500).abs();
      expect(d0y, greaterThan(d0x));
      expect(d90x, greaterThan(d90y));
    });
  });
}

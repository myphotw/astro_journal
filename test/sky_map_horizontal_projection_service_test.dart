import 'dart:ui';

import 'package:astro_journal/features/sky_map/viewmodel/sky_map_view_model.dart';
import 'package:astro_journal/services/celestial_position_service.dart';
import 'package:astro_journal/services/sky_map_horizontal_projection_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const canvas = Size(800, 800);

  group('SkyMapHorizontalProjectionService', () {
    test('initial directional view places the horizon near the lower edge', () {
      for (final size in const [Size(1280, 720), Size(360, 640)]) {
        final horizon = SkyMapHorizontalProjectionService.project(
          altitudeDeg: 0,
          azimuthDeg: SkyMapViewModel.defaultCenterAzimuthDeg,
          centerAltitudeDeg: SkyMapViewModel.defaultCenterAltitudeDeg,
          centerAzimuthDeg: SkyMapViewModel.defaultCenterAzimuthDeg,
          canvasSize: size,
          viewHeightDeg: SkyMapViewModel.defaultViewHeightDeg,
        ).pixel;

        expect(horizon.dx, closeTo(size.width / 2, 1e-8));
        expect(
          horizon.dy / size.height,
          closeTo(SkyMapViewModel.defaultHorizonScreenFraction, 1e-8),
        );
      }
    });

    test('projects shared RA/Dec Alt/Az result to the screen center', () {
      final altAz = CelestialPositionService.computeAltAz(
        raHours: 5.5,
        decDeg: -5.4,
        latDeg: 37.5,
        lonDeg: 127,
        time: DateTime.utc(2026, 1, 15, 12),
      );

      final projected = SkyMapHorizontalProjectionService.project(
        altitudeDeg: altAz.altitude,
        azimuthDeg: altAz.azimuth,
        centerAltitudeDeg: altAz.altitude,
        centerAzimuthDeg: altAz.azimuth,
        canvasSize: canvas,
        viewHeightDeg: 60,
      );

      expect(projected.pixel, const Offset(400, 400));
      expect(projected.angularDistanceDeg, closeTo(0, 1e-8));
    });

    test('zenith all-sky view places every horizon direction on its rim', () {
      Offset point(double azimuth) => SkyMapHorizontalProjectionService.project(
        altitudeDeg: 0,
        azimuthDeg: azimuth,
        centerAltitudeDeg: 90,
        centerAzimuthDeg: 180,
        canvasSize: canvas,
        viewHeightDeg: 180,
      ).pixel;

      expect(point(0).dx, closeTo(400, 1e-6));
      expect(point(0).dy, closeTo(0, 1e-6));
      expect(point(90).dx, closeTo(0, 1e-6));
      expect(point(90).dy, closeTo(400, 1e-6));
      expect(point(180).dx, closeTo(400, 1e-6));
      expect(point(180).dy, closeTo(800, 1e-6));
      expect(point(270).dx, closeTo(800, 1e-6));
      expect(point(270).dy, closeTo(400, 1e-6));
    });

    test('azimuth zero and 360 are the same projected position', () {
      final atZero = SkyMapHorizontalProjectionService.project(
        altitudeDeg: 25,
        azimuthDeg: 0,
        centerAltitudeDeg: 45,
        centerAzimuthDeg: 355,
        canvasSize: canvas,
        viewHeightDeg: 80,
      ).pixel;
      final atFullTurn = SkyMapHorizontalProjectionService.project(
        altitudeDeg: 25,
        azimuthDeg: 360,
        centerAltitudeDeg: 45,
        centerAzimuthDeg: 355,
        canvasSize: canvas,
        viewHeightDeg: 80,
      ).pixel;

      expect((atZero - atFullTurn).distance, closeTo(0, 1e-8));
    });

    test('negative altitudes project and unproject without remapping', () {
      final projected = SkyMapHorizontalProjectionService.project(
        altitudeDeg: -25,
        azimuthDeg: 135,
        centerAltitudeDeg: 10,
        centerAzimuthDeg: 150,
        canvasSize: canvas,
        viewHeightDeg: 100,
      );
      final restored = SkyMapHorizontalProjectionService.unproject(
        pixel: projected.pixel,
        centerAltitudeDeg: 10,
        centerAzimuthDeg: 150,
        canvasSize: canvas,
        viewHeightDeg: 100,
      );

      expect(restored.altitudeDeg, closeTo(-25, 1e-8));
      expect(restored.azimuthDeg, closeTo(135, 1e-8));
    });

    test('screen position stays continuous while crossing the horizon', () {
      Offset at(double altitude) => SkyMapHorizontalProjectionService.project(
        altitudeDeg: altitude,
        azimuthDeg: 170,
        centerAltitudeDeg: 15,
        centerAzimuthDeg: 180,
        canvasSize: canvas,
        viewHeightDeg: 80,
      ).pixel;

      final belowStep = (at(0) - at(-0.01)).distance;
      final aboveStep = (at(0.01) - at(0)).distance;

      expect(belowStep, closeTo(aboveStep, 1e-5));
      expect(belowStep, lessThan(0.2));
    });

    test('zoom uses one continuous projection without a mode boundary', () {
      Offset at(double fov) => SkyMapHorizontalProjectionService.project(
        altitudeDeg: 40,
        azimuthDeg: 145,
        centerAltitudeDeg: 55,
        centerAzimuthDeg: 160,
        canvasSize: canvas,
        viewHeightDeg: fov,
      ).pixel;

      final center = const Offset(400, 400);
      final wide = (at(120) - center).distance;
      final medium = (at(60) - center).distance;
      final narrow = (at(30) - center).distance;

      expect(medium / wide, closeTo(2, 1e-9));
      expect(narrow / medium, closeTo(2, 1e-9));
    });

    test(
      'dragging changes center to the sky direction under the moved pixel',
      () {
        const delta = Offset(80, -40);
        final next = SkyMapHorizontalProjectionService.panCenter(
          delta: delta,
          centerAltitudeDeg: 70,
          centerAzimuthDeg: 180,
          canvasSize: canvas,
          viewHeightDeg: 90,
        );
        final inOldView = SkyMapHorizontalProjectionService.project(
          altitudeDeg: next.altitudeDeg,
          azimuthDeg: next.azimuthDeg,
          centerAltitudeDeg: 70,
          centerAzimuthDeg: 180,
          canvasSize: canvas,
          viewHeightDeg: 90,
        ).pixel;

        expect(inOldView.dx, closeTo(400 - delta.dx, 1e-7));
        expect(inOldView.dy, closeTo(400 - delta.dy, 1e-7));
      },
    );

    test('constellation segment remains short across azimuth wrap', () {
      final a = SkyMapHorizontalProjectionService.project(
        altitudeDeg: 35,
        azimuthDeg: 359,
        centerAltitudeDeg: 35,
        centerAzimuthDeg: 0,
        canvasSize: canvas,
        viewHeightDeg: 40,
      ).pixel;
      final b = SkyMapHorizontalProjectionService.project(
        altitudeDeg: 35,
        azimuthDeg: 1,
        centerAltitudeDeg: 35,
        centerAzimuthDeg: 0,
        canvasSize: canvas,
        viewHeightDeg: 40,
      ).pixel;

      expect(
        SkyMapHorizontalProjectionService.shouldDrawConstellationSegment(
          altitudeADeg: 35,
          azimuthADeg: 359,
          altitudeBDeg: 35,
          azimuthBDeg: 1,
          projectedA: a,
          projectedB: b,
          canvasSize: canvas,
          viewHeightDeg: 40,
        ),
        isTrue,
      );
      expect((a - b).distance, lessThan(50));
    });

    test('equipment FOV remains a four-corner overlay around its target', () {
      final target = SkyMapHorizontalProjectionService.project(
        altitudeDeg: 45,
        azimuthDeg: 180,
        centerAltitudeDeg: 45,
        centerAzimuthDeg: 180,
        canvasSize: canvas,
        viewHeightDeg: 30,
      ).pixel;
      final corners = SkyMapHorizontalProjectionService.projectFovCorners(
        objectAltitudeDeg: 45,
        objectAzimuthDeg: 180,
        centerAltitudeDeg: 45,
        centerAzimuthDeg: 180,
        fovWidthDeg: 2,
        fovHeightDeg: 1,
        rotationDeg: 30,
        canvasSize: canvas,
        viewHeightDeg: 30,
      );

      expect(corners, hasLength(4));
      final average = corners.reduce((a, b) => a + b) / 4;
      expect((average - target).distance, lessThan(0.1));
    });
  });
}

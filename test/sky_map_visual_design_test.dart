import 'dart:ui';

import 'package:astro_journal/data/models/sky_map_render_object.dart';
import 'package:astro_journal/features/sky_map/widgets/painters/sky_map_background_painter.dart';
import 'package:astro_journal/features/sky_map/widgets/sky_map_visual_style.dart';
import 'package:astro_journal/services/sky_map_horizontal_projection_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Sky Map V2 visual design', () {
    test('grid density follows the visible angular range', () {
      expect(SkyMapBackgroundPainter.gridIntervalFor(180), 30);
      expect(SkyMapBackgroundPainter.gridIntervalFor(90), 15);
      expect(SkyMapBackgroundPainter.gridIntervalFor(45), 10);
      expect(SkyMapBackgroundPainter.gridIntervalFor(20), 5);
    });

    test('cardinal direction labels are localized without moving azimuths', () {
      expect(SkyMapBackgroundPainter.cardinalLabels, const [
        (azimuth: 0.0, label: '북'),
        (azimuth: 90.0, label: '동'),
        (azimuth: 180.0, label: '남'),
        (azimuth: 270.0, label: '서'),
      ]);
      expect(SkyMapBackgroundPainter.cardinalFontSize, 20);
      expect(
        SkyMapBackgroundPainter.cardinalLabelColor,
        const Color(0xFFFFF8E7),
      );
    });

    test('object types retain distinct palette colors', () {
      final colors = SkyMapShapeKind.values
          .map(SkyMapVisualStyle.objectColor)
          .toSet();

      expect(colors, hasLength(SkyMapShapeKind.values.length));
      expect(
        SkyMapVisualStyle.objectColor(SkyMapShapeKind.galaxy),
        SkyMapVisualStyle.galaxy,
      );
      expect(
        SkyMapVisualStyle.objectColor(SkyMapShapeKind.nebula),
        SkyMapVisualStyle.nebula,
      );
    });

    test('sun altitude selects the standard daylight and twilight phases', () {
      expect(SkyMapVisualStyle.lightPhaseFor(5), SkyMapLightPhase.day);
      expect(
        SkyMapVisualStyle.lightPhaseFor(-3),
        SkyMapLightPhase.civilTwilight,
      );
      expect(
        SkyMapVisualStyle.lightPhaseFor(-9),
        SkyMapLightPhase.nauticalTwilight,
      );
      expect(
        SkyMapVisualStyle.lightPhaseFor(-15),
        SkyMapLightPhase.astronomicalTwilight,
      );
      expect(SkyMapVisualStyle.lightPhaseFor(-19), SkyMapLightPhase.night);
    });

    test('sky colors interpolate continuously through twilight boundaries', () {
      for (final boundary in const [-18.0, -12.0, -6.0, 0.0]) {
        final before = SkyMapVisualStyle.skyColorFor(boundary - 0.001);
        final after = SkyMapVisualStyle.skyColorFor(boundary + 0.001);

        expect(_colorDistance(before, after), lessThan(0.002));
      }
      expect(SkyMapVisualStyle.skyColorFor(-18), SkyMapVisualStyle.background);
    });

    test('ground stays darker than the sky at night, twilight, and day', () {
      for (final altitude in const [-24.0, -15.0, -8.0, -2.0, 20.0]) {
        final sky = SkyMapVisualStyle.skyColorFor(altitude);
        final ground = SkyMapVisualStyle.groundColorFor(altitude);

        expect(ground.computeLuminance(), lessThan(sky.computeLuminance()));
      }
    });

    test('below-horizon objects fade without a discontinuity at zero', () {
      expect(SkyMapVisualStyle.visibilityForAltitude(-10), 0.30);
      expect(SkyMapVisualStyle.visibilityForAltitude(-3), 0.30);
      expect(SkyMapVisualStyle.visibilityForAltitude(2), 1);
      expect(
        SkyMapVisualStyle.visibilityForAltitude(-0.001),
        closeTo(SkyMapVisualStyle.visibilityForAltitude(0.001), 0.001),
      );
    });

    test('background painter handles mixed sky and ground views', () {
      for (final centerAltitude in const [90.0, 15.0, -20.0]) {
        final recorder = PictureRecorder();
        final canvas = Canvas(recorder);
        final painter = SkyMapBackgroundPainter(
          centerAltitudeDeg: centerAltitude,
          centerAzimuthDeg: 180,
          viewHeightDeg: centerAltitude == 90 ? 180 : 60,
          sunAltitudeDeg: -8,
          sunAzimuthDeg: 250,
        );

        expect(
          () => painter.paint(canvas, const Size(800, 600)),
          returnsNormally,
        );
        recorder.endRecording().dispose();
      }
    });

    test('day sky brightens from zenith toward the horizon', () {
      final zenith = SkyMapVisualStyle.atmosphericColorFor(
        altitudeDeg: 90,
        azimuthDeg: 180,
        sunAltitudeDeg: 30,
        sunAzimuthDeg: 180,
      );
      final horizon = SkyMapVisualStyle.atmosphericColorFor(
        altitudeDeg: 0,
        azimuthDeg: 180,
        sunAltitudeDeg: 30,
        sunAzimuthDeg: 180,
      );

      expect(
        horizon.computeLuminance(),
        greaterThan(zenith.computeLuminance()),
      );
    });

    test('twilight warmth is localized toward the sun', () {
      final towardSun = SkyMapVisualStyle.atmosphericColorFor(
        altitudeDeg: 2,
        azimuthDeg: 260,
        sunAltitudeDeg: -5,
        sunAzimuthDeg: 260,
      );
      final opposite = SkyMapVisualStyle.atmosphericColorFor(
        altitudeDeg: 2,
        azimuthDeg: 80,
        sunAltitudeDeg: -5,
        sunAzimuthDeg: 260,
      );

      expect(towardSun.r, greaterThan(opposite.r));
      expect(towardSun.b, lessThan(opposite.b));
    });

    test('ground darkens continuously below the horizon', () {
      Color ground(double altitude) =>
          SkyMapVisualStyle.atmosphericGroundColorFor(
            altitudeDeg: altitude,
            azimuthDeg: 220,
            sunAltitudeDeg: -8,
            sunAzimuthDeg: 220,
          );

      expect(
        ground(-60).computeLuminance(),
        lessThan(ground(-1).computeLuminance()),
      );
    });

    test('azimuth labels stay near a visible horizon intersection', () {
      const size = Size(800, 600);
      const painter = SkyMapBackgroundPainter(
        centerAltitudeDeg: 15,
        centerAzimuthDeg: 180,
        viewHeightDeg: 60,
        sunAltitudeDeg: -20,
        sunAzimuthDeg: 270,
      );
      final placement = painter.debugAzimuthLabelPlacement(180, size)!;
      final horizon = SkyMapHorizontalProjectionService.project(
        altitudeDeg: 0,
        azimuthDeg: 180,
        centerAltitudeDeg: 15,
        centerAzimuthDeg: 180,
        canvasSize: size,
        viewHeightDeg: 60,
      ).pixel;

      expect(placement.auxiliary, isFalse);
      expect((placement.position - horizon).distance, lessThan(25));
      expect(placement.altitudeDeg.abs(), lessThanOrEqualTo(2));
    });

    test('azimuth labels use the viewport edge when horizon is outside', () {
      const size = Size(800, 600);
      const painter = SkyMapBackgroundPainter(
        centerAltitudeDeg: 60,
        centerAzimuthDeg: 180,
        viewHeightDeg: 30,
        sunAltitudeDeg: -20,
        sunAzimuthDeg: 270,
      );
      final placement = painter.debugAzimuthLabelPlacement(180, size)!;

      expect(placement.auxiliary, isTrue);
      expect(placement.position.dx, inInclusiveRange(0, size.width));
      expect(placement.position.dy, inInclusiveRange(0, size.height));
      expect(
        [
          placement.position.dx,
          size.width - placement.position.dx,
          placement.position.dy,
          size.height - placement.position.dy,
        ].reduce((a, b) => a < b ? a : b),
        lessThanOrEqualTo(14),
      );
    });

    test('altitude labels share the exact projected altitude-grid point', () {
      const size = Size(800, 600);
      const painter = SkyMapBackgroundPainter(
        centerAltitudeDeg: 35,
        centerAzimuthDeg: 172,
        viewHeightDeg: 60,
        sunAltitudeDeg: -20,
        sunAzimuthDeg: 270,
      );
      final label = painter.debugAltitudeLabelPosition(30, 15, size);
      final gridPoint = SkyMapHorizontalProjectionService.project(
        altitudeDeg: 30,
        azimuthDeg: 165,
        centerAltitudeDeg: 35,
        centerAzimuthDeg: 172,
        canvasSize: size,
        viewHeightDeg: 60,
      ).pixel;

      expect((label - gridPoint).distance, closeTo(0, 1e-9));
    });
  });
}

double _colorDistance(Color a, Color b) {
  final red = (a.r - b.r).abs();
  final green = (a.g - b.g).abs();
  final blue = (a.b - b.b).abs();
  return red + green + blue;
}

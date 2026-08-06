import 'package:astro_journal/data/models/brightness_cell.dart';
import 'package:astro_journal/data/models/bortle_metadata.dart';
import 'package:astro_journal/features/light_pollution_map/overlay/light_pollution_tile_generator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LightPollutionTileGenerator bilinear', () {
    final metadata = BortleMetadata(
      originX: 123.4998786,
      originY: 39.80418496,
      pixelWidth: 0.00833333,
      pixelHeight: 0.00833333,
      width: 1080,
      height: 876,
      crs: 'EPSG:4326',
      west: 123.4998786,
      south: 32.50418788,
      east: 132.499875,
      north: 39.80418496,
      atlasName: 'World_Atlas_2015',
      atlasVersion: '2015',
      builderVersion: '1.0.0',
      generatedAt: 'test',
    );

    /// 제주 타일(z=11) 근처 조밀한 가짜 셀.
    List<BrightnessCell> _jejuCells() {
      final cells = <BrightnessCell>[];
      for (var row = 730; row <= 820; row++) {
        for (var col = 300; col <= 450; col++) {
          final t = ((row - 730) + (col - 300)) / 240.0;
          cells.add(BrightnessCell(row: row, col: col, brightness: 0.2 + t * 4));
        }
      }
      return cells;
    }

    test('generatePng returns non-null PNG for Jeju tile', () async {
      // Jeju City ~ tile 1743,821 @ z11
      final png = await LightPollutionTileGenerator.generatePng(
        metadata: metadata,
        cells: _jejuCells(),
        tileX: 1743,
        tileY: 821,
        zoom: 11,
      );
      expect(png, isNotNull);
      expect(png!.length, greaterThan(100));
    });

    test('benchmark generatePng Jeju z11 (5 runs)', () async {
      final cells = _jejuCells();
      // warm-up
      await LightPollutionTileGenerator.generatePng(
        metadata: metadata,
        cells: cells,
        tileX: 1743,
        tileY: 821,
        zoom: 11,
      );

      final sw = Stopwatch()..start();
      const runs = 5;
      for (var i = 0; i < runs; i++) {
        final png = await LightPollutionTileGenerator.generatePng(
          metadata: metadata,
          cells: cells,
          tileX: 1743,
          tileY: 821,
          zoom: 11,
        );
        expect(png, isNotNull);
      }
      sw.stop();
      final avgMs = sw.elapsedMilliseconds / runs;
      // ignore: avoid_print
      print('bilin1 generatePng avg ${avgMs.toStringAsFixed(1)} ms '
          '(cells=${cells.length}, zoom=11, stride=4)');
      expect(avgMs, lessThan(2000));
    });
  });
}

import 'package:astro_journal/features/light_pollution_map/overlay/light_pollution_tile_constants.dart';
import 'package:astro_journal/features/light_pollution_map/overlay/light_pollution_tile_mercator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LightPollutionTileConstants', () {
    test('samplingStrideForZoom returns expected tiers', () {
      expect(LightPollutionTileConstants.samplingStrideForZoom(6), 8);
      expect(LightPollutionTileConstants.samplingStrideForZoom(7), 8);
      expect(LightPollutionTileConstants.samplingStrideForZoom(8), 6);
      expect(LightPollutionTileConstants.samplingStrideForZoom(10), 6);
      expect(LightPollutionTileConstants.samplingStrideForZoom(11), 4);
      expect(LightPollutionTileConstants.samplingStrideForZoom(13), 4);
      expect(LightPollutionTileConstants.samplingStrideForZoom(14), 2);
      expect(LightPollutionTileConstants.samplingStrideForZoom(15), 2);
    });

    test('default overlay opacity is 0.42', () {
      expect(
        LightPollutionTileConstants.defaultOverlayOpacity,
        0.42,
      );
    });
  });

  group('LightPollutionTileMercator', () {
    test('tileBounds returns north greater than south', () {
      final bounds = LightPollutionTileMercator.tileBounds(100, 50, 8);
      expect(bounds.north, greaterThan(bounds.south));
      expect(bounds.east, greaterThan(bounds.west));
    });

    test('tileXToLng increases with x', () {
      final west = LightPollutionTileMercator.tileXToLng(10, 8);
      final east = LightPollutionTileMercator.tileXToLng(11, 8);
      expect(east, greaterThan(west));
    });
  });
}

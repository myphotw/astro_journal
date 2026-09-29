import 'dart:io';
import 'dart:typed_data';

import 'package:astro_journal/features/light_pollution_map/overlay/light_pollution_tile_cache.dart';
import 'package:astro_journal/features/light_pollution_map/overlay/light_pollution_tile_constants.dart';
import 'package:astro_journal/features/light_pollution_map/overlay/light_pollution_tile_mercator.dart';
import 'package:astro_journal/features/light_pollution_map/overlay/light_pollution_tile_provider.dart';
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

    test('Windows presentation avoids the previous double attenuation', () {
      final defaultOpacity =
          LightPollutionTileConstants.defaultOverlayOpacity;
      final previousWindowsOpacity = defaultOpacity * defaultOpacity;
      final windowsOpacity =
          defaultOpacity * LightPollutionTileConstants.windowsOverlayOpacity;

      expect(LightPollutionTileConstants.windowsOverlayOpacity, 0.80);
      expect(
        windowsOpacity,
        greaterThan(previousWindowsOpacity),
      );
      expect(defaultOpacity, 0.42);
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

  test('same versioned tile key reuses memory-cached PNG bytes', () {
    final firstKey = LightPollutionTileProvider.cacheKey(901, 412, 11);
    final repeatedKey = LightPollutionTileProvider.cacheKey(901, 412, 11);
    final bytes = Uint8List.fromList([1, 2, 3]);
    final cache = LightPollutionTileCache(maxEntries: 4)..put(firstKey, bytes);

    expect(repeatedKey, firstKey);
    expect(cache.get(repeatedKey), same(bytes));
  });

  test('Windows keeps one tile provider and disables overlay tile fading', () {
    final source = File(
      'lib/features/light_pollution_map/view/windows_light_pollution_map_screen.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    expect(
      source,
      contains('WindowsLightPollutionTileProvider? _windowsTileProvider'),
    );
    expect(source, contains('identical(_tileProviderOwner, viewModel)'));
    expect(source, contains('tileProvider: windowsTileProvider'));
    expect(
      source,
      contains('tileDisplay: const flutter_map.TileDisplay.instantaneous()'),
    );
    expect(source, contains('keepBuffer: 4'));
  });

  test('Windows keeps versioned disk tiles and uses bounded parallel loads', () {
    final source = File(
      'lib/features/light_pollution_map/viewmodel/light_pollution_map_view_model.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    expect(
      source,
      contains('defaultTargetPlatform == TargetPlatform.windows'),
    );
    expect(source, contains('maxConcurrent: isWindows ? 3 : 1'));
    expect(source, contains('if (!isWindows)'));
    expect(source, contains('_tileProvider!.clearCache()'));
  });
}

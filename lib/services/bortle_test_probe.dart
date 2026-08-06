import 'package:flutter/foundation.dart';

import '../data/repositories/bortle_repository.dart';
import 'app_logger.dart';

/// Debug-only probe that logs Bortle brightness lookups without UI changes.
class BortleTestProbe {
  BortleTestProbe._();

  static const _tag = 'BORTLE';

  /// Sample coordinates for smoke testing (README 홍천 + Builder Seoul).
  static const _testLocations = <({String name, double lat, double lng})>[
    (name: 'Hongcheon', lat: 37.6970, lng: 127.8750),
    (name: 'Seoul', lat: 37.5665, lng: 126.9780),
  ];

  static Future<void> run(BortleRepository repository) async {
    if (!kDebugMode) return;

    try {
      final metadata = await repository.getMetadata();
      AppLogger.info(
        _tag,
        'metadata loaded: atlas=${metadata.atlasName} '
        '${metadata.width}x${metadata.height} '
        'origin=(${metadata.originX}, ${metadata.originY})',
      );

      for (final location in _testLocations) {
        final result = await repository.lookup(location.lat, location.lng);
        if (result == null) {
          AppLogger.info(
            _tag,
            '${location.name} lat=${location.lat} lng=${location.lng} '
            '→ out of bounds or no data',
          );
          continue;
        }

        AppLogger.info(
          _tag,
          '${location.name} lat=${result.latitude} lng=${result.longitude} '
          '→ row=${result.row} col=${result.col} brightness=${result.brightness}',
        );
      }
    } catch (error, stack) {
      AppLogger.error(_tag, error, stack);
    }
  }
}

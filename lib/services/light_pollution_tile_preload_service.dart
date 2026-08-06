import 'dart:math' as math;

import '../data/models/bortle_metadata.dart';
import '../data/repositories/shooting_record_repository.dart';
import '../features/light_pollution_map/overlay/light_pollution_tile_disk_cache.dart';
import '../features/light_pollution_map/overlay/light_pollution_tile_generator.dart';
import '../features/light_pollution_map/overlay/light_pollution_tile_mercator.dart';
import '../features/light_pollution_map/overlay/light_pollution_tile_provider.dart';
import 'app_logger.dart';
import 'observation_condition_service.dart';

/// Preloads light-pollution tiles for frequently visited shooting locations.
class LightPollutionTilePreloadService {
  LightPollutionTilePreloadService(
    this._shootingRecordRepository,
    this._observationConditionService, {
    LightPollutionTileDiskCache? diskCache,
  }) : _diskCache = diskCache ?? LightPollutionTileDiskCache();

  static const _tag = 'LP TILE PRELOAD';
  static const _preloadZoomLevels = [10, 11];
  static const _tileRadius = 1;

  final ShootingRecordRepository _shootingRecordRepository;
  final ObservationConditionService _observationConditionService;
  final LightPollutionTileDiskCache _diskCache;

  Future<void> preloadFrequentAreas({
    required BortleMetadata metadata,
    List<({double lat, double lng})>? extraCenters,
    bool includeShootingRecords = true,
    int maxCenters = 8,
  }) async {
    final centers = <String, ({double lat, double lng})>{};

    for (final center in extraCenters ?? const []) {
      centers[_centerKey(center.lat, center.lng)] = center;
    }

    // 광해지도 첫 진입 시에는 촬영기록 전체 스캔을 건너뛰어
    // 메인 스레드/DB 경합으로 인한 UI 멈춤을 줄인다.
    if (includeShootingRecords) {
      final records = await _shootingRecordRepository.getAll();
      for (final record in records) {
        if (centers.length >= maxCenters) break;
        final exif = record.exif;
        if (exif?.lat == null || exif?.lng == null) continue;
        final lat = exif!.lat!;
        final lng = exif.lng!;
        centers[_centerKey(lat, lng)] = (lat: lat, lng: lng);
      }
    }

    if (centers.isEmpty) return;

    for (final center in centers.values) {
      for (final zoom in _preloadZoomLevels) {
        final tileX = _lngToTileX(center.lng, zoom);
        final tileY = _latToTileY(center.lat, zoom);

        for (var dx = -_tileRadius; dx <= _tileRadius; dx++) {
          for (var dy = -_tileRadius; dy <= _tileRadius; dy++) {
            final x = tileX + dx;
            final y = tileY + dy;
            final key = LightPollutionTileProvider.cacheKey(x, y, zoom);
            if (await _diskCache.contains(key)) continue;
            await _generateAndStore(metadata: metadata, x: x, y: y, zoom: zoom, key: key);
          }
        }
      }
    }
  }

  Future<void> _generateAndStore({
    required BortleMetadata metadata,
    required int x,
    required int y,
    required int zoom,
    required String key,
  }) async {
    try {
      final bounds = LightPollutionTileMercator.tileBounds(x, y, zoom);
      if (!LightPollutionTileGenerator.intersectsDataBounds(
        metadata,
        south: bounds.south,
        west: bounds.west,
        north: bounds.north,
        east: bounds.east,
      )) {
        return;
      }

      final cells = await _observationConditionService.getBrightnessInBounds(
        south: bounds.south,
        west: bounds.west,
        north: bounds.north,
        east: bounds.east,
      );

      final png = await LightPollutionTileGenerator.generatePng(
        metadata: metadata,
        cells: cells,
        tileX: x,
        tileY: y,
        zoom: zoom,
      );

      if (png == null) return;
      await _diskCache.put(key, png);
    } catch (error, stack) {
      AppLogger.error(_tag, error, stack);
    }
  }

  static String _centerKey(double lat, double lng) =>
      '${lat.toStringAsFixed(2)}:${lng.toStringAsFixed(2)}';

  static int _lngToTileX(double lng, int zoom) {
    return ((lng + 180) / 360 * math.pow(2, zoom)).floor();
  }

  static int _latToTileY(double lat, int zoom) {
    final latRad = lat * math.pi / 180;
    return ((1 -
                math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) /
            2 *
            math.pow(2, zoom))
        .floor();
  }
}

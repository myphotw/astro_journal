import 'dart:isolate';
import 'dart:typed_data';

import '../../../data/models/brightness_cell.dart';
import '../../../data/models/bortle_metadata.dart';
import 'brightness_color_mapper.dart';
import 'light_pollution_scale.dart';
import 'light_pollution_tile_constants.dart';
import 'light_pollution_tile_mercator.dart';
import 'light_pollution_tile_png.dart';

/// Builds 256×256 PNG tiles from brightness grid cells.
///
/// 각 샘플 지점에서 Mercator lat/lng → **실수 row/col** → atlas 4-이웃
/// bilinear → 샘플 격자. 샘플 사이 픽셀은 화면 공간 bilinear로 채운다.
/// (블록 단색 채우기 없음)
class LightPollutionTileGenerator {
  LightPollutionTileGenerator._();

  static const _tileSize = LightPollutionTileConstants.tileSize;
  static const _brightnessScale = 1000000;

  /// Legend RGB (opaque) — isolate에서 dart:ui 없이 색 매핑.
  static const _legendRgb = <int>[
    0x312E81, // Bortle 1
    0x5B21B6, // 2
    0x1D4ED8, // 3
    0x064E3B, // 4 dark
    0x047857, // 4 mid
    0x10B981, // 4 bright
    0x65A30D, // 5
    0xD97706, // 6
    0xEA580C, // 7
    0xDC2626, // 8
    0x7F1D1D, // 9
  ];

  static bool intersectsDataBounds(
    BortleMetadata metadata, {
    required double south,
    required double west,
    required double north,
    required double east,
  }) {
    return !(east < metadata.west ||
        west > metadata.east ||
        north < metadata.south ||
        south > metadata.north);
  }

  static Future<Uint8List?> generatePng({
    required BortleMetadata metadata,
    required List<BrightnessCell> cells,
    required int tileX,
    required int tileY,
    required int zoom,
  }) async {
    if (cells.isEmpty) return null;

    final bounds = LightPollutionTileMercator.tileBounds(tileX, tileY, zoom);
    if (!intersectsDataBounds(
      metadata,
      south: bounds.south,
      west: bounds.west,
      north: bounds.north,
      east: bounds.east,
    )) {
      return null;
    }

    final stride = LightPollutionTileConstants.samplingStrideForZoom(zoom);
    final opacity = LightPollutionTileConstants.overlayOpacity;
    final alphaByte = (opacity * 255.0).round().clamp(0, 255);

    final packed = Int32List(cells.length * 3);
    for (var i = 0; i < cells.length; i++) {
      final cell = cells[i];
      packed[i * 3] = cell.row;
      packed[i * 3 + 1] = cell.col;
      packed[i * 3 + 2] =
          (cell.brightness * _brightnessScale).round().clamp(0, 1 << 30);
    }

    assert(BrightnessColorMapper.legendEntries.length == _legendRgb.length);

    final args = _TileIsolateArgs(
      packedCells: packed,
      tileX: tileX,
      tileY: tileY,
      zoom: zoom,
      stride: stride,
      alphaByte: alphaByte,
      originX: metadata.originX,
      originY: metadata.originY,
      pixelWidth: metadata.pixelWidth,
      pixelHeight: metadata.pixelHeight,
      gridWidth: metadata.width,
      gridHeight: metadata.height,
      metaWest: metadata.west,
      metaSouth: metadata.south,
      metaEast: metadata.east,
      metaNorth: metadata.north,
    );

    return Isolate.run(() => _renderTileIsolate(args));
  }

  static Uint8List? _renderTileIsolate(_TileIsolateArgs args) {
    final lookup = <int, int>{};
    final packed = args.packedCells;
    for (var i = 0; i < packed.length; i += 3) {
      lookup[packed[i] * 100000 + packed[i + 1]] = packed[i + 2];
    }

    final sampleCoords = _sampleAxisCoords(args.stride);
    final n = sampleCoords.length;
    final sampleBright = Float64List(n * n);
    for (var i = 0; i < sampleBright.length; i++) {
      sampleBright[i] = double.nan;
    }

    var anySample = false;
    for (var iy = 0; iy < n; iy++) {
      final py = sampleCoords[iy];
      final lat = LightPollutionTileMercator.tileYToLat(
        args.tileY,
        args.zoom,
        (py + 0.5) / _tileSize,
      );
      for (var ix = 0; ix < n; ix++) {
        final px = sampleCoords[ix];
        final lng = LightPollutionTileMercator.tileXToLng(
          args.tileX,
          args.zoom,
          (px + 0.5) / _tileSize,
        );

        if (lng < args.metaWest ||
            lng > args.metaEast ||
            lat < args.metaSouth ||
            lat > args.metaNorth) {
          continue;
        }

        final exactCol = (lng - args.originX) / args.pixelWidth;
        final exactRow = (args.originY - lat) / args.pixelHeight;
        final bright = _bilinearAtlasBrightness(
          lookup: lookup,
          exactRow: exactRow,
          exactCol: exactCol,
          gridWidth: args.gridWidth,
          gridHeight: args.gridHeight,
        );
        if (bright == null) continue;
        sampleBright[iy * n + ix] = bright;
        anySample = true;
      }
    }

    if (!anySample) return null;

    final rgba = Uint8List(_tileSize * _tileSize * 4);
    var wrote = false;

    // 샘플 격자 사이 픽셀: 화면 공간 brightness bilinear (단색 블록 없음)
    for (var py = 0; py < _tileSize; py++) {
      final ySpan = _locateSpan(sampleCoords, py);
      final y0 = ySpan.$1;
      final y1 = ySpan.$2;
      final sy0 = sampleCoords[y0].toDouble();
      final sy1 = sampleCoords[y1].toDouble();
      final ty = sy1 == sy0 ? 0.0 : (py - sy0) / (sy1 - sy0);

      for (var px = 0; px < _tileSize; px++) {
        final xSpan = _locateSpan(sampleCoords, px);
        final x0 = xSpan.$1;
        final x1 = xSpan.$2;
        final sx0 = sampleCoords[x0].toDouble();
        final sx1 = sampleCoords[x1].toDouble();
        final tx = sx1 == sx0 ? 0.0 : (px - sx0) / (sx1 - sx0);

        final i00 = y0 * n + x0;
        final i10 = y0 * n + x1;
        final i01 = y1 * n + x0;
        final i11 = y1 * n + x1;

        final v00 = sampleBright[i00];
        final v10 = sampleBright[i10];
        final v01 = sampleBright[i01];
        final v11 = sampleBright[i11];

        final bright = _bilinearSparse(
          !v00.isNaN,
          !v10.isNaN,
          !v01.isNaN,
          !v11.isNaN,
          v00.isNaN ? 0 : v00,
          v10.isNaN ? 0 : v10,
          v01.isNaN ? 0 : v01,
          v11.isNaN ? 0 : v11,
          tx,
          ty,
        );
        if (bright == null) continue;

        final argb = _argbForBrightness(bright, args.alphaByte);
        final idx = (py * _tileSize + px) * 4;
        rgba[idx] = (argb >> 16) & 0xff;
        rgba[idx + 1] = (argb >> 8) & 0xff;
        rgba[idx + 2] = argb & 0xff;
        rgba[idx + 3] = (argb >> 24) & 0xff;
        wrote = true;
      }
    }

    if (!wrote) return null;

    return LightPollutionTilePng.encodeRgba(
      width: _tileSize,
      height: _tileSize,
      rgba: rgba,
    );
  }

  /// stride 간격 샘플 좌표 + 타일 끝(255) 포함.
  static List<int> _sampleAxisCoords(int stride) {
    final coords = <int>[];
    for (var i = 0; i < _tileSize; i += stride) {
      coords.add(i);
    }
    if (coords.last != _tileSize - 1) {
      coords.add(_tileSize - 1);
    }
    return coords;
  }

  static (int, int) _locateSpan(List<int> coords, int pos) {
    if (pos <= coords.first) return (0, 0);
    if (pos >= coords.last) {
      final last = coords.length - 1;
      return (last, last);
    }
    for (var i = 0; i < coords.length - 1; i++) {
      if (pos >= coords[i] && pos <= coords[i + 1]) {
        return (i, i + 1);
      }
    }
    final last = coords.length - 1;
    return (last, last);
  }

  /// 실수 row/col 주변 4셀 brightness bilinear (없으면 null).
  static double? _bilinearAtlasBrightness({
    required Map<int, int> lookup,
    required double exactRow,
    required double exactCol,
    required int gridWidth,
    required int gridHeight,
  }) {
    final r0 = exactRow.floor();
    final c0 = exactCol.floor();
    final r1 = r0 + 1;
    final c1 = c0 + 1;
    final fr = exactRow - r0;
    final fc = exactCol - c0;

    double? cell(int row, int col) {
      if (row < 0 || row >= gridHeight || col < 0 || col >= gridWidth) {
        return null;
      }
      final milli = lookup[row * 100000 + col];
      if (milli == null) return null;
      return milli / _brightnessScale;
    }

    final v00 = cell(r0, c0);
    final v10 = cell(r0, c1);
    final v01 = cell(r1, c0);
    final v11 = cell(r1, c1);

    return _bilinearSparse(
      v00 != null,
      v10 != null,
      v01 != null,
      v11 != null,
      v00 ?? 0,
      v10 ?? 0,
      v01 ?? 0,
      v11 ?? 0,
      fc,
      fr,
    );
  }

  /// 코너가 비면 null. 일부만 있으면 있는 코너만 가중 평균.
  static double? _bilinearSparse(
    bool c00,
    bool c10,
    bool c01,
    bool c11,
    double v00,
    double v10,
    double v01,
    double v11,
    double tx,
    double ty,
  ) {
    var wSum = 0.0;
    var vSum = 0.0;
    void add(bool ok, double v, double w) {
      if (!ok || w <= 0) return;
      wSum += w;
      vSum += v * w;
    }

    add(c00, v00, (1 - tx) * (1 - ty));
    add(c10, v10, tx * (1 - ty));
    add(c01, v01, (1 - tx) * ty);
    add(c11, v11, tx * ty);

    if (wSum <= 0) return null;
    return vSum / wSum;
  }

  static int _argbForBrightness(double artificialMcd, int alphaByte) {
    final bortle = LightPollutionScale.artificialMcdToBortle(artificialMcd);
    late int index;
    if (bortle == 4) {
      final tier = LightPollutionScale.bortle4SubTier(artificialMcd) ??
          Bortle4SubTier.mid;
      switch (tier) {
        case Bortle4SubTier.dark:
          index = 3;
        case Bortle4SubTier.mid:
          index = 4;
        case Bortle4SubTier.bright:
          index = 5;
      }
    } else if (bortle <= 3) {
      index = bortle - 1;
    } else {
      index = bortle + 1;
    }
    final rgb = _legendRgb[index.clamp(0, _legendRgb.length - 1)];
    return (alphaByte << 24) | rgb;
  }
}

class _TileIsolateArgs {
  const _TileIsolateArgs({
    required this.packedCells,
    required this.tileX,
    required this.tileY,
    required this.zoom,
    required this.stride,
    required this.alphaByte,
    required this.originX,
    required this.originY,
    required this.pixelWidth,
    required this.pixelHeight,
    required this.gridWidth,
    required this.gridHeight,
    required this.metaWest,
    required this.metaSouth,
    required this.metaEast,
    required this.metaNorth,
  });

  final Int32List packedCells;
  final int tileX;
  final int tileY;
  final int zoom;
  final int stride;
  final int alphaByte;
  final double originX;
  final double originY;
  final double pixelWidth;
  final double pixelHeight;
  final int gridWidth;
  final int gridHeight;
  final double metaWest;
  final double metaSouth;
  final double metaEast;
  final double metaNorth;
}

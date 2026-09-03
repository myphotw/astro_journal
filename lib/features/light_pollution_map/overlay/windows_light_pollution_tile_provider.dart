import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as flutter_map;

/// Bridges the existing Bortle PNG generator to flutter_map on Windows.
///
/// No remote light-pollution service is introduced here: [loadTileBytes]
/// delegates to the same local DB-backed tile provider used on mobile.
class WindowsLightPollutionTileProvider extends flutter_map.TileProvider {
  WindowsLightPollutionTileProvider({required this.loadTileBytes});

  final Future<Uint8List?> Function(int x, int y, int zoom) loadTileBytes;

  @override
  ImageProvider<Object> getImage(
    flutter_map.TileCoordinates coordinates,
    flutter_map.TileLayer options,
  ) => _WindowsLightPollutionTileImage(
    x: coordinates.x.toInt(),
    y: coordinates.y.toInt(),
    zoom: coordinates.z.toInt(),
    loadTileBytes: loadTileBytes,
  );
}

@immutable
class _WindowsLightPollutionTileImage
    extends ImageProvider<_WindowsLightPollutionTileImage> {
  const _WindowsLightPollutionTileImage({
    required this.x,
    required this.y,
    required this.zoom,
    required this.loadTileBytes,
  });

  final int x;
  final int y;
  final int zoom;
  final Future<Uint8List?> Function(int x, int y, int zoom) loadTileBytes;

  @override
  Future<_WindowsLightPollutionTileImage> obtainKey(
    ImageConfiguration configuration,
  ) => SynchronousFuture<_WindowsLightPollutionTileImage>(this);

  @override
  ImageStreamCompleter loadImage(
    _WindowsLightPollutionTileImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: _loadAsync(key, decode),
    scale: 1,
    debugLabel: 'bortle://${key.zoom}/${key.x}/${key.y}',
  );

  static Future<ui.Codec> _loadAsync(
    _WindowsLightPollutionTileImage key,
    ImageDecoderCallback decode,
  ) async {
    final bytes = await key.loadTileBytes(key.x, key.y, key.zoom);
    if (bytes == null || bytes.isEmpty) {
      throw StateError('No Bortle tile is available at ${key.zoom}/${key.x}/${key.y}.');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }

  @override
  bool operator ==(Object other) =>
      other is _WindowsLightPollutionTileImage &&
      other.x == x &&
      other.y == y &&
      other.zoom == zoom &&
      identical(other.loadTileBytes, loadTileBytes);

  @override
  int get hashCode => Object.hash(x, y, zoom, loadTileBytes);
}

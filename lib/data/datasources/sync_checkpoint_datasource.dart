import 'dart:convert';

import 'gallery_cache_local_datasource.dart';

abstract class SyncCheckpointDataSource {
  Future<String?> readCursor(String streamName);
  Future<void> writeCursor(String streamName, String cursor);
}

class GalleryCacheSyncCheckpointDataSource implements SyncCheckpointDataSource {
  GalleryCacheSyncCheckpointDataSource(this._cache, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final GalleryCacheDataSource _cache;
  final DateTime Function() _now;

  String _key(String streamName) => 'sync:checkpoint:$streamName';

  @override
  Future<String?> readCursor(String streamName) async {
    final entry = await _cache.read(_key(streamName));
    if (entry == null) return null;
    try {
      final decoded = jsonDecode(entry.payloadJson);
      if (decoded is! Map) return null;
      final value = decoded['cursor']?.toString().trim();
      return value == null || value.isEmpty ? null : value;
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> writeCursor(String streamName, String cursor) async {
    await _cache.write(
      GalleryCacheEntry(
        key: _key(streamName),
        payloadJson: jsonEncode({'cursor': cursor}),
        cachedAt: _now().toUtc(),
      ),
    );
  }
}

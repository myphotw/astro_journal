import 'dart:typed_data';

/// LRU memory cache for generated PNG tile bytes.
class LightPollutionTileCache {
  LightPollutionTileCache({this.maxEntries = 1024});

  final int maxEntries;
  final _entries = <String, Uint8List>{};

  Uint8List? get(String key) {
    final value = _entries.remove(key);
    if (value == null) return null;
    _entries[key] = value;
    return value;
  }

  void put(String key, Uint8List value) {
    if (_entries.containsKey(key)) {
      _entries.remove(key);
    } else if (_entries.length >= maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    _entries[key] = value;
  }

  void clear() => _entries.clear();

  int get length => _entries.length;
}

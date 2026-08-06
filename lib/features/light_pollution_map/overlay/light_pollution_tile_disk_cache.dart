import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Disk cache for generated light-pollution PNG tiles (offline map use).
class LightPollutionTileDiskCache {
  LightPollutionTileDiskCache({Directory? rootDirectory}) : _root = rootDirectory;

  final Directory? _root;
  Directory? _cacheRoot;

  Future<Directory> _ensureRoot() async {
    if (_cacheRoot != null) return _cacheRoot!;
    _cacheRoot = _root ?? Directory('${(await getApplicationDocumentsDirectory()).path}/light_pollution_tiles');
    if (!_cacheRoot!.existsSync()) {
      _cacheRoot!.createSync(recursive: true);
    }
    return _cacheRoot!;
  }

  Future<Uint8List?> get(String key) async {
    final file = File('${(await _ensureRoot()).path}/$key.png');
    if (!file.existsSync()) return null;
    return file.readAsBytes();
  }

  Future<void> put(String key, Uint8List value) async {
    final root = await _ensureRoot();
    final file = File('${root.path}/$key.png');
    final parent = file.parent;
    if (!parent.existsSync()) {
      parent.createSync(recursive: true);
    }
    await file.writeAsBytes(value, flush: true);
  }

  Future<bool> contains(String key) async {
    return File('${(await _ensureRoot()).path}/$key.png').existsSync();
  }

  Future<void> clear() async {
    final root = await _ensureRoot();
    if (root.existsSync()) {
      await root.delete(recursive: true);
      root.createSync(recursive: true);
    }
  }
}

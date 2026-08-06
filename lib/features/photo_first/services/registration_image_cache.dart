import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';

/// 등록 세션용 썸네일 캐시.
///
/// 경로당 파일 바이트를 한 번만 읽어 [MemoryImage]로 보관한다.
/// 화면 전환·위저드 단계 변경 시 재로드·재디코드를 막는다.
class RegistrationImageCache {
  RegistrationImageCache._();

  static final Map<String, CachedRegistrationThumb> _cache = {};

  static Future<CachedRegistrationThumb> loadThumbnail(String path) async {
    final existing = _cache[path];
    if (existing != null) return existing;

    final bytes = await File(path).readAsBytes();
    final image = MemoryImage(bytes);
    final entry = CachedRegistrationThumb(bytes: bytes, image: image);
    _cache[path] = entry;
    return entry;
  }

  static void evict(String path) => _cache.remove(path);

  static void clear() => _cache.clear();
}

class CachedRegistrationThumb {
  const CachedRegistrationThumb({
    required this.bytes,
    required this.image,
  });

  final Uint8List bytes;
  final MemoryImage image;
}

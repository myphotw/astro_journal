import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/splash/data/splash_image_catalog.dart';
import '../features/splash/models/splash_image_entry.dart';
import 'app_logger.dart';

/// Splash 브랜드 이미지 다운로드·캐시·랜덤 선택.
///
/// 저장 위치: `{ApplicationSupportDirectory}/splash_images/`
/// Prefs:
/// - `splash_last_image_id`
/// - `splash_catalog_version`
class SplashImageService {
  SplashImageService({
    http.Client? httpClient,
    math.Random? random,
    Future<Directory> Function()? resolveCacheDirectory,
  })  : _http = httpClient ?? http.Client(),
        _random = random ?? math.Random(),
        _resolveCacheDirectory = resolveCacheDirectory;

  static const _tag = 'SplashImage';
  static const _prefsLastId = 'splash_last_image_id';
  static const _prefsCatalogVersion = 'splash_catalog_version';
  static const _dirName = 'splash_images';

  final http.Client _http;
  final math.Random _random;
  final Future<Directory> Function()? _resolveCacheDirectory;

  Directory? _cacheDir;
  Future<void>? _ensureInFlight;
  final Map<String, Future<void>> _downloadInFlight = {};

  /// 표시용 선택 결과.
  ///
  /// 로컬에 없으면 1장만 빠르게 받아 표시를 시도하고,
  /// 나머지는 [ensureCached]가 백그라운드에서 채운다.
  Future<SplashImagePick> pickForDisplay({
    String? preferTag,
  }) async {
    var available = await _localEntries(preferTag: preferTag);
    if (available.isEmpty) {
      await _downloadOneForDisplay(preferTag: preferTag);
      available = await _localEntries(preferTag: preferTag);
    }
    // 나머지 캐시는 백그라운드
    unawaited(ensureCached(preferTag: preferTag));

    if (available.isEmpty) {
      return const SplashImagePick.fallback();
    }

    final prefs = await SharedPreferences.getInstance();
    final lastId = prefs.getString(_prefsLastId);
    final pool = available.where((e) => e.id != lastId).toList();
    final candidates = pool.isEmpty ? available : pool;
    final picked = candidates[_random.nextInt(candidates.length)];
    await prefs.setString(_prefsLastId, picked.id);

    final file = await _fileFor(picked);
    if (!await file.exists()) {
      return const SplashImagePick.fallback();
    }
    return SplashImagePick.local(
      entry: picked,
      file: file,
    );
  }

  Future<void> _downloadOneForDisplay({String? preferTag}) async {
    final dir = await _resolveDir();
    final source = preferTag == null
        ? SplashImageCatalog.entries
        : SplashImageCatalog.byTag(preferTag);
    final ordered = List<SplashImageEntry>.from(source)..shuffle(_random);
    for (final entry in ordered) {
      final file = File(p.join(dir.path, entry.fileName));
      if (await _isUsableFile(file)) {
        return;
      }
      try {
        await _download(entry, file);
        return;
      } catch (error) {
        AppLogger.info(_tag, 'quick download failed ${entry.id}: $error');
      }
    }
  }

  Future<bool> _isUsableFile(File file) async {
    try {
      return await file.exists() && await file.length() > 0;
    } on FileSystemException {
      return false;
    }
  }

  /// 누락분 다운로드. 이미 있으면 스킵.
  Future<void> ensureCached({String? preferTag}) {
    return _ensureInFlight ??= _ensureCachedBody(preferTag: preferTag)
        .whenComplete(() => _ensureInFlight = null);
  }

  Future<void> _ensureCachedBody({String? preferTag}) async {
    final dir = await _resolveDir();
    final prefs = await SharedPreferences.getInstance();
    final storedVersion = prefs.getInt(_prefsCatalogVersion) ?? 0;
    if (storedVersion != SplashImageCatalog.catalogVersion) {
      AppLogger.info(
        _tag,
        'catalog version $storedVersion → ${SplashImageCatalog.catalogVersion}',
      );
      await prefs.setInt(
        _prefsCatalogVersion,
        SplashImageCatalog.catalogVersion,
      );
    }

    final targets = preferTag == null
        ? SplashImageCatalog.entries
        : SplashImageCatalog.byTag(preferTag);
    // 태그 필터 시에도 전체 캐시를 채우는 편이 다음 실행에 유리하다.
    final all = <SplashImageEntry>{
      ...targets,
      ...SplashImageCatalog.entries,
    }.toList(growable: false);

    for (final entry in all) {
      final file = File(p.join(dir.path, entry.fileName));
      if (await _isUsableFile(file)) {
        continue;
      }
      try {
        await _download(entry, file);
      } catch (error) {
        AppLogger.info(_tag, 'download failed ${entry.id}: $error');
      }
    }
  }

  Future<List<SplashImageEntry>> _localEntries({String? preferTag}) async {
    final dir = await _resolveDir();
    final source = preferTag == null
        ? SplashImageCatalog.entries
        : SplashImageCatalog.byTag(preferTag);
    final result = <SplashImageEntry>[];
    for (final entry in source) {
      final file = File(p.join(dir.path, entry.fileName));
      if (await _isUsableFile(file)) {
        result.add(entry);
      }
    }
    // 태그 결과가 비면 전체 로컬로 폴백
    if (result.isEmpty && preferTag != null) {
      return _localEntries();
    }
    return result;
  }

  Future<File> _fileFor(SplashImageEntry entry) async {
    final dir = await _resolveDir();
    return File(p.join(dir.path, entry.fileName));
  }

  Future<Directory> _resolveDir() async {
    final cached = _cacheDir;
    if (cached != null) return cached;
    final Directory dir;
    final custom = _resolveCacheDirectory;
    if (custom != null) {
      dir = await custom();
    } else {
      final root = await getApplicationSupportDirectory();
      dir = Directory(p.join(root.path, _dirName));
    }
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cacheDir = dir;
    return dir;
  }

  Future<void> _download(SplashImageEntry entry, File file) {
    return _downloadInFlight.putIfAbsent(entry.id, () async {
      try {
        if (await _isUsableFile(file)) {
          return;
        }
        AppLogger.info(_tag, 'downloading ${entry.id}');
        final response = await _http
            .get(Uri.parse(entry.remoteUrl))
            .timeout(const Duration(seconds: 25));
        if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
          throw StateError('HTTP ${response.statusCode}');
        }
        final tmp = File('${file.path}.part');
        await tmp.writeAsBytes(response.bodyBytes, flush: true);
        if (await file.exists()) {
          await file.delete();
        }
        await tmp.rename(file.path);
        AppLogger.info(
          _tag,
          'saved ${entry.fileName} (${response.bodyBytes.length})',
        );
      } finally {
        _downloadInFlight.remove(entry.id);
      }
    });
  }

  /// 테스트·관리용: 캐시 디렉터리 경로.
  Future<String> cacheDirectoryPath() async => (await _resolveDir()).path;
}

/// [SplashImageService.pickForDisplay] 결과.
class SplashImagePick {
  const SplashImagePick._({
    required this.isFallback,
    this.entry,
    this.file,
  });

  const SplashImagePick.fallback()
      : this._(isFallback: true);

  const SplashImagePick.local({
    required SplashImageEntry entry,
    required File file,
  }) : this._(isFallback: false, entry: entry, file: file);

  final bool isFallback;
  final SplashImageEntry? entry;
  final File? file;
}

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_logger.dart';

/// Android SAF(Storage Access Framework) 백업 저장/불러오기 브리지.
///
/// 내보내기: Tree URI → DocumentFile.createFile → OutputStream
/// 가져오기: OPEN_DOCUMENT → content URI → 앱 cache 로컬 ZIP 경로
class SafBackupBridge {
  SafBackupBridge._();

  static const _channel = MethodChannel('com.example.astro_journal/saf_backup');

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// ACTION_OPEN_DOCUMENT_TREE + persistable URI permission.
  ///
  /// 반환: `content://...` tree URI. 취소 시 null.
  static Future<String?> pickPersistableDirectory() async {
    if (!isSupported) return null;
    AppLogger.info('SafBackup', 'pickPersistableDirectory start');
    final uri = await _channel.invokeMethod<String>('pickPersistableDirectory');
    AppLogger.info('SafBackup', 'pickPersistableDirectory result=$uri');
    return uri;
  }

  /// ZIP 문서 선택 후 앱 cache로 복사. 반환: 로컬 파일 경로. 취소 시 null.
  static Future<String?> pickZipDocumentToCache() async {
    if (!isSupported) return null;
    AppLogger.info('SafBackup', 'pickZipDocumentToCache start');
    final path = await _channel.invokeMethod<String>('pickZipDocumentToCache');
    AppLogger.info('SafBackup', 'pickZipDocumentToCache result=$path');
    return path;
  }

  /// content URI를 cache ZIP으로 복사. 반환: 로컬 경로.
  static Future<String> copyContentUriToCache(String uri) async {
    AppLogger.info('SafBackup', 'copyContentUriToCache uri=$uri');
    final path = await _channel.invokeMethod<String>(
      'copyContentUriToCache',
      <String, dynamic>{'uri': uri},
    );
    if (path == null || path.isEmpty) {
      throw StateError('content URI 복사 결과가 비어 있습니다.');
    }
    AppLogger.info('SafBackup', 'copyContentUriToCache done=$path');
    return path;
  }

  /// [sourcePath]의 ZIP을 tree URI 폴더에 DocumentFile로 복사.
  ///
  /// 반환: 생성된 문서 content URI.
  static Future<String> copyFileToTreeUri({
    required String sourcePath,
    required String treeUri,
    required String displayName,
  }) async {
    AppLogger.info(
      'SafBackup',
      'copyFileToTreeUri source=$sourcePath tree=$treeUri name=$displayName',
    );
    final out = await _channel.invokeMethod<String>(
      'copyFileToTreeUri',
      <String, dynamic>{
        'sourcePath': sourcePath,
        'treeUri': treeUri,
        'displayName': displayName,
      },
    );
    if (out == null || out.isEmpty) {
      throw StateError('SAF 파일 생성 결과가 비어 있습니다.');
    }
    AppLogger.info('SafBackup', 'copyFileToTreeUri done=$out');
    return out;
  }

  static Future<bool> hasPersistablePermission(String uri) async {
    if (!isSupported) return false;
    final ok = await _channel.invokeMethod<bool>(
      'hasPersistablePermission',
      <String, dynamic>{'uri': uri},
    );
    AppLogger.info('SafBackup', 'hasPersistablePermission uri=$uri ok=$ok');
    return ok ?? false;
  }

  /// content URI를 ACTION_VIEW로 연다.
  static Future<void> openDocumentUri(String uri) async {
    AppLogger.info('SafBackup', 'openDocumentUri uri=$uri');
    await _channel.invokeMethod<void>(
      'openDocumentUri',
      <String, dynamic>{'uri': uri},
    );
  }
}

import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/constants/database_constants.dart';
import '../core/database/sqflite_bootstrap.dart';
import '../data/database/app_database.dart';
import 'app_logger.dart';
import 'saf_backup_bridge.dart';

/// 백업 내보내기 진행 상태.
class BackupExportProgress {
  const BackupExportProgress({
    required this.stage,
    required this.message,
    this.current = 0,
    this.total = 0,
  });

  /// preparing | packing | sharing | done
  final String stage;
  final String message;
  final int current;
  final int total;

  double? get fraction {
    if (total <= 0) return null;
    return (current / total).clamp(0.0, 1.0);
  }
}

/// 폴더/파일 저장 결과.
class BackupSaveResult {
  const BackupSaveResult({
    required this.location,
    required this.isContentUri,
  });

  /// 파일 시스템 경로 또는 `content://` URI.
  final String location;

  /// Android SAF content URI 여부.
  final bool isContentUri;

  bool get canOpenViaSaf => isContentUri && location.startsWith('content:');
}

typedef BackupProgressCallback = void Function(BackupExportProgress progress);

class BackupService {
  void _log(String message) {
    AppLogger.info('BackupService', message);
    debugPrint('[BackupService] $message');
  }
  /// SQLite DB + 사진 폴더를 ZIP으로 묶어 경로를 반환한다.
  ///
  /// 압축은 백그라운드 Isolate에서 수행해 UI가 멈추지 않게 한다.
  Future<String> exportBackup({BackupProgressCallback? onProgress}) async {
    void report(BackupExportProgress progress) => onProgress?.call(progress);

    report(
      const BackupExportProgress(
        stage: 'preparing',
        message: '백업 준비 중…',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    final appDir = await getApplicationDocumentsDirectory();
    final dbPath = await getAppDatabasesPath();
    final dbFile = File(p.join(dbPath, DatabaseConstants.databaseName));
    final photosDir = Directory(p.join(appDir.path, 'photos'));

    final tempDir = await getTemporaryDirectory();
    final zipPath = p.join(
      tempDir.path,
      'astro_journal_backup_${_timestamp()}.zip',
    );

    report(
      const BackupExportProgress(
        stage: 'preparing',
        message: '파일 목록 수집 중…',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    final entries = <_ZipEntryPaths>[];
    if (dbFile.existsSync()) {
      entries.add(
        _ZipEntryPaths(
          sourcePath: dbFile.path,
          archivePath: 'db/${DatabaseConstants.databaseName}',
        ),
      );
    }
    if (photosDir.existsSync()) {
      await for (final entity
          in photosDir.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final relative = p.relative(entity.path, from: appDir.path);
        entries.add(
          _ZipEntryPaths(
            sourcePath: entity.path,
            archivePath: relative.replaceAll('\\', '/'),
          ),
        );
        if (entries.length % 40 == 0) {
          await Future<void>.delayed(Duration.zero);
        }
      }
    }

    final total = entries.length;
    report(
      BackupExportProgress(
        stage: 'preparing',
        message: total == 0 ? '압축할 파일이 없습니다.' : '파일 $total개 압축 준비…',
        current: 0,
        total: total,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    // DB 연결을 닫아 파일을 안전하게 복사한다.
    await AppDatabase.close();

    try {
      if (total == 0) {
        // 빈 ZIP이라도 생성
        final encoder = ZipFileEncoder()..create(zipPath);
        encoder.close();
      } else {
        await _zipEntriesInIsolate(
          zipPath: zipPath,
          entries: entries,
          onProgress: (done) {
            report(
              BackupExportProgress(
                stage: 'packing',
                message: '압축 중… ($done / $total)',
                current: done,
                total: total,
              ),
            );
          },
        );
      }
    } finally {
      await AppDatabase.instance;
    }

    report(
      BackupExportProgress(
        stage: 'done',
        message: '압축 완료',
        current: total,
        total: total,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    return zipPath;
  }

  /// Isolate에서 ZIP을 만들며 진행률을 [onProgress]로 전달한다.
  Future<void> _zipEntriesInIsolate({
    required String zipPath,
    required List<_ZipEntryPaths> entries,
    required void Function(int done) onProgress,
  }) async {
    final receivePort = ReceivePort();
    final errorPort = ReceivePort();
    final exitPort = ReceivePort();

    // Isolate 간 전달은 단순 타입만 사용 (커스텀 클래스 호환 이슈 방지)
    final entryPairs = <List<String>>[
      for (final e in entries) [e.sourcePath, e.archivePath],
    ];

    await Isolate.spawn(
      _backupZipIsolateEntry,
      <dynamic>[receivePort.sendPort, zipPath, entryPairs],
      onError: errorPort.sendPort,
      onExit: exitPort.sendPort,
      errorsAreFatal: true,
    );

    var failed = false;
    Object? isolateError;
    final errorSub = errorPort.listen((err) {
      failed = true;
      isolateError = err;
    });

    try {
      await for (final message in receivePort) {
        if (failed) {
          throw StateError('백업 압축 Isolate 오류: $isolateError');
        }
        if (message is int) {
          onProgress(message);
          await Future<void>.delayed(Duration.zero);
        } else if (message == 'done') {
          break;
        } else if (message is String && message.startsWith('error:')) {
          throw StateError(message.substring(6));
        }
      }
      if (failed) {
        throw StateError('백업 압축 Isolate 오류: $isolateError');
      }
    } finally {
      await errorSub.cancel();
      receivePort.close();
      errorPort.close();
      exitPort.close();
    }
  }

  /// 사용자가 고른 폴더에 ZIP을 저장한다.
  ///
  /// Android: SAF Tree URI + DocumentFile (content://).
  /// Desktop: 일반 파일 경로 복사.
  ///
  /// 취소 시 null.
  Future<BackupSaveResult?> saveBackupToChosenFolder(String zipPath) async {
    final fileName = p.basename(zipPath);
    _log('ZIP 저장 시작 source=$zipPath name=$fileName');

    if (SafBackupBridge.isSupported) {
      return _saveBackupViaSaf(zipPath, fileName);
    }
    return _saveBackupViaFilePath(zipPath, fileName);
  }

  Future<BackupSaveResult?> _saveBackupViaSaf(
    String zipPath,
    String fileName,
  ) async {
    _log('SAF 폴더 선택 시작');
    final treeUri = await SafBackupBridge.pickPersistableDirectory();
    if (treeUri == null || treeUri.isEmpty) {
      _log('SAF 폴더 선택 취소');
      return null;
    }
    _log('선택한 URI=$treeUri');

    final permitted =
        await SafBackupBridge.hasPersistablePermission(treeUri);
    _log('권한 획득 여부 persisted=$permitted');

    _log('ZIP → DocumentFile 복사 시작');
    final docUri = await SafBackupBridge.copyFileToTreeUri(
      sourcePath: zipPath,
      treeUri: treeUri,
      displayName: fileName,
    );
    _log('파일 생성·저장 완료 docUri=$docUri');

    return BackupSaveResult(location: docUri, isContentUri: true);
  }

  Future<BackupSaveResult?> _saveBackupViaFilePath(
    String zipPath,
    String fileName,
  ) async {
    try {
      await FilePicker.platform.clearTemporaryFiles();
    } catch (_) {}

    final directoryPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '백업 ZIP을 저장할 폴더를 선택하세요',
    );
    _log('선택한 경로=$directoryPath');
    if (directoryPath == null || directoryPath.isEmpty) return null;

    // content URI가 섞여 오면 File API 금지 → SAF로 전환
    if (directoryPath.startsWith('content:')) {
      _log('content URI를 File API로 쓰지 않고 SAF로 전환');
      final docUri = await SafBackupBridge.copyFileToTreeUri(
        sourcePath: zipPath,
        treeUri: directoryPath,
        displayName: fileName,
      );
      return BackupSaveResult(location: docUri, isContentUri: true);
    }

    final destPath = p.join(directoryPath, fileName);
    _log('File.copy 시작 dest=$destPath');
    await File(zipPath).copy(destPath);
    _log('File.copy 완료');
    return BackupSaveResult(location: destPath, isContentUri: false);
  }

  /// 폴더 선택이 불가한 환경용 — 시스템 저장 대화상자(파일명·위치).
  Future<BackupSaveResult?> saveBackupWithSaveDialog(String zipPath) async {
    final fileName = p.basename(zipPath);
    final file = File(zipPath);
    if (!file.existsSync()) return null;

    final length = await file.length();
    _log('saveFile dialog size=$length');
    if (length > 64 * 1024 * 1024) {
      _log('파일이 커서 saveFile(bytes) 생략');
      return null;
    }

    final bytes = await file.readAsBytes();
    final savedPath = await FilePicker.platform.saveFile(
      dialogTitle: '백업 파일 저장',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      bytes: bytes,
    );
    _log('saveFile result=$savedPath');
    if (savedPath == null || savedPath.isEmpty) return null;

    final isUri = savedPath.startsWith('content:');
    return BackupSaveResult(location: savedPath, isContentUri: isUri);
  }

  /// content URI 또는 파일 경로를 연다.
  Future<void> openSavedBackup(BackupSaveResult result) async {
    if (result.canOpenViaSaf) {
      await SafBackupBridge.openDocumentUri(result.location);
      return;
    }
    await shareBackupFile(result.location);
  }

  /// [exportBackup]으로 만든 ZIP을 공유 시트로 연다.
  Future<void> shareBackupFile(String zipPath) async {
    await Share.shareXFiles(
      [
        XFile(
          zipPath,
          mimeType: 'application/zip',
          name: p.basename(zipPath),
        ),
      ],
      text: 'Astro Journal 백업',
    );
  }

  /// ZIP 백업 파일을 가져와 기존 DB와 사진을 덮어쓴다.
  ///
  /// [zipFilePath]는 로컬 파일 경로 또는 `content://` URI.
  Future<void> importBackup(
    String zipFilePath, {
    BackupProgressCallback? onProgress,
  }) async {
    void report(BackupExportProgress progress) => onProgress?.call(progress);

    report(
      const BackupExportProgress(
        stage: 'preparing',
        message: '백업 파일 읽는 중…',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    final appDir = await getApplicationDocumentsDirectory();
    final dbPath = await getAppDatabasesPath();

    _log('import start input=$zipFilePath');
    final localZipPath = await _resolveLocalZipPath(zipFilePath);
    _log('import localZip=$localZipPath');

    final zipFile = File(localZipPath);
    if (!zipFile.existsSync()) {
      throw StateError('백업 ZIP을 찾을 수 없습니다: $localZipPath');
    }
    final zipSize = await zipFile.length();
    _log('import zip size=$zipSize');
    if (zipSize <= 0) {
      throw StateError('백업 ZIP이 비어 있습니다.');
    }

    report(
      const BackupExportProgress(
        stage: 'preparing',
        message: '압축 해제 준비 중…',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    // Isolate에서 파일 읽어 디코드 (UI 블로킹 완화)
    final archive = await Isolate.run(() {
      final bytes = File(localZipPath).readAsBytesSync();
      return ZipDecoder().decodeBytes(bytes);
    });
    final files = archive.where((f) => f.isFile).toList();
    final total = files.length;
    _log('import archive files=$total');

    report(
      BackupExportProgress(
        stage: 'preparing',
        message: '복원할 파일 $total개…',
        current: 0,
        total: total,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    await AppDatabase.close();

    var restoredDb = false;
    var restoredPhotos = 0;
    try {
      // 복원 전 기존 WAL/SHM 제거 — 덮어쓴 DB와 충돌 방지
      _deleteSqliteSidecars(dbPath);

      for (var i = 0; i < files.length; i++) {
        final file = files[i];
        final filePath = _normalizeZipEntryName(file.name);
        late String outPath;
        if (filePath.startsWith('db/')) {
          outPath = p.join(dbPath, p.basename(filePath));
          restoredDb = true;
        } else if (filePath.startsWith('photos/')) {
          outPath = p.join(appDir.path, filePath);
          restoredPhotos++;
        } else {
          continue;
        }

        final content = file.content;
        if (content is! List<int>) {
          throw StateError('ZIP 항목 내용을 읽을 수 없습니다: $filePath');
        }

        final outFile = File(outPath);
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(content, flush: true);

        final done = i + 1;
        report(
          BackupExportProgress(
            stage: 'packing',
            message: '복원 중… ($done / $total)',
            current: done,
            total: total,
          ),
        );
        if (done % 5 == 0 || done == total) {
          await Future<void>.delayed(Duration.zero);
        }
      }

      // DB 파일을 썼다면 사이드카를 다시 제거 (부분 생성 방지)
      if (restoredDb) {
        _deleteSqliteSidecars(dbPath);
      }
      _log('import restored db=$restoredDb photos=$restoredPhotos');
    } finally {
      await AppDatabase.instance;
    }

    report(
      BackupExportProgress(
        stage: 'done',
        message: '복원 완료',
        current: total,
        total: total,
      ),
    );
  }

  /// 가져올 ZIP을 선택한다. Android는 SAF, 그 외는 FilePicker.
  ///
  /// 반환: 앱이 읽을 수 있는 로컬 경로. 취소 시 null.
  Future<String?> pickBackupZipForImport() async {
    if (SafBackupBridge.isSupported) {
      _log('import pick via SAF');
      return SafBackupBridge.pickZipDocumentToCache();
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      withData: false,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.single;
    final path = file.path;
    _log('import pick via FilePicker path=$path');
    if (path == null || path.isEmpty) {
      if (file.bytes != null) {
        final tempDir = await getTemporaryDirectory();
        final out = File(
          p.join(tempDir.path, 'import_backup_${_timestamp()}.zip'),
        );
        await out.writeAsBytes(file.bytes!, flush: true);
        return out.path;
      }
      return null;
    }
    return _resolveLocalZipPath(path);
  }

  Future<String> _resolveLocalZipPath(String pathOrUri) async {
    if (pathOrUri.startsWith('content:')) {
      _log('content URI → cache 복사');
      return SafBackupBridge.copyContentUriToCache(pathOrUri);
    }
    final file = File(pathOrUri);
    if (!file.existsSync()) {
      throw StateError('백업 파일을 열 수 없습니다: $pathOrUri');
    }
    return pathOrUri;
  }

  void _deleteSqliteSidecars(String dbDir) {
    final base = p.join(dbDir, DatabaseConstants.databaseName);
    for (final suffix in const ['-wal', '-shm', '-journal']) {
      final side = File('$base$suffix');
      if (side.existsSync()) {
        try {
          side.deleteSync();
          _log('deleted sqlite sidecar ${side.path}');
        } catch (e) {
          _log('sidecar delete failed ${side.path}: $e');
        }
      }
    }
  }

  String _normalizeZipEntryName(String name) {
    var n = name.replaceAll('\\', '/');
    while (n.startsWith('./')) {
      n = n.substring(2);
    }
    if (n.startsWith('/')) n = n.substring(1);
    return n;
  }

  String _timestamp() {
    final now = DateTime.now();
    return '${now.year}${_pad(now.month)}${_pad(now.day)}'
        '_${_pad(now.hour)}${_pad(now.minute)}${_pad(now.second)}';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}

class _ZipEntryPaths {
  const _ZipEntryPaths({
    required this.sourcePath,
    required this.archivePath,
  });

  final String sourcePath;
  final String archivePath;
}

/// Isolate 진입점 — UI 스레드와 분리해 ZIP을 생성한다.
///
/// args: [SendPort replyPort, String zipPath, List<List<String>> entries]
void _backupZipIsolateEntry(List<dynamic> args) {
  final replyPort = args[0] as SendPort;
  final zipPath = args[1] as String;
  final rawEntries = args[2] as List<dynamic>;
  final entryPairs = <List<String>>[
    for (final e in rawEntries) (e as List<dynamic>).cast<String>(),
  ];
  try {
    final encoder = ZipFileEncoder()..create(zipPath);
    final total = entryPairs.length;
    for (var i = 0; i < total; i++) {
      final pair = entryPairs[i];
      final sourcePath = pair[0];
      final archivePath = pair[1];
      final file = File(sourcePath);
      if (file.existsSync()) {
        try {
          encoder.addFile(file, archivePath);
        } catch (_) {
          // 개별 파일 실패는 건너뜀
        }
      }
      final done = i + 1;
      if (done % 3 == 0 || done == total) {
        replyPort.send(done);
      }
    }
    encoder.close();
    replyPort.send('done');
  } catch (e, st) {
    replyPort.send('error:$e\n$st');
  }
}

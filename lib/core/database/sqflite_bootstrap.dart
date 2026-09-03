import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

/// Android 기본 SQLite에는 FTS5가 없는 기기가 있어 번들 sqlite3를 사용한다.
Future<void> initSqflite() async {
  if (kIsWeb) {
    return;
  }

  if (Platform.isAndroid) {
    await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
  }

  if (Platform.isAndroid || Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
}

/// FFI 팩토리의 getDatabasesPath()는 Android에서 유효하지 않은 경로를
/// 반환하므로, 네이티브 sqflite와 동일한 `<dataDir>/databases` 경로를
/// path_provider로 직접 계산한다. (기존 설치 데이터 유지)
Future<String> getAppDatabasesPath() async {
  if (!kIsWeb && Platform.isAndroid) {
    final docsDir = await getApplicationDocumentsDirectory();
    final databasesDir = Directory(p.join(docsDir.parent.path, 'databases'));
    await databasesDir.create(recursive: true);
    return databasesDir.path;
  }
  return getDatabasesPath();
}

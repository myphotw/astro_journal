import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../core/constants/bortle_constants.dart';
import '../core/database/sqflite_bootstrap.dart';
import '../data/models/brightness_cell.dart';
import '../data/models/bortle_metadata.dart';

/// Opens and manages the read-only Bortle light-pollution database.
///
/// Copies [BortleConstants.assetPath] into app storage on first launch.
class BortleDatabaseService {
  BortleDatabaseService._();

  static Database? _database;
  static BortleMetadata? _cachedMetadata;
  static Future<Database>? _opening;

  static Future<void> initialize() async {
    await instance;
  }

  static Future<Database> get instance async {
    if (_database != null) return _database!;
    // 동시 호출 시 33MB 복사가 중복되지 않도록 단일 Future를 공유한다.
    _opening ??= _open().whenComplete(() => _opening = null);
    return _opening!;
  }

  static Future<Database> _open() async {
    final path = await _ensureLocalCopy();
    final db = await openDatabase(path, readOnly: true);
    _database = db;
    return db;
  }

  static Future<String> _ensureLocalCopy() async {
    final dbDir = await getAppDatabasesPath();
    final localPath = join(dbDir, BortleConstants.databaseFileName);
    final file = File(localPath);

    if (await file.exists()) {
      return localPath;
    }

    final byteData = await rootBundle.load(BortleConstants.assetPath);
    final bytes = byteData.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );
    // 대용량 디스크 쓰기는 백그라운드 isolate에서 수행해 UI 프리즈를 방지한다.
    await Isolate.run(() => _writeBytesSync(localPath, bytes));
    return localPath;
  }

  static void _writeBytesSync(String path, Uint8List bytes) {
    File(path).writeAsBytesSync(bytes, flush: true);
  }

  static Future<BortleMetadata> getMetadata() async {
    if (_cachedMetadata != null) {
      return _cachedMetadata!;
    }

    final db = await instance;
    final rows = await db.query(BortleConstants.tableMetadata);
    final map = {
      for (final row in rows)
        row['key']! as String: row['value']! as String,
    };

    _cachedMetadata = BortleMetadata.fromKeyValueRows(map);
    return _cachedMetadata!;
  }

  /// Returns brightness at [latitude]/[longitude], or null if out of bounds.
  static Future<double?> getBrightness(
    double latitude,
    double longitude,
  ) async {
    final metadata = await getMetadata();
    final grid = metadata.latLonToRowCol(latitude, longitude);
    if (!metadata.isInBounds(grid.row, grid.col)) {
      return null;
    }

    final db = await instance;
    final result = await db.query(
      BortleConstants.tableBrightnessMap,
      columns: ['brightness'],
      where: 'row = ? AND col = ?',
      whereArgs: [grid.row, grid.col],
      limit: 1,
    );

    if (result.isEmpty) {
      return null;
    }

    return (result.first['brightness'] as num).toDouble();
  }

  /// Returns brightness pixels within GPS bounds using indexed row/col range query.
  static Future<List<BrightnessCell>> getBrightnessInBounds({
    required double south,
    required double west,
    required double north,
    required double east,
  }) async {
    final metadata = await getMetadata();
    final grid = metadata.gpsBoundsToRowColBounds(
      south: south,
      west: west,
      north: north,
      east: east,
    );
    if (grid == null) return const [];

    final db = await instance;
    final rows = await db.query(
      BortleConstants.tableBrightnessMap,
      columns: ['row', 'col', 'brightness'],
      where: 'row BETWEEN ? AND ? AND col BETWEEN ? AND ?',
      whereArgs: [grid.rowMin, grid.rowMax, grid.colMin, grid.colMax],
    );

    return rows
        .map(
          (row) => BrightnessCell(
            row: row['row']! as int,
            col: row['col']! as int,
            brightness: (row['brightness'] as num).toDouble(),
          ),
        )
        .toList(growable: false);
  }
}

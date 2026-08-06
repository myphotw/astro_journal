import 'package:sqflite/sqflite.dart';

import '../../core/constants/database_constants.dart';
import '../database/app_database.dart';
import '../models/shooting_record.dart';

class ShootingRecordLocalDataSource {
  ShootingRecordLocalDataSource({this._database});

  Database? _database;

  Future<Database> get _db async {
    _database = await AppDatabase.resolve(_database);
    return _database!;
  }

  Future<List<ShootingRecord>> getAll() async {
    final db = await _db;
    final rows = await db.query(
      DatabaseConstants.tableShootingRecords,
      columns: DatabaseConstants.shootingRecordColumns,
      orderBy: '${DatabaseConstants.colCapturedAt} DESC',
    );
    return rows.map(ShootingRecord.fromMap).toList();
  }

  Future<List<ShootingRecord>> getByCelestialObjectId(
    String celestialObjectId,
  ) async {
    final db = await _db;
    final rows = await db.query(
      DatabaseConstants.tableShootingRecords,
      columns: DatabaseConstants.shootingRecordColumns,
      where: '${DatabaseConstants.colCelestialObjectId} = ?',
      whereArgs: [celestialObjectId],
      orderBy: '${DatabaseConstants.colCapturedAt} DESC',
    );
    return rows.map(ShootingRecord.fromMap).toList();
  }

  Future<ShootingRecord?> getById(String id) async {
    final db = await _db;
    final rows = await db.query(
      DatabaseConstants.tableShootingRecords,
      where: '${DatabaseConstants.colId} = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ShootingRecord.fromMap(rows.first);
  }

  Future<ShootingRecord?> findByOriginalFilename(String originalFilename) async {
    final db = await _db;
    final rows = await db.query(
      DatabaseConstants.tableShootingRecords,
      where: '${DatabaseConstants.colOriginalFilename} = ?',
      whereArgs: [originalFilename],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ShootingRecord.fromMap(rows.first);
  }

  Future<ShootingRecord?> findByObjectAndCapturedAt(
    String celestialObjectId,
    DateTime capturedAt, {
    Duration tolerance = const Duration(minutes: 1),
  }) async {
    final db = await _db;
    final from = capturedAt.subtract(tolerance).toIso8601String();
    final to = capturedAt.add(tolerance).toIso8601String();
    final rows = await db.query(
      DatabaseConstants.tableShootingRecords,
      where:
          '${DatabaseConstants.colCelestialObjectId} = ? '
          'AND ${DatabaseConstants.colCapturedAt} >= ? '
          'AND ${DatabaseConstants.colCapturedAt} <= ?',
      whereArgs: [celestialObjectId, from, to],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ShootingRecord.fromMap(rows.first);
  }

  Future<void> insert(ShootingRecord record) async {
    final db = await _db;
    await db.insert(
      DatabaseConstants.tableShootingRecords,
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> update(ShootingRecord record) async {
    final db = await _db;
    await db.update(
      DatabaseConstants.tableShootingRecords,
      record.toMap(),
      where: '${DatabaseConstants.colId} = ?',
      whereArgs: [record.id],
    );
  }

  Future<void> delete(String id) async {
    final db = await _db;
    await db.delete(
      DatabaseConstants.tableShootingRecords,
      where: '${DatabaseConstants.colId} = ?',
      whereArgs: [id],
    );
  }

  Future<void> clearRepresentativeForObject(String celestialObjectId) async {
    final db = await _db;
    await db.update(
      DatabaseConstants.tableShootingRecords,
      {DatabaseConstants.colIsRepresentative: 0},
      where: '${DatabaseConstants.colCelestialObjectId} = ?',
      whereArgs: [celestialObjectId],
    );
  }

  Future<void> setRepresentativeFlag(String recordId, bool value) async {
    final db = await _db;
    await db.update(
      DatabaseConstants.tableShootingRecords,
      {DatabaseConstants.colIsRepresentative: value ? 1 : 0},
      where: '${DatabaseConstants.colId} = ?',
      whereArgs: [recordId],
    );
  }
}

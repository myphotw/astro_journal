import 'package:sqflite/sqflite.dart';

import '../../core/constants/database_constants.dart';
import '../../services/observation_site_validator.dart';
import '../database/app_database.dart';
import '../models/blocked_azimuth_range.dart';
import '../models/horizon_point.dart';
import '../models/observation_site.dart';

class ObservationSiteLocalDataSource {
  ObservationSiteLocalDataSource({this._database});

  Database? _database;

  Future<Database> get _db async {
    _database = await AppDatabase.resolve(_database);
    return _database!;
  }

  Future<List<ObservationSite>> list({bool includeDeleted = false}) async {
    final db = await _db;
    final rows = await db.query(
      DatabaseConstants.tableObservationSites,
      where: includeDeleted ? null : 'deleted_at IS NULL',
      orderBy: 'is_favorite DESC, last_used_at DESC, name COLLATE NOCASE',
    );
    final result = <ObservationSite>[];
    for (final row in rows) {
      result.add(await _hydrate(db, row));
    }
    return result;
  }

  Future<ObservationSite?> get(String id, {bool includeDeleted = false}) async {
    final db = await _db;
    final rows = await db.query(
      DatabaseConstants.tableObservationSites,
      where: includeDeleted ? 'id = ?' : 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _hydrate(db, rows.first);
  }

  Future<void> create(ObservationSite site) async {
    ObservationSiteValidator.validate(site);
    final db = await _db;
    await db.transaction((txn) => _insertAggregate(txn, site));
  }

  Future<void> update(ObservationSite site) async {
    ObservationSiteValidator.validate(site);
    final db = await _db;
    await db.transaction((txn) async {
      final changed = await txn.update(
        DatabaseConstants.tableObservationSites,
        site.toMap(),
        where: 'id = ?',
        whereArgs: [site.id],
      );
      if (changed != 1) {
        throw StateError('수정할 관측지를 찾을 수 없습니다: ${site.id}');
      }
      await _replaceHorizonPoints(txn, site.id, site.horizonPoints);
      await _replaceBlockedRanges(txn, site.id, site.blockedAzimuthRanges);
    });
  }

  Future<void> setFavorite(String id, bool favorite) async {
    final db = await _db;
    await db.update(
      DatabaseConstants.tableObservationSites,
      {
        'is_favorite': favorite ? 1 : 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
    );
  }

  Future<void> markLastUsed(String id, DateTime usedAt) async {
    final db = await _db;
    await db.update(
      DatabaseConstants.tableObservationSites,
      {
        'last_used_at': usedAt.toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
    );
  }

  Future<void> delete(String id, {bool hard = false}) async {
    final db = await _db;
    if (!hard) {
      final now = DateTime.now().toIso8601String();
      await db.update(
        DatabaseConstants.tableObservationSites,
        {'deleted_at': now, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [id],
      );
      return;
    }
    await db.transaction((txn) async {
      await txn.delete(
        DatabaseConstants.tableObservationSiteHorizonPoints,
        where: 'observation_site_id = ?',
        whereArgs: [id],
      );
      await txn.delete(
        DatabaseConstants.tableObservationSiteBlockedAzimuthRanges,
        where: 'observation_site_id = ?',
        whereArgs: [id],
      );
      await txn.delete(
        DatabaseConstants.tableObservationSites,
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<List<HorizonPoint>> listHorizonPoints(String siteId) async {
    final db = await _db;
    return _listHorizonPoints(db, siteId);
  }

  Future<void> addHorizonPoint(HorizonPoint point) async {
    ObservationSiteValidator.validateHorizonPoint(point);
    final db = await _db;
    await db.insert(
      DatabaseConstants.tableObservationSiteHorizonPoints,
      point.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<void> updateHorizonPoint(HorizonPoint point) async {
    ObservationSiteValidator.validateHorizonPoint(point);
    final db = await _db;
    await db.update(
      DatabaseConstants.tableObservationSiteHorizonPoints,
      point.toMap(),
      where: 'id = ?',
      whereArgs: [point.id],
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<void> deleteHorizonPoint(String id) async {
    final db = await _db;
    await db.delete(
      DatabaseConstants.tableObservationSiteHorizonPoints,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> replaceHorizonPoints(
    String siteId,
    List<HorizonPoint> points,
  ) async {
    _validatePoints(siteId, points);
    final db = await _db;
    await db.transaction((txn) => _replaceHorizonPoints(txn, siteId, points));
  }

  Future<List<BlockedAzimuthRange>> listBlockedRanges(String siteId) async {
    final db = await _db;
    return _listBlockedRanges(db, siteId);
  }

  Future<void> addBlockedRange(BlockedAzimuthRange range) async {
    ObservationSiteValidator.validateBlockedRange(range);
    final db = await _db;
    await db.insert(
      DatabaseConstants.tableObservationSiteBlockedAzimuthRanges,
      range.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<void> updateBlockedRange(BlockedAzimuthRange range) async {
    ObservationSiteValidator.validateBlockedRange(range);
    final db = await _db;
    await db.update(
      DatabaseConstants.tableObservationSiteBlockedAzimuthRanges,
      range.toMap(),
      where: 'id = ?',
      whereArgs: [range.id],
    );
  }

  Future<void> deleteBlockedRange(String id) async {
    final db = await _db;
    await db.delete(
      DatabaseConstants.tableObservationSiteBlockedAzimuthRanges,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> replaceBlockedRanges(
    String siteId,
    List<BlockedAzimuthRange> ranges,
  ) async {
    for (final range in ranges) {
      ObservationSiteValidator.validateBlockedRange(
        range,
        expectedSiteId: siteId,
      );
    }
    final db = await _db;
    await db.transaction((txn) => _replaceBlockedRanges(txn, siteId, ranges));
  }

  Future<ObservationSite> _hydrate(
    DatabaseExecutor db,
    Map<String, Object?> row,
  ) async {
    final id = row['id']! as String;
    final points = await _listHorizonPoints(db, id);
    final ranges = await _listBlockedRanges(db, id);
    return ObservationSite.fromMap(
      row,
      horizonPoints: points,
      blockedAzimuthRanges: ranges,
    );
  }

  Future<List<HorizonPoint>> _listHorizonPoints(
    DatabaseExecutor db,
    String siteId,
  ) async {
    final rows = await db.query(
      DatabaseConstants.tableObservationSiteHorizonPoints,
      where: 'observation_site_id = ?',
      whereArgs: [siteId],
      orderBy: 'azimuth ASC, sort_order ASC',
    );
    return rows.map(HorizonPoint.fromMap).toList();
  }

  Future<List<BlockedAzimuthRange>> _listBlockedRanges(
    DatabaseExecutor db,
    String siteId,
  ) async {
    final rows = await db.query(
      DatabaseConstants.tableObservationSiteBlockedAzimuthRanges,
      where: 'observation_site_id = ?',
      whereArgs: [siteId],
      orderBy: 'start_azimuth ASC',
    );
    return rows.map(BlockedAzimuthRange.fromMap).toList();
  }

  Future<void> _insertAggregate(
    DatabaseExecutor db,
    ObservationSite site,
  ) async {
    await db.insert(
      DatabaseConstants.tableObservationSites,
      site.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    for (final point in site.horizonPoints) {
      await db.insert(
        DatabaseConstants.tableObservationSiteHorizonPoints,
        point.toMap(),
      );
    }
    for (final range in site.blockedAzimuthRanges) {
      await db.insert(
        DatabaseConstants.tableObservationSiteBlockedAzimuthRanges,
        range.toMap(),
      );
    }
  }

  Future<void> _replaceHorizonPoints(
    DatabaseExecutor db,
    String siteId,
    List<HorizonPoint> points,
  ) async {
    _validatePoints(siteId, points);
    await db.delete(
      DatabaseConstants.tableObservationSiteHorizonPoints,
      where: 'observation_site_id = ?',
      whereArgs: [siteId],
    );
    for (final point in points) {
      await db.insert(
        DatabaseConstants.tableObservationSiteHorizonPoints,
        point.toMap(),
      );
    }
  }

  void _validatePoints(String siteId, List<HorizonPoint> points) {
    final azimuths = <double>{};
    for (final point in points) {
      ObservationSiteValidator.validateHorizonPoint(
        point,
        expectedSiteId: siteId,
      );
      if (!azimuths.add(point.azimuth)) {
        throw ArgumentError('같은 방위각의 Horizon 지점을 중복 저장할 수 없습니다.');
      }
    }
  }

  Future<void> _replaceBlockedRanges(
    DatabaseExecutor db,
    String siteId,
    List<BlockedAzimuthRange> ranges,
  ) async {
    await db.delete(
      DatabaseConstants.tableObservationSiteBlockedAzimuthRanges,
      where: 'observation_site_id = ?',
      whereArgs: [siteId],
    );
    for (final range in ranges) {
      ObservationSiteValidator.validateBlockedRange(
        range,
        expectedSiteId: siteId,
      );
      await db.insert(
        DatabaseConstants.tableObservationSiteBlockedAzimuthRanges,
        range.toMap(),
      );
    }
  }
}

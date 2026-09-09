import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/database_constants.dart';
import '../../services/observation_site_validator.dart';
import '../database/app_database.dart';
import '../models/blocked_azimuth_range.dart';
import '../models/horizon_point.dart';
import '../models/observation_site.dart';
import '../models/observation_site_remote.dart';
import '../models/observation_site_sync_item.dart';

class ObservationSiteLocalDataSource {
  ObservationSiteLocalDataSource({
    Database? database,
    this.syncMutationsEnabled = false,
  }) : _database = database;

  Database? _database;
  final bool syncMutationsEnabled;

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
    await db.transaction((txn) async {
      await _insertAggregate(txn, site);
      if (syncMutationsEnabled) {
        await _enqueueSnapshot(txn, site, ObservationSiteSyncOperation.create);
      }
    });
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
      if (syncMutationsEnabled) {
        await _enqueueSnapshot(txn, site, ObservationSiteSyncOperation.update);
      }
    });
  }

  Future<void> setFavorite(String id, bool favorite) async {
    final db = await _db;
    await db.transaction((txn) async {
      final changed = await txn.update(
        DatabaseConstants.tableObservationSites,
        {
          'is_favorite': favorite ? 1 : 0,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [id],
      );
      if (changed == 1 && syncMutationsEnabled) {
        await _enqueueSnapshot(
          txn,
          await _getRequired(txn, id),
          ObservationSiteSyncOperation.update,
        );
      }
    });
  }

  Future<void> markLastUsed(String id, DateTime usedAt) async {
    final db = await _db;
    await db.update(
      DatabaseConstants.tableObservationSites,
      {'last_used_at': usedAt.toIso8601String()},
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
    );
  }

  Future<void> delete(String id, {bool hard = false}) async {
    final db = await _db;
    if (!hard) {
      final now = DateTime.now().toIso8601String();
      await db.transaction((txn) async {
        final current = await _getRequired(txn, id);
        await txn.update(
          DatabaseConstants.tableObservationSites,
          {'deleted_at': now, 'updated_at': now},
          where: 'id = ?',
          whereArgs: [id],
        );
        if (syncMutationsEnabled) {
          await _enqueueSnapshot(
            txn,
            current.copyWith(
              updatedAt: DateTime.parse(now),
              deletedAt: DateTime.parse(now),
            ),
            ObservationSiteSyncOperation.delete,
          );
        }
      });
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
    await db.transaction((txn) async {
      await txn.insert(
        DatabaseConstants.tableObservationSiteHorizonPoints,
        point.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      await _touchAndEnqueue(txn, point.observationSiteId);
    });
  }

  Future<void> updateHorizonPoint(HorizonPoint point) async {
    ObservationSiteValidator.validateHorizonPoint(point);
    final db = await _db;
    await db.transaction((txn) async {
      await txn.update(
        DatabaseConstants.tableObservationSiteHorizonPoints,
        point.toMap(),
        where: 'id = ?',
        whereArgs: [point.id],
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      await _touchAndEnqueue(txn, point.observationSiteId);
    });
  }

  Future<void> deleteHorizonPoint(String id) async {
    final db = await _db;
    await db.transaction((txn) async {
      final rows = await txn.query(
        DatabaseConstants.tableObservationSiteHorizonPoints,
        columns: const ['observation_site_id'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      await txn.delete(
        DatabaseConstants.tableObservationSiteHorizonPoints,
        where: 'id = ?',
        whereArgs: [id],
      );
      if (rows.isNotEmpty) {
        await _touchAndEnqueue(
          txn,
          rows.single['observation_site_id']! as String,
        );
      }
    });
  }

  Future<void> replaceHorizonPoints(
    String siteId,
    List<HorizonPoint> points,
  ) async {
    _validatePoints(siteId, points);
    final db = await _db;
    await db.transaction((txn) async {
      await _replaceHorizonPoints(txn, siteId, points);
      await _touchAndEnqueue(txn, siteId);
    });
  }

  Future<List<BlockedAzimuthRange>> listBlockedRanges(String siteId) async {
    final db = await _db;
    return _listBlockedRanges(db, siteId);
  }

  Future<void> addBlockedRange(BlockedAzimuthRange range) async {
    ObservationSiteValidator.validateBlockedRange(range);
    final db = await _db;
    await db.transaction((txn) async {
      await txn.insert(
        DatabaseConstants.tableObservationSiteBlockedAzimuthRanges,
        range.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      await _touchAndEnqueue(txn, range.observationSiteId);
    });
  }

  Future<void> updateBlockedRange(BlockedAzimuthRange range) async {
    ObservationSiteValidator.validateBlockedRange(range);
    final db = await _db;
    await db.transaction((txn) async {
      await txn.update(
        DatabaseConstants.tableObservationSiteBlockedAzimuthRanges,
        range.toMap(),
        where: 'id = ?',
        whereArgs: [range.id],
      );
      await _touchAndEnqueue(txn, range.observationSiteId);
    });
  }

  Future<void> deleteBlockedRange(String id) async {
    final db = await _db;
    await db.transaction((txn) async {
      final rows = await txn.query(
        DatabaseConstants.tableObservationSiteBlockedAzimuthRanges,
        columns: const ['observation_site_id'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      await txn.delete(
        DatabaseConstants.tableObservationSiteBlockedAzimuthRanges,
        where: 'id = ?',
        whereArgs: [id],
      );
      if (rows.isNotEmpty) {
        await _touchAndEnqueue(
          txn,
          rows.single['observation_site_id']! as String,
        );
      }
    });
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
    await db.transaction((txn) async {
      await _replaceBlockedRanges(txn, siteId, ranges);
      await _touchAndEnqueue(txn, siteId);
    });
  }

  Future<ObservationSiteSyncMetadata?> getSyncMetadata(String siteId) async {
    final db = await _db;
    final rows = await db.query(
      DatabaseConstants.tableObservationSiteSyncState,
      where: 'site_id = ?',
      whereArgs: [siteId],
      limit: 1,
    );
    return rows.isEmpty
        ? null
        : ObservationSiteSyncMetadata.fromMap(rows.single);
  }

  Future<bool> hasPendingSync(String siteId) async {
    final db = await _db;
    final count = Sqflite.firstIntValue(
      await db.rawQuery(
        '''
        SELECT COUNT(*)
        FROM ${DatabaseConstants.tableObservationSiteSyncOutbox}
        WHERE site_id = ? AND state IN ('QUEUED','PROCESSING','FAILED','CONFLICT')
        ''',
        [siteId],
      ),
    );
    return (count ?? 0) > 0;
  }

  Future<List<ObservationSiteSyncItem>> listPendingSync() async {
    final db = await _db;
    final now = DateTime.now().toUtc().toIso8601String();
    final rows = await db.query(
      DatabaseConstants.tableObservationSiteSyncOutbox,
      where:
          "state IN ('QUEUED','PROCESSING') OR (state='FAILED' AND retry_count <= 3 AND (next_retry_at IS NULL OR next_retry_at <= ?))",
      whereArgs: [now],
      orderBy: 'created_at ASC, id ASC',
    );
    return rows.map(ObservationSiteSyncItem.fromMap).toList(growable: false);
  }

  Future<void> ensureBootstrapQueued(ObservationSite site) async {
    final db = await _db;
    await db.transaction((txn) async {
      final metadata = await _metadata(txn, site.id);
      if (metadata?.serverRevision != null) return;
      final count = Sqflite.firstIntValue(
        await txn.rawQuery(
          '''
          SELECT COUNT(*)
          FROM ${DatabaseConstants.tableObservationSiteSyncOutbox}
          WHERE site_id = ? AND operation_type = 'CREATE'
            AND state IN ('QUEUED','PROCESSING','FAILED','CONFLICT')
          ''',
          [site.id],
        ),
      );
      if ((count ?? 0) == 0) {
        await _enqueueSnapshot(txn, site, ObservationSiteSyncOperation.create);
      }
    });
  }

  Future<void> enqueueCurrentUpdate(ObservationSite site) async {
    final db = await _db;
    await db.transaction(
      (txn) => _enqueueSnapshot(txn, site, ObservationSiteSyncOperation.update),
    );
  }

  Future<bool> applyRemoteAggregate(
    ObservationSiteRemoteAggregate aggregate, {
    bool force = false,
    bool preserveLocalDefaultEquipment = true,
  }) async {
    final db = await _db;
    return db.transaction((txn) async {
      final rows = await txn.query(
        DatabaseConstants.tableObservationSites,
        where: 'id = ?',
        whereArgs: [aggregate.site.id],
        limit: 1,
      );
      final current = rows.isEmpty ? null : await _hydrate(txn, rows.single);
      final metadata = await _metadata(txn, aggregate.site.id);
      if (!force &&
          metadata?.serverRevision != null &&
          metadata!.serverRevision! >= aggregate.revision) {
        return false;
      }
      final canonical = aggregate.site.copyWith(
        lastUsedAt: current?.lastUsedAt,
        defaultEquipmentId:
            aggregate.site.defaultEquipmentId ??
            (preserveLocalDefaultEquipment
                ? current?.defaultEquipmentId
                : null),
        clearDefaultEquipment:
            aggregate.site.defaultEquipmentId == null &&
            (!preserveLocalDefaultEquipment ||
                current?.defaultEquipmentId == null),
      );
      final changed =
          current == null || !_sameVisibleAggregate(current, canonical);
      await _upsertAggregate(txn, canonical);
      await _writeMetadata(txn, aggregate);
      return changed;
    });
  }

  Future<bool> applyRemoteDelete({
    required String siteId,
    required int revision,
    required DateTime deletedAt,
    bool force = false,
  }) async {
    final db = await _db;
    return db.transaction((txn) async {
      final metadata = await _metadata(txn, siteId);
      if (metadata?.serverRevision case final current?
          when current >= revision && metadata?.serverDeletedAt != null) {
        return false;
      }
      if (!force && await _hasPendingSync(txn, siteId)) {
        await _writeDeleteMetadata(
          txn,
          siteId: siteId,
          revision: revision,
          deletedAt: deletedAt,
        );
        await txn.update(
          DatabaseConstants.tableObservationSiteSyncOutbox,
          {
            'state': 'CONFLICT',
            'last_error': 'Remote ObservationSite was deleted.',
            'next_retry_at': null,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          where: "site_id = ? AND state IN ('QUEUED','PROCESSING','FAILED')",
          whereArgs: [siteId],
        );
        return false;
      }
      final changed = await txn.update(
        DatabaseConstants.tableObservationSites,
        {
          'deleted_at': deletedAt.toUtc().toIso8601String(),
          'updated_at': deletedAt.toUtc().toIso8601String(),
        },
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [siteId],
      );
      await txn.delete(
        DatabaseConstants.tableObservationSiteHorizonPoints,
        where: 'observation_site_id = ?',
        whereArgs: [siteId],
      );
      await txn.delete(
        DatabaseConstants.tableObservationSiteBlockedAzimuthRanges,
        where: 'observation_site_id = ?',
        whereArgs: [siteId],
      );
      await _writeDeleteMetadata(
        txn,
        siteId: siteId,
        revision: revision,
        deletedAt: deletedAt,
      );
      return changed == 1;
    });
  }

  Future<bool> applyRemoteMissing(String siteId) async {
    final db = await _db;
    return db.transaction((txn) async {
      final metadata = await _metadata(txn, siteId);
      if (metadata?.serverRevision == null) return false;
      final now = DateTime.now().toUtc().toIso8601String();
      final changed = await txn.update(
        DatabaseConstants.tableObservationSites,
        {'deleted_at': now, 'updated_at': now},
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [siteId],
      );
      await txn.update(
        DatabaseConstants.tableObservationSiteSyncState,
        {'server_deleted_at': now, 'last_synced_at': now},
        where: 'site_id = ?',
        whereArgs: [siteId],
      );
      return changed == 1;
    });
  }

  Future<void> saveRemoteSnapshotOnly(
    ObservationSiteRemoteAggregate aggregate,
  ) async {
    final db = await _db;
    await db.transaction((txn) => _writeMetadata(txn, aggregate));
  }

  Future<void> markSyncProcessing(String operationId) async {
    final db = await _db;
    await db.update(
      DatabaseConstants.tableObservationSiteSyncOutbox,
      {
        'state': 'PROCESSING',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'operation_id = ?',
      whereArgs: [operationId],
    );
  }

  Future<void> markSyncSucceeded(String operationId) async {
    final db = await _db;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      final rows = await txn.query(
        DatabaseConstants.tableObservationSiteSyncOutbox,
        columns: const ['site_id'],
        where: 'operation_id = ?',
        whereArgs: [operationId],
        limit: 1,
      );
      await txn.update(
        DatabaseConstants.tableObservationSiteSyncOutbox,
        {
          'state': 'SYNCED',
          'last_error': null,
          'next_retry_at': null,
          'completed_at': now,
          'updated_at': now,
        },
        where: 'operation_id = ?',
        whereArgs: [operationId],
      );
      if (rows.isNotEmpty) {
        await txn.update(
          DatabaseConstants.tableObservationSiteSyncOutbox,
          {'state': 'CANCELLED', 'updated_at': now},
          where: "site_id = ? AND state = 'CONFLICT'",
          whereArgs: [rows.single['site_id']],
        );
      }
    });
  }

  Future<void> rebaseQueuedSync(String siteId, int revision) async {
    final db = await _db;
    await db.update(
      DatabaseConstants.tableObservationSiteSyncOutbox,
      {
        'base_revision': revision,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where:
          "site_id = ? AND operation_type IN ('UPDATE','DELETE') AND state = 'QUEUED'",
      whereArgs: [siteId],
    );
  }

  Future<void> markSyncFailed(
    ObservationSiteSyncItem item,
    String error,
  ) async {
    final retryCount = item.retryCount + 1;
    final delay = switch (retryCount) {
      1 => const Duration(seconds: 5),
      2 => const Duration(seconds: 15),
      _ => const Duration(seconds: 60),
    };
    final now = DateTime.now().toUtc();
    final db = await _db;
    await db.update(
      DatabaseConstants.tableObservationSiteSyncOutbox,
      {
        'state': 'FAILED',
        'retry_count': retryCount,
        'next_retry_at': retryCount > 3
            ? null
            : now.add(delay).toIso8601String(),
        'last_error': error,
        'updated_at': now.toIso8601String(),
      },
      where: 'operation_id = ?',
      whereArgs: [item.operationId],
    );
  }

  Future<void> markSyncConflict(
    ObservationSiteSyncItem item,
    String error, {
    ObservationSiteRemoteAggregate? serverAggregate,
  }) async {
    final db = await _db;
    await db.transaction((txn) async {
      if (serverAggregate != null) {
        await _writeMetadata(txn, serverAggregate);
      }
      await txn.update(
        DatabaseConstants.tableObservationSiteSyncOutbox,
        {
          'state': 'CONFLICT',
          'last_error': error,
          'server_payload_json': serverAggregate == null
              ? null
              : jsonEncode(serverAggregate.toJson()),
          'next_retry_at': null,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'operation_id = ?',
        whereArgs: [item.operationId],
      );
    });
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

  Future<void> _touchAndEnqueue(DatabaseExecutor db, String siteId) async {
    if (!syncMutationsEnabled) return;
    await db.update(
      DatabaseConstants.tableObservationSites,
      {'updated_at': DateTime.now().toUtc().toIso8601String()},
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [siteId],
    );
    await _enqueueSnapshot(
      db,
      await _getRequired(db, siteId),
      ObservationSiteSyncOperation.update,
    );
  }

  Future<ObservationSite> _getRequired(
    DatabaseExecutor db,
    String siteId,
  ) async {
    final rows = await db.query(
      DatabaseConstants.tableObservationSites,
      where: 'id = ?',
      whereArgs: [siteId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('관측지를 찾을 수 없습니다: $siteId');
    }
    return _hydrate(db, rows.single);
  }

  Future<ObservationSiteSyncMetadata?> _metadata(
    DatabaseExecutor db,
    String siteId,
  ) async {
    final rows = await db.query(
      DatabaseConstants.tableObservationSiteSyncState,
      where: 'site_id = ?',
      whereArgs: [siteId],
      limit: 1,
    );
    return rows.isEmpty
        ? null
        : ObservationSiteSyncMetadata.fromMap(rows.single);
  }

  Future<bool> _hasPendingSync(DatabaseExecutor db, String siteId) async {
    final count = Sqflite.firstIntValue(
      await db.rawQuery(
        '''
        SELECT COUNT(*)
        FROM ${DatabaseConstants.tableObservationSiteSyncOutbox}
        WHERE site_id = ? AND state IN ('QUEUED','PROCESSING','FAILED','CONFLICT')
        ''',
        [siteId],
      ),
    );
    return (count ?? 0) > 0;
  }

  Future<void> _writeDeleteMetadata(
    DatabaseExecutor db, {
    required String siteId,
    required int revision,
    required DateTime deletedAt,
  }) async {
    final timestamp = deletedAt.toUtc().toIso8601String();
    await db.insert(
      DatabaseConstants.tableObservationSiteSyncState,
      {
        'site_id': siteId,
        'server_revision': revision,
        'server_updated_at': timestamp,
        'server_deleted_at': timestamp,
        'last_synced_at': DateTime.now().toUtc().toIso8601String(),
        'server_payload_json': null,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _writeMetadata(
    DatabaseExecutor db,
    ObservationSiteRemoteAggregate aggregate,
  ) async {
    await db.insert(
      DatabaseConstants.tableObservationSiteSyncState,
      {
        'site_id': aggregate.site.id,
        'server_revision': aggregate.revision,
        'server_updated_at': aggregate.site.updatedAt.toUtc().toIso8601String(),
        'server_deleted_at': aggregate.site.deletedAt
            ?.toUtc()
            .toIso8601String(),
        'last_synced_at': DateTime.now().toUtc().toIso8601String(),
        'server_payload_json': jsonEncode(aggregate.toJson()),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _upsertAggregate(
    DatabaseExecutor db,
    ObservationSite site,
  ) async {
    ObservationSiteValidator.validate(site);
    final changed = await db.update(
      DatabaseConstants.tableObservationSites,
      site.toMap(),
      where: 'id = ?',
      whereArgs: [site.id],
    );
    if (changed == 0) {
      await db.insert(DatabaseConstants.tableObservationSites, site.toMap());
    }
    await _replaceHorizonPoints(db, site.id, site.horizonPoints);
    await _replaceBlockedRanges(db, site.id, site.blockedAzimuthRanges);
  }

  Future<void> _enqueueSnapshot(
    DatabaseExecutor db,
    ObservationSite site,
    ObservationSiteSyncOperation requestedOperation,
  ) async {
    final metadata = await _metadata(db, site.id);
    var effectiveOperation = requestedOperation;
    final payload = jsonEncode(
      ObservationSiteRemoteAggregate(
        site: site,
        revision: metadata?.serverRevision ?? 0,
      ).toJson(),
    );
    final now = DateTime.now().toUtc().toIso8601String();

    if (requestedOperation == ObservationSiteSyncOperation.update &&
        metadata?.serverRevision == null) {
      final existing = await _pendingOperation(
        db,
        site.id,
        ObservationSiteSyncOperation.create,
        states: const ['QUEUED', 'FAILED'],
      );
      if (existing != null) {
        await db.update(
          DatabaseConstants.tableObservationSiteSyncOutbox,
          {
            'payload_json': payload,
            'state': 'QUEUED',
            'retry_count': 0,
            'next_retry_at': null,
            'last_error': null,
            'updated_at': now,
          },
          where: 'operation_id = ?',
          whereArgs: [existing],
        );
        return;
      }
      final processingCreate = await _pendingOperation(
        db,
        site.id,
        ObservationSiteSyncOperation.create,
        states: const ['PROCESSING'],
      );
      effectiveOperation = processingCreate == null
          ? ObservationSiteSyncOperation.create
          : ObservationSiteSyncOperation.update;
    }

    if (effectiveOperation == ObservationSiteSyncOperation.create) {
      final existing = await _pendingOperation(
        db,
        site.id,
        ObservationSiteSyncOperation.create,
        states: const ['QUEUED', 'FAILED'],
      );
      if (existing != null) {
        await db.update(
          DatabaseConstants.tableObservationSiteSyncOutbox,
          {
            'payload_json': payload,
            'state': 'QUEUED',
            'retry_count': 0,
            'next_retry_at': null,
            'last_error': null,
            'updated_at': now,
          },
          where: 'operation_id = ?',
          whereArgs: [existing],
        );
        return;
      }
    }

    if (effectiveOperation == ObservationSiteSyncOperation.update) {
      final pendingCreate = await _pendingOperation(
        db,
        site.id,
        ObservationSiteSyncOperation.create,
        states: const ['QUEUED', 'FAILED'],
      );
      if (pendingCreate != null) {
        await db.update(
          DatabaseConstants.tableObservationSiteSyncOutbox,
          {
            'payload_json': payload,
            'state': 'QUEUED',
            'retry_count': 0,
            'next_retry_at': null,
            'last_error': null,
            'updated_at': now,
          },
          where: 'operation_id = ?',
          whereArgs: [pendingCreate],
        );
        return;
      }
      final pendingUpdate = await _pendingOperation(
        db,
        site.id,
        ObservationSiteSyncOperation.update,
        states: const ['QUEUED', 'FAILED'],
      );
      if (pendingUpdate != null) {
        await db.update(
          DatabaseConstants.tableObservationSiteSyncOutbox,
          {
            'payload_json': payload,
            'state': 'QUEUED',
            'retry_count': 0,
            'next_retry_at': null,
            'last_error': null,
            'updated_at': now,
          },
          where: 'operation_id = ?',
          whereArgs: [pendingUpdate],
        );
        return;
      }
    }

    if (effectiveOperation == ObservationSiteSyncOperation.delete) {
      if (metadata?.serverRevision == null) {
        final queuedCreate = await _pendingOperation(
          db,
          site.id,
          ObservationSiteSyncOperation.create,
          states: const ['QUEUED', 'FAILED'],
        );
        if (queuedCreate != null) {
          await db.update(
            DatabaseConstants.tableObservationSiteSyncOutbox,
            {'state': 'CANCELLED', 'updated_at': now},
            where: 'operation_id = ?',
            whereArgs: [queuedCreate],
          );
          return;
        }
      }
      final pendingDelete = await _pendingOperation(
        db,
        site.id,
        ObservationSiteSyncOperation.delete,
        states: const ['QUEUED', 'FAILED'],
      );
      if (pendingDelete != null) return;
      await db.update(
        DatabaseConstants.tableObservationSiteSyncOutbox,
        {'state': 'CANCELLED', 'updated_at': now},
        where:
            "site_id = ? AND operation_type = 'UPDATE' AND state IN ('QUEUED','FAILED')",
        whereArgs: [site.id],
      );
    }

    await db.insert(DatabaseConstants.tableObservationSiteSyncOutbox, {
      'operation_id': const Uuid().v4(),
      'site_id': site.id,
      'operation_type': effectiveOperation.databaseValue,
      'base_revision': metadata?.serverRevision,
      'state': 'QUEUED',
      'retry_count': 0,
      'next_retry_at': null,
      'last_error': null,
      'payload_json': payload,
      'server_payload_json': null,
      'created_at': now,
      'updated_at': now,
      'completed_at': null,
    });
  }

  Future<String?> _pendingOperation(
    DatabaseExecutor db,
    String siteId,
    ObservationSiteSyncOperation operation, {
    required List<String> states,
  }) async {
    final placeholders = List.filled(states.length, '?').join(',');
    final rows = await db.query(
      DatabaseConstants.tableObservationSiteSyncOutbox,
      columns: const ['operation_id'],
      where: 'site_id = ? AND operation_type = ? AND state IN ($placeholders)',
      whereArgs: [siteId, operation.databaseValue, ...states],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['operation_id'] as String;
  }

  bool _sameVisibleAggregate(ObservationSite left, ObservationSite right) {
    Map<String, Object?> normalized(ObservationSite site) {
      final parent = Map<String, Object?>.from(site.toMap())
        ..remove('last_used_at')
        ..remove('created_at')
        ..remove('updated_at');
      return {
        'parent': parent,
        'horizon': site.horizonPoints.map((item) => item.toMap()).toList(),
        'blocked': site.blockedAzimuthRanges
            .map((item) => item.toMap())
            .toList(),
      };
    }

    return jsonEncode(normalized(left)) == jsonEncode(normalized(right));
  }
}

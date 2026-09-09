import 'dart:convert';

import 'package:sqflite/sqflite.dart'
    show ConflictAlgorithm, Database, DatabaseExecutor, Sqflite;
import 'package:uuid/uuid.dart';

import '../../core/constants/database_constants.dart';
import '../database/app_database.dart';
import '../models/equipment.dart';
import '../models/equipment_remote.dart';
import '../models/equipment_sync_item.dart';
import '../models/eyepiece.dart';

class EquipmentLocalDataSource {
  EquipmentLocalDataSource({
    Database? database,
    this.syncMutationsEnabled = false,
  }) : _database = database;

  Database? _database;
  final bool syncMutationsEnabled;

  Future<Database> get _db async {
    _database = await AppDatabase.resolve(_database);
    return _database!;
  }

  Future<List<Equipment>> getAll({bool activeOnly = false}) async {
    final db = await _db;
    final rows = await db.query(
      DatabaseConstants.tableEquipment,
      where: activeOnly ? '${DatabaseConstants.colIsActive} = 1' : null,
      orderBy:
          '${DatabaseConstants.colSortOrder}, ${DatabaseConstants.colName}',
    );
    if (rows.isEmpty) return [];

    final equipmentIds = rows
        .map((row) => row[DatabaseConstants.colId] as String)
        .toList();
    final eyepiecesByEquipment = await _getEyepiecesGroupedByEquipment(
      db,
      equipmentIds,
    );

    return rows
        .map(
          (row) => Equipment.fromMap(
            row,
            eyepieces:
                eyepiecesByEquipment[row[DatabaseConstants.colId] as String] ??
                const [],
          ),
        )
        .toList();
  }

  Future<Equipment?> getById(String id) async {
    final db = await _db;
    final rows = await db.query(
      DatabaseConstants.tableEquipment,
      where: '${DatabaseConstants.colId} = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final eyepieces = await _getEyepiecesForEquipment(db, id);
    return Equipment.fromMap(rows.first, eyepieces: eyepieces);
  }

  Future<void> insert(Equipment equipment) async {
    final db = await _db;
    await db.transaction((txn) async {
      await _upsertAggregate(txn, equipment);
      if (syncMutationsEnabled) {
        await _enqueueSnapshot(txn, equipment, EquipmentSyncOperation.create);
      }
    });
  }

  Future<void> update(Equipment equipment) async {
    final db = await _db;
    await db.transaction((txn) async {
      await _upsertAggregate(txn, equipment);
      if (syncMutationsEnabled) {
        await _enqueueSnapshot(txn, equipment, EquipmentSyncOperation.update);
      }
    });
  }

  Future<void> delete(String id) async {
    final db = await _db;
    await db.transaction((txn) async {
      final equipment = await _get(txn, id);
      if (equipment == null) return;
      if (syncMutationsEnabled) {
        await _enqueueSnapshot(txn, equipment, EquipmentSyncOperation.delete);
      }
      await _deleteAggregate(txn, id);
    });
  }

  Future<EquipmentSyncMetadata?> getSyncMetadata(String equipmentId) async {
    final db = await _db;
    final rows = await db.query(
      DatabaseConstants.tableEquipmentSyncState,
      where: 'equipment_id = ?',
      whereArgs: [equipmentId],
      limit: 1,
    );
    return rows.isEmpty ? null : EquipmentSyncMetadata.fromMap(rows.single);
  }

  Future<bool> isServerBacked(String equipmentId) async {
    final metadata = await getSyncMetadata(equipmentId);
    return metadata?.serverRevision != null &&
        metadata?.serverDeletedAt == null;
  }

  Future<bool> hasPendingSync(String equipmentId) async {
    final db = await _db;
    return _hasPendingSync(db, equipmentId);
  }

  Future<List<EquipmentSyncItem>> listPendingSync() async {
    final db = await _db;
    final now = DateTime.now().toUtc().toIso8601String();
    final rows = await db.query(
      DatabaseConstants.tableEquipmentSyncOutbox,
      where:
          "state IN ('QUEUED','PROCESSING') OR (state='FAILED' AND retry_count <= 3 AND (next_retry_at IS NULL OR next_retry_at <= ?))",
      whereArgs: [now],
      orderBy: 'created_at ASC, id ASC',
    );
    return rows.map(EquipmentSyncItem.fromMap).toList(growable: false);
  }

  Future<void> ensureBootstrapQueued(Equipment equipment) async {
    final db = await _db;
    await db.transaction((txn) async {
      final metadata = await _metadata(txn, equipment.id);
      if (metadata?.serverRevision != null) return;
      final existing = await _pendingOperation(
        txn,
        equipment.id,
        EquipmentSyncOperation.create,
        states: const ['QUEUED', 'PROCESSING', 'FAILED', 'CONFLICT'],
      );
      if (existing == null) {
        await _enqueueSnapshot(txn, equipment, EquipmentSyncOperation.create);
      }
    });
  }

  Future<bool> applyRemoteAggregate(
    EquipmentRemoteAggregate aggregate, {
    bool force = false,
  }) async {
    final db = await _db;
    return db.transaction((txn) async {
      final current = await _get(txn, aggregate.equipment.id);
      final metadata = await _metadata(txn, aggregate.equipment.id);
      if (!force &&
          metadata?.serverRevision != null &&
          metadata!.serverRevision! >= aggregate.revision) {
        return false;
      }
      final changed =
          current == null || !_sameAggregate(current, aggregate.equipment);
      await _upsertAggregate(txn, aggregate.equipment);
      await _writeMetadata(txn, aggregate);
      return changed;
    });
  }

  Future<bool> applyRemoteDelete({
    required String equipmentId,
    required int revision,
    required DateTime deletedAt,
    bool force = false,
  }) async {
    final db = await _db;
    return db.transaction((txn) async {
      final metadata = await _metadata(txn, equipmentId);
      if (metadata?.serverRevision case final current?
          when current >= revision && metadata?.serverDeletedAt != null) {
        return false;
      }
      if (!force && await _hasPendingSync(txn, equipmentId)) {
        await _writeDeleteMetadata(
          txn,
          equipmentId: equipmentId,
          revision: revision,
          deletedAt: deletedAt,
        );
        await txn.update(
          DatabaseConstants.tableEquipmentSyncOutbox,
          {
            'state': 'CONFLICT',
            'last_error': 'Remote Equipment was deleted.',
            'next_retry_at': null,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          where:
              "equipment_id = ? AND state IN ('QUEUED','PROCESSING','FAILED')",
          whereArgs: [equipmentId],
        );
        return false;
      }
      final changed = await _get(txn, equipmentId) != null;
      await _deleteAggregate(txn, equipmentId);
      await _writeDeleteMetadata(
        txn,
        equipmentId: equipmentId,
        revision: revision,
        deletedAt: deletedAt,
      );
      return changed;
    });
  }

  Future<bool> applyRemoteMissing(String equipmentId) async {
    final db = await _db;
    return db.transaction((txn) async {
      final metadata = await _metadata(txn, equipmentId);
      if (metadata?.serverRevision == null) return false;
      final changed = await _get(txn, equipmentId) != null;
      await _deleteAggregate(txn, equipmentId);
      final now = DateTime.now().toUtc().toIso8601String();
      await txn.update(
        DatabaseConstants.tableEquipmentSyncState,
        {'server_deleted_at': now, 'last_synced_at': now},
        where: 'equipment_id = ?',
        whereArgs: [equipmentId],
      );
      return changed;
    });
  }

  Future<void> saveRemoteSnapshotOnly(
    EquipmentRemoteAggregate aggregate,
  ) async {
    final db = await _db;
    await db.transaction((txn) => _writeMetadata(txn, aggregate));
  }

  Future<void> markSyncProcessing(String operationId) async {
    final db = await _db;
    await db.update(
      DatabaseConstants.tableEquipmentSyncOutbox,
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
        DatabaseConstants.tableEquipmentSyncOutbox,
        columns: const ['equipment_id'],
        where: 'operation_id = ?',
        whereArgs: [operationId],
        limit: 1,
      );
      await txn.update(
        DatabaseConstants.tableEquipmentSyncOutbox,
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
          DatabaseConstants.tableEquipmentSyncOutbox,
          {'state': 'CANCELLED', 'updated_at': now},
          where: "equipment_id = ? AND state = 'CONFLICT'",
          whereArgs: [rows.single['equipment_id']],
        );
      }
    });
  }

  Future<void> rebaseQueuedSync(String equipmentId, int revision) async {
    final db = await _db;
    await db.update(
      DatabaseConstants.tableEquipmentSyncOutbox,
      {
        'base_revision': revision,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where:
          "equipment_id = ? AND operation_type IN ('UPDATE','DELETE') AND state = 'QUEUED'",
      whereArgs: [equipmentId],
    );
  }

  Future<void> markSyncFailed(EquipmentSyncItem item, String error) async {
    final retryCount = item.retryCount + 1;
    final delay = switch (retryCount) {
      1 => const Duration(seconds: 5),
      2 => const Duration(seconds: 15),
      _ => const Duration(seconds: 60),
    };
    final now = DateTime.now().toUtc();
    final db = await _db;
    await db.update(
      DatabaseConstants.tableEquipmentSyncOutbox,
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
    EquipmentSyncItem item,
    String error, {
    EquipmentRemoteAggregate? serverAggregate,
  }) async {
    final db = await _db;
    await db.transaction((txn) async {
      if (serverAggregate != null) {
        await _writeMetadata(txn, serverAggregate);
      }
      await txn.update(
        DatabaseConstants.tableEquipmentSyncOutbox,
        {
          'state': 'CONFLICT',
          'last_error': error,
          'conflict_snapshot_json': serverAggregate == null
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

  Future<Equipment?> _get(DatabaseExecutor db, String id) async {
    final rows = await db.query(
      DatabaseConstants.tableEquipment,
      where: '${DatabaseConstants.colId} = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final eyepieces = await _getEyepiecesForEquipment(db, id);
    return Equipment.fromMap(rows.single, eyepieces: eyepieces);
  }

  Future<EquipmentSyncMetadata?> _metadata(
    DatabaseExecutor db,
    String equipmentId,
  ) async {
    final rows = await db.query(
      DatabaseConstants.tableEquipmentSyncState,
      where: 'equipment_id = ?',
      whereArgs: [equipmentId],
      limit: 1,
    );
    return rows.isEmpty ? null : EquipmentSyncMetadata.fromMap(rows.single);
  }

  Future<bool> _hasPendingSync(DatabaseExecutor db, String equipmentId) async {
    final count = Sqflite.firstIntValue(
      await db.rawQuery(
        '''
        SELECT COUNT(*)
        FROM ${DatabaseConstants.tableEquipmentSyncOutbox}
        WHERE equipment_id = ?
          AND state IN ('QUEUED','PROCESSING','FAILED','CONFLICT')
        ''',
        [equipmentId],
      ),
    );
    return (count ?? 0) > 0;
  }

  Future<void> _writeMetadata(
    DatabaseExecutor db,
    EquipmentRemoteAggregate aggregate,
  ) async {
    await db.insert(
      DatabaseConstants.tableEquipmentSyncState,
      {
        'equipment_id': aggregate.equipment.id,
        'server_revision': aggregate.revision,
        'server_updated_at': aggregate.updatedAt.toUtc().toIso8601String(),
        'server_deleted_at': aggregate.deletedAt?.toUtc().toIso8601String(),
        'last_synced_at': DateTime.now().toUtc().toIso8601String(),
        'canonical_snapshot_json': jsonEncode(aggregate.toJson()),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _writeDeleteMetadata(
    DatabaseExecutor db, {
    required String equipmentId,
    required int revision,
    required DateTime deletedAt,
  }) async {
    final timestamp = deletedAt.toUtc().toIso8601String();
    await db.insert(
      DatabaseConstants.tableEquipmentSyncState,
      {
        'equipment_id': equipmentId,
        'server_revision': revision,
        'server_updated_at': timestamp,
        'server_deleted_at': timestamp,
        'last_synced_at': DateTime.now().toUtc().toIso8601String(),
        'canonical_snapshot_json': null,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _upsertAggregate(
    DatabaseExecutor db,
    Equipment equipment,
  ) async {
    final updated = await db.update(
      DatabaseConstants.tableEquipment,
      equipment.toMap(),
      where: '${DatabaseConstants.colId} = ?',
      whereArgs: [equipment.id],
    );
    if (updated == 0) {
      await db.insert(
        DatabaseConstants.tableEquipment,
        equipment.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await db.delete(
      DatabaseConstants.tableEyepieces,
      where: '${DatabaseConstants.colEquipmentId} = ?',
      whereArgs: [equipment.id],
    );
    for (final eyepiece in equipment.eyepieces) {
      final canonical = Eyepiece(
        id: eyepiece.id,
        equipmentId: equipment.id,
        name: eyepiece.name,
        focalLengthMm: eyepiece.focalLengthMm,
        afovDegrees: eyepiece.afovDegrees,
        sortOrder: eyepiece.sortOrder,
      );
      await db.insert(
        DatabaseConstants.tableEyepieces,
        canonical.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<void> _deleteAggregate(DatabaseExecutor db, String id) async {
    await db.delete(
      DatabaseConstants.tableEyepieces,
      where: '${DatabaseConstants.colEquipmentId} = ?',
      whereArgs: [id],
    );
    await db.delete(
      DatabaseConstants.tableEquipment,
      where: '${DatabaseConstants.colId} = ?',
      whereArgs: [id],
    );
  }

  Future<void> _enqueueSnapshot(
    DatabaseExecutor db,
    Equipment equipment,
    EquipmentSyncOperation requestedOperation,
  ) async {
    final metadata = await _metadata(db, equipment.id);
    var operation = requestedOperation;
    final payload = jsonEncode(
      EquipmentRemoteAggregate(
        equipment: equipment,
        revision: metadata?.serverRevision ?? 0,
        createdAt: metadata?.serverUpdatedAt ?? DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ).toJson(),
    );
    final now = DateTime.now().toUtc().toIso8601String();

    if (requestedOperation == EquipmentSyncOperation.update &&
        metadata?.serverRevision == null) {
      final queuedCreate = await _pendingOperation(
        db,
        equipment.id,
        EquipmentSyncOperation.create,
        states: const ['QUEUED', 'FAILED'],
      );
      if (queuedCreate != null) {
        await _replacePendingPayload(db, queuedCreate, payload, now);
        return;
      }
      operation = EquipmentSyncOperation.create;
    }

    if (operation == EquipmentSyncOperation.create) {
      final existing = await _pendingOperation(
        db,
        equipment.id,
        operation,
        states: const ['QUEUED', 'FAILED'],
      );
      if (existing != null) {
        await _replacePendingPayload(db, existing, payload, now);
        return;
      }
    }

    if (operation == EquipmentSyncOperation.update) {
      final existing = await _pendingOperation(
        db,
        equipment.id,
        operation,
        states: const ['QUEUED', 'FAILED'],
      );
      if (existing != null) {
        await _replacePendingPayload(db, existing, payload, now);
        return;
      }
    }

    if (operation == EquipmentSyncOperation.delete) {
      if (metadata?.serverRevision == null) {
        final queuedCreate = await _pendingOperation(
          db,
          equipment.id,
          EquipmentSyncOperation.create,
          states: const ['QUEUED', 'FAILED'],
        );
        if (queuedCreate != null) {
          await db.update(
            DatabaseConstants.tableEquipmentSyncOutbox,
            {'state': 'CANCELLED', 'updated_at': now},
            where: 'operation_id = ?',
            whereArgs: [queuedCreate],
          );
          return;
        }
      }
      final existing = await _pendingOperation(
        db,
        equipment.id,
        operation,
        states: const ['QUEUED', 'FAILED'],
      );
      if (existing != null) return;
      await db.update(
        DatabaseConstants.tableEquipmentSyncOutbox,
        {'state': 'CANCELLED', 'updated_at': now},
        where:
            "equipment_id = ? AND operation_type = 'UPDATE' AND state IN ('QUEUED','FAILED')",
        whereArgs: [equipment.id],
      );
    }

    await db.insert(DatabaseConstants.tableEquipmentSyncOutbox, {
      'operation_id': const Uuid().v4(),
      'equipment_id': equipment.id,
      'operation_type': operation.databaseValue,
      'base_revision': metadata?.serverRevision,
      'payload_json': payload,
      'state': 'QUEUED',
      'retry_count': 0,
      'next_retry_at': null,
      'last_error': null,
      'conflict_snapshot_json': null,
      'created_at': now,
      'updated_at': now,
      'completed_at': null,
    });
  }

  Future<void> _replacePendingPayload(
    DatabaseExecutor db,
    String operationId,
    String payload,
    String now,
  ) async {
    await db.update(
      DatabaseConstants.tableEquipmentSyncOutbox,
      {
        'payload_json': payload,
        'state': 'QUEUED',
        'retry_count': 0,
        'next_retry_at': null,
        'last_error': null,
        'updated_at': now,
      },
      where: 'operation_id = ?',
      whereArgs: [operationId],
    );
  }

  Future<String?> _pendingOperation(
    DatabaseExecutor db,
    String equipmentId,
    EquipmentSyncOperation operation, {
    required List<String> states,
  }) async {
    final placeholders = List.filled(states.length, '?').join(',');
    final rows = await db.query(
      DatabaseConstants.tableEquipmentSyncOutbox,
      columns: const ['operation_id'],
      where:
          'equipment_id = ? AND operation_type = ? AND state IN ($placeholders)',
      whereArgs: [equipmentId, operation.databaseValue, ...states],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['operation_id'] as String;
  }

  bool _sameAggregate(Equipment left, Equipment right) {
    Map<String, Object?> normalized(Equipment value) => {
      'equipment': value.toMap(),
      'eyepieces': value.eyepieces.map((item) => item.toMap()).toList(),
    };
    return jsonEncode(normalized(left)) == jsonEncode(normalized(right));
  }

  Future<List<Eyepiece>> _getEyepiecesForEquipment(
    DatabaseExecutor db,
    String equipmentId,
  ) async {
    final grouped = await _getEyepiecesGroupedByEquipment(db, [equipmentId]);
    return grouped[equipmentId] ?? const [];
  }

  Future<Map<String, List<Eyepiece>>> _getEyepiecesGroupedByEquipment(
    DatabaseExecutor db,
    List<String> equipmentIds,
  ) async {
    if (equipmentIds.isEmpty) return {};

    final placeholders = List.filled(equipmentIds.length, '?').join(', ');
    final rows = await db.query(
      DatabaseConstants.tableEyepieces,
      where: '${DatabaseConstants.colEquipmentId} IN ($placeholders)',
      whereArgs: equipmentIds,
      orderBy:
          '${DatabaseConstants.colSortOrder}, ${DatabaseConstants.colFocalLengthMm}',
    );

    final grouped = <String, List<Eyepiece>>{};
    for (final row in rows) {
      final eyepiece = Eyepiece.fromMap(row);
      (grouped[eyepiece.equipmentId] ??= []).add(eyepiece);
    }
    return grouped;
  }
}

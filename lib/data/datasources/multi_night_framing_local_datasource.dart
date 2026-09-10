import 'dart:convert';

import 'package:sqflite/sqflite.dart'
    show ConflictAlgorithm, Database, DatabaseExecutor, Sqflite;
import 'package:uuid/uuid.dart';

import '../../core/constants/database_constants.dart';
import '../database/app_database.dart';
import '../models/multi_night_framing_reference.dart';
import '../models/multi_night_framing_sync_item.dart';

class MultiNightFramingLocalDataSource {
  MultiNightFramingLocalDataSource({
    Database? database,
    this.syncMutationsEnabled = false,
  }) : _database = database;

  Database? _database;
  final bool syncMutationsEnabled;

  Future<Database> get _db async {
    _database = await AppDatabase.resolve(_database);
    return _database!;
  }

  Future<List<MultiNightFramingReference>> list({
    String? catalogObjectId,
    String? equipmentId,
    bool includeDeleted = false,
  }) async {
    final clauses = <String>[];
    final args = <Object?>[];
    if (!includeDeleted) clauses.add('deleted_at IS NULL');
    if (catalogObjectId != null) {
      clauses.add('catalog_object_id = ?');
      args.add(catalogObjectId);
    }
    if (equipmentId != null) {
      clauses.add('equipment_id = ?');
      args.add(equipmentId);
    }
    final db = await _db;
    final rows = await db.query(
      DatabaseConstants.tableMultiNightFramingReferences,
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'reference_captured_at DESC',
    );
    return rows.map(MultiNightFramingReference.fromMap).toList(growable: false);
  }

  Future<MultiNightFramingReference?> get(
    String id, {
    bool includeDeleted = false,
  }) async {
    final db = await _db;
    return _get(db, id, includeDeleted: includeDeleted);
  }

  Future<MultiNightFramingReference?> findIdentity({
    required String catalogObjectId,
    required String equipmentId,
  }) async {
    final values = await list(
      catalogObjectId: catalogObjectId,
      equipmentId: equipmentId,
    );
    return values.isEmpty ? null : values.first;
  }

  Future<void> create(MultiNightFramingReference reference) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.insert(
        DatabaseConstants.tableMultiNightFramingReferences,
        reference.toMap(),
      );
      if (syncMutationsEnabled) {
        await _enqueue(txn, reference, MultiNightFramingSyncOperation.create);
      }
    });
  }

  Future<void> update(MultiNightFramingReference reference) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.update(
        DatabaseConstants.tableMultiNightFramingReferences,
        reference.copyWith(updatedAt: DateTime.now()).toMap(),
        where: 'id = ?',
        whereArgs: [reference.id],
      );
      if (syncMutationsEnabled) {
        await _enqueue(txn, reference, MultiNightFramingSyncOperation.update);
      }
    });
  }

  Future<void> delete(String id) async {
    final db = await _db;
    await db.transaction((txn) async {
      final reference = await _get(txn, id);
      if (reference == null) return;
      if (syncMutationsEnabled) {
        await _enqueue(txn, reference, MultiNightFramingSyncOperation.delete);
      }
      final now = DateTime.now().toUtc().toIso8601String();
      await txn.update(
        DatabaseConstants.tableMultiNightFramingReferences,
        {'deleted_at': now, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<MultiNightFramingSyncMetadata?> getSyncMetadata(
    String referenceId,
  ) async {
    final db = await _db;
    return _metadata(db, referenceId);
  }

  Future<bool> hasPendingSync(String referenceId) async {
    final db = await _db;
    return _hasPendingSync(db, referenceId);
  }

  Future<List<MultiNightFramingSyncItem>> listPendingSync() async {
    final db = await _db;
    final now = DateTime.now().toUtc().toIso8601String();
    final rows = await db.query(
      DatabaseConstants.tableMultiNightFramingSyncOutbox,
      where:
          "state IN ('QUEUED','PROCESSING') OR (state='FAILED' AND retry_count <= 3 AND (next_retry_at IS NULL OR next_retry_at <= ?))",
      whereArgs: [now],
      orderBy: 'created_at ASC, id ASC',
    );
    return rows.map(MultiNightFramingSyncItem.fromMap).toList(growable: false);
  }

  Future<String?> latestConflictForCatalog(String catalogObjectId) async {
    final db = await _db;
    final rows = await db.rawQuery(
      '''
      SELECT o.last_error
      FROM ${DatabaseConstants.tableMultiNightFramingSyncOutbox} o
      INNER JOIN ${DatabaseConstants.tableMultiNightFramingReferences} r
        ON r.id = o.reference_id
      WHERE r.catalog_object_id = ? AND o.state = 'CONFLICT'
      ORDER BY o.updated_at DESC
      LIMIT 1
      ''',
      [catalogObjectId],
    );
    return rows.isEmpty ? null : rows.single['last_error'] as String?;
  }

  Future<bool> applyRemote(
    MultiNightFramingReference reference, {
    bool force = false,
  }) async {
    final db = await _db;
    return db.transaction((txn) async {
      final metadata = await _metadata(txn, reference.id);
      if (!force &&
          metadata?.serverRevision != null &&
          metadata!.serverRevision! >= reference.revision) {
        return false;
      }
      final before = await _get(txn, reference.id, includeDeleted: true);
      await txn.insert(
        DatabaseConstants.tableMultiNightFramingReferences,
        reference.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await _writeMetadata(txn, reference);
      return before == null ||
          jsonEncode(before.toMap()) != jsonEncode(reference.toMap());
    });
  }

  Future<bool> applyRemoteDelete({
    required String referenceId,
    required int revision,
    required DateTime deletedAt,
    bool force = false,
  }) async {
    final db = await _db;
    return db.transaction((txn) async {
      final metadata = await _metadata(txn, referenceId);
      if (metadata?.serverRevision case final current?
          when current >= revision && metadata?.serverDeletedAt != null) {
        return false;
      }
      if (!force && await _hasPendingSync(txn, referenceId)) {
        await _writeDeleteMetadata(
          txn,
          referenceId: referenceId,
          revision: revision,
          deletedAt: deletedAt,
        );
        await txn.update(
          DatabaseConstants.tableMultiNightFramingSyncOutbox,
          {
            'state': 'CONFLICT',
            'last_error': 'Remote reference was deleted.',
            'next_retry_at': null,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          where:
              "reference_id = ? AND state IN ('QUEUED','PROCESSING','FAILED')",
          whereArgs: [referenceId],
        );
        return false;
      }
      final before = await _get(txn, referenceId);
      await txn.update(
        DatabaseConstants.tableMultiNightFramingReferences,
        {
          'revision': revision,
          'deleted_at': deletedAt.toUtc().toIso8601String(),
          'updated_at': deletedAt.toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [referenceId],
      );
      await _writeDeleteMetadata(
        txn,
        referenceId: referenceId,
        revision: revision,
        deletedAt: deletedAt,
      );
      return before != null;
    });
  }

  Future<bool> applyRemoteMissing(String referenceId) async {
    final db = await _db;
    return db.transaction((txn) async {
      final metadata = await _metadata(txn, referenceId);
      if (metadata?.serverRevision == null ||
          await _hasPendingSync(txn, referenceId)) {
        return false;
      }
      final before = await _get(txn, referenceId);
      final now = DateTime.now().toUtc();
      if (before != null) {
        await txn.update(
          DatabaseConstants.tableMultiNightFramingReferences,
          {
            'deleted_at': now.toIso8601String(),
            'updated_at': now.toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [referenceId],
        );
      }
      await txn.update(
        DatabaseConstants.tableMultiNightFramingSyncState,
        {
          'server_deleted_at': now.toIso8601String(),
          'last_synced_at': now.toIso8601String(),
        },
        where: 'reference_id = ?',
        whereArgs: [referenceId],
      );
      return before != null;
    });
  }

  Future<void> saveRemoteSnapshotOnly(
    MultiNightFramingReference reference,
  ) async {
    final db = await _db;
    await db.transaction((txn) => _writeMetadata(txn, reference));
  }

  Future<bool> preserveIdentityConflict(
    MultiNightFramingReference localReference,
    MultiNightFramingReference serverReference,
  ) async {
    final db = await _db;
    return db.transaction((txn) async {
      final updated = await txn.update(
        DatabaseConstants.tableMultiNightFramingSyncOutbox,
        {
          'state': 'CONFLICT',
          'last_error': 'REFERENCE_ALREADY_EXISTS',
          'conflict_snapshot_json': jsonEncode(serverReference.toJson()),
          'next_retry_at': null,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: "reference_id = ? AND state IN ('QUEUED','PROCESSING','FAILED')",
        whereArgs: [localReference.id],
      );
      await _writeMetadata(txn, serverReference);
      return updated > 0;
    });
  }

  Future<void> markProcessing(String operationId) async {
    final db = await _db;
    await db.update(
      DatabaseConstants.tableMultiNightFramingSyncOutbox,
      {
        'state': 'PROCESSING',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'operation_id = ?',
      whereArgs: [operationId],
    );
  }

  Future<void> markSucceeded(String operationId) async {
    final db = await _db;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      DatabaseConstants.tableMultiNightFramingSyncOutbox,
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
  }

  Future<void> rebaseQueued(String referenceId, int revision) async {
    final db = await _db;
    await db.update(
      DatabaseConstants.tableMultiNightFramingSyncOutbox,
      {
        'base_revision': revision,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where:
          "reference_id = ? AND operation_type IN ('UPDATE','DELETE') AND state = 'QUEUED'",
      whereArgs: [referenceId],
    );
  }

  Future<void> markFailed(MultiNightFramingSyncItem item, String error) async {
    final retryCount = item.retryCount + 1;
    final delay = switch (retryCount) {
      1 => const Duration(seconds: 5),
      2 => const Duration(seconds: 15),
      _ => const Duration(seconds: 60),
    };
    final now = DateTime.now().toUtc();
    final db = await _db;
    await db.update(
      DatabaseConstants.tableMultiNightFramingSyncOutbox,
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

  Future<void> markConflict(
    MultiNightFramingSyncItem item,
    String error, {
    MultiNightFramingReference? serverReference,
  }) async {
    final db = await _db;
    await db.transaction((txn) async {
      if (serverReference != null) {
        await _writeMetadata(txn, serverReference);
      }
      await txn.update(
        DatabaseConstants.tableMultiNightFramingSyncOutbox,
        {
          'state': 'CONFLICT',
          'last_error': error,
          'conflict_snapshot_json': serverReference == null
              ? null
              : jsonEncode(serverReference.toJson()),
          'next_retry_at': null,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'operation_id = ?',
        whereArgs: [item.operationId],
      );
    });
  }

  Future<MultiNightFramingReference?> _get(
    DatabaseExecutor db,
    String id, {
    bool includeDeleted = false,
  }) async {
    final rows = await db.query(
      DatabaseConstants.tableMultiNightFramingReferences,
      where: includeDeleted ? 'id = ?' : 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty
        ? null
        : MultiNightFramingReference.fromMap(rows.single);
  }

  Future<MultiNightFramingSyncMetadata?> _metadata(
    DatabaseExecutor db,
    String referenceId,
  ) async {
    final rows = await db.query(
      DatabaseConstants.tableMultiNightFramingSyncState,
      where: 'reference_id = ?',
      whereArgs: [referenceId],
      limit: 1,
    );
    return rows.isEmpty
        ? null
        : MultiNightFramingSyncMetadata.fromMap(rows.single);
  }

  Future<bool> _hasPendingSync(DatabaseExecutor db, String referenceId) async {
    final count = Sqflite.firstIntValue(
      await db.rawQuery(
        '''
        SELECT COUNT(*)
        FROM ${DatabaseConstants.tableMultiNightFramingSyncOutbox}
        WHERE reference_id = ?
          AND state IN ('QUEUED','PROCESSING','FAILED','CONFLICT')
        ''',
        [referenceId],
      ),
    );
    return (count ?? 0) > 0;
  }

  Future<void> _writeMetadata(
    DatabaseExecutor db,
    MultiNightFramingReference reference,
  ) async {
    await db.insert(
      DatabaseConstants.tableMultiNightFramingSyncState,
      {
        'reference_id': reference.id,
        'server_revision': reference.revision,
        'server_updated_at': reference.updatedAt.toUtc().toIso8601String(),
        'server_deleted_at': reference.deletedAt?.toUtc().toIso8601String(),
        'last_synced_at': DateTime.now().toUtc().toIso8601String(),
        'canonical_snapshot_json': jsonEncode(reference.toJson()),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _writeDeleteMetadata(
    DatabaseExecutor db, {
    required String referenceId,
    required int revision,
    required DateTime deletedAt,
  }) async {
    final timestamp = deletedAt.toUtc().toIso8601String();
    await db.insert(
      DatabaseConstants.tableMultiNightFramingSyncState,
      {
        'reference_id': referenceId,
        'server_revision': revision,
        'server_updated_at': timestamp,
        'server_deleted_at': timestamp,
        'last_synced_at': DateTime.now().toUtc().toIso8601String(),
        'canonical_snapshot_json': null,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _enqueue(
    DatabaseExecutor db,
    MultiNightFramingReference reference,
    MultiNightFramingSyncOperation requested,
  ) async {
    final metadata = await _metadata(db, reference.id);
    var operation = requested;
    final payload = jsonEncode(reference.toJson());
    final now = DateTime.now().toUtc().toIso8601String();

    if (requested == MultiNightFramingSyncOperation.update &&
        metadata?.serverRevision == null) {
      final createId = await _pendingOperation(
        db,
        reference.id,
        MultiNightFramingSyncOperation.create,
      );
      if (createId != null) {
        await _replacePayload(db, createId, payload, now);
        return;
      }
      operation = MultiNightFramingSyncOperation.create;
    }

    if (operation != MultiNightFramingSyncOperation.delete) {
      final existing = await _pendingOperation(db, reference.id, operation);
      if (existing != null) {
        await _replacePayload(db, existing, payload, now);
        return;
      }
    } else {
      if (metadata?.serverRevision == null) {
        final createId = await _pendingOperation(
          db,
          reference.id,
          MultiNightFramingSyncOperation.create,
        );
        if (createId != null) {
          await db.update(
            DatabaseConstants.tableMultiNightFramingSyncOutbox,
            {'state': 'CANCELLED', 'updated_at': now},
            where: 'operation_id = ?',
            whereArgs: [createId],
          );
          return;
        }
      }
      await db.update(
        DatabaseConstants.tableMultiNightFramingSyncOutbox,
        {'state': 'CANCELLED', 'updated_at': now},
        where:
            "reference_id = ? AND operation_type = 'UPDATE' AND state IN ('QUEUED','FAILED')",
        whereArgs: [reference.id],
      );
    }

    await db.insert(DatabaseConstants.tableMultiNightFramingSyncOutbox, {
      'operation_id': const Uuid().v4(),
      'reference_id': reference.id,
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

  Future<String?> _pendingOperation(
    DatabaseExecutor db,
    String referenceId,
    MultiNightFramingSyncOperation operation,
  ) async {
    final rows = await db.query(
      DatabaseConstants.tableMultiNightFramingSyncOutbox,
      columns: const ['operation_id'],
      where:
          "reference_id = ? AND operation_type = ? AND state IN ('QUEUED','FAILED')",
      whereArgs: [referenceId, operation.databaseValue],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['operation_id'] as String;
  }

  Future<void> _replacePayload(
    DatabaseExecutor db,
    String operationId,
    String payload,
    String now,
  ) async {
    await db.update(
      DatabaseConstants.tableMultiNightFramingSyncOutbox,
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
}

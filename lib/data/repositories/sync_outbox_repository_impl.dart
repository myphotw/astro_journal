import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants/database_constants.dart';
import '../database/app_database.dart';
import '../models/sync_outbox_item.dart';
import 'sync_outbox_repository.dart';

class SyncOutboxRepositoryImpl implements SyncOutboxRepository {
  SyncOutboxRepositoryImpl({this.database});

  final Database? database;
  Future<Database> get _db async => AppDatabase.resolve(database);
  @override
  Future<void> create(SyncOutboxItem item) async {
    final db = await _db;
    await db.insert(
      DatabaseConstants.tableSyncOutbox,
      item.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  @override
  Future<List<SyncOutboxItem>> listPending() async {
    final db = await _db;
    final now = DateTime.now().toUtc().toIso8601String();
    final rows = await db.query(
      DatabaseConstants.tableSyncOutbox,
      where:
          "state IN ('QUEUED','UPLOADING','PROCESSING','RECORD_CREATING') OR (state='FAILED' AND (next_retry_at IS NULL OR next_retry_at <= ?))",
      whereArgs: [now],
      orderBy: 'created_at ASC',
    );
    return rows.map(SyncOutboxItem.fromMap).toList();
  }

  @override
  Future<int> countQueued() async {
    final db = await _db;
    return Sqflite.firstIntValue(
          await db.rawQuery(
            "SELECT COUNT(*) FROM sync_outbox WHERE state='QUEUED'",
          ),
        ) ??
        0;
  }

  @override
  Future<int> countProcessing() async {
    final db = await _db;
    return Sqflite.firstIntValue(
          await db.rawQuery(
            "SELECT COUNT(*) FROM sync_outbox WHERE state IN ('UPLOADING','PROCESSING','RECORD_CREATING')",
          ),
        ) ??
        0;
  }

  @override
  Future<int> countFailed() async {
    final db = await _db;
    return Sqflite.firstIntValue(
          await db.rawQuery(
            "SELECT COUNT(*) FROM sync_outbox WHERE state='FAILED'",
          ),
        ) ??
        0;
  }

  @override
  Future<void> updateState(
    String id,
    SyncOutboxState state, {
    String? error,
    DateTime? nextRetryAt,
  }) async {
    final db = await _db;
    await db.update(
      DatabaseConstants.tableSyncOutbox,
      {
        'state': state.name.toUpperCase(),
        'last_error': error,
        'next_retry_at': nextRetryAt?.toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'operation_id=?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> markSynced(
    String id, {
    String? backendFileId,
    String? backendRecordId,
    String? uploadJobId,
  }) async {
    final db = await _db;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      DatabaseConstants.tableSyncOutbox,
      {
        'state': 'SYNCED',
        'backend_file_id': backendFileId,
        'backend_record_id': backendRecordId,
        'upload_job_id': uploadJobId,
        'completed_at': now,
        'updated_at': now,
      },
      where: 'operation_id=?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> patch(String operationId, Map<String, Object?> values) async {
    final db = await _db;
    await db.update(
      DatabaseConstants.tableSyncOutbox,
      {...values, 'updated_at': DateTime.now().toUtc().toIso8601String()},
      where: 'operation_id=?',
      whereArgs: [operationId],
    );
  }

  @override
  Future<void> retryAllFailed() async {
    final db = await _db;
    await db.update(DatabaseConstants.tableSyncOutbox, {
      'state': 'QUEUED',
      'next_retry_at': null,
      'last_error': null,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, where: "state='FAILED'");
  }

  @override
  Future<void> enqueueRecordPatch({
    required String backendRecordId,
    required int expectedRevision,
    required Map<String, Object?> fields,
    String? localRecordId,
  }) async {
    if (fields.isEmpty) return;
    final db = await _db;
    await db.transaction((txn) async {
      var effectiveRevision = expectedRevision;
      final completed = await txn.query(
        DatabaseConstants.tableSyncOutbox,
        columns: const ['payload_json'],
        where:
            "backend_record_id=? AND operation_type IN ('PHOTO_UPLOAD_AND_RECORD','RECORD_PATCH') AND state='SYNCED'",
        whereArgs: [backendRecordId],
        orderBy: 'updated_at DESC',
        limit: 1,
      );
      if (completed.isNotEmpty) {
        final payload = jsonDecode(
          completed.single['payload_json'] as String? ?? '{}',
        );
        final durableRevision = payload is Map ? payload['revision'] : null;
        if (durableRevision is num &&
            durableRevision.toInt() > effectiveRevision) {
          effectiveRevision = durableRevision.toInt();
        }
      }
      final queued = await txn.query(
        DatabaseConstants.tableSyncOutbox,
        where:
            "operation_type='RECORD_PATCH' AND backend_record_id=? AND state='QUEUED'",
        whereArgs: [backendRecordId],
        orderBy: 'created_at DESC',
        limit: 1,
      );
      if (queued.isNotEmpty) {
        final current = SyncOutboxItem.fromMap(queued.first);
        final baseline = current.payload['revision'];
        if (baseline is num && baseline.toInt() == effectiveRevision) {
          final merged = <String, Object?>{
            ...current.payload,
            ...fields,
            'revision': effectiveRevision,
          };
          await txn.update(
            DatabaseConstants.tableSyncOutbox,
            {
              'payload_json': jsonEncode(merged),
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            },
            where: 'operation_id=?',
            whereArgs: [current.operationId],
          );
          return;
        }
      }
      await txn.insert(
        DatabaseConstants.tableSyncOutbox,
        SyncOutboxItem(
          operationId: const Uuid().v4(),
          operationType: SyncOperationType.recordPatch,
          localRecordId: localRecordId,
          backendRecordId: backendRecordId,
          payload: <String, Object?>{'revision': effectiveRevision, ...fields},
        ).toMap(),
      );
    });
  }

  @override
  Future<void> enqueueRecordDelete({
    required String backendRecordId,
    String? localRecordId,
  }) async {
    final db = await _db;
    await db.transaction((txn) async {
      final now = DateTime.now().toUtc().toIso8601String();
      await txn.update(
        DatabaseConstants.tableSyncOutbox,
        {'state': 'CANCELLED', 'updated_at': now},
        where:
            "operation_type='RECORD_PATCH' AND backend_record_id=? AND state IN ('QUEUED','FAILED')",
        whereArgs: [backendRecordId],
      );
      await txn.insert(
        DatabaseConstants.tableSyncOutbox,
        SyncOutboxItem(
          operationId: const Uuid().v4(),
          operationType: SyncOperationType.recordDelete,
          localRecordId: localRecordId,
          backendRecordId: backendRecordId,
          payload: {'backend_record_id': backendRecordId},
        ).toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    });
  }

  @override
  Future<void> cancelPendingUpload(String localRecordId) async {
    final db = await _db;
    await db.update(
      DatabaseConstants.tableSyncOutbox,
      {
        'state': 'CANCELLED',
        'next_retry_at': null,
        'last_error': 'cancelled|Local record deleted before sync completed.',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where:
          "operation_type='PHOTO_UPLOAD_AND_RECORD' AND local_record_id=? AND backend_record_id IS NULL AND state IN ('QUEUED','UPLOADING','PROCESSING','RECORD_CREATING','FAILED')",
      whereArgs: [localRecordId],
    );
  }

  @override
  Future<void> rebaseQueuedRecordPatches(
    String backendRecordId,
    int revision,
  ) async {
    final db = await _db;
    await db.transaction((txn) async {
      final rows = await txn.query(
        DatabaseConstants.tableSyncOutbox,
        columns: const ['operation_id', 'payload_json'],
        where:
            "operation_type='RECORD_PATCH' AND backend_record_id=? AND state='QUEUED'",
        whereArgs: [backendRecordId],
      );
      for (final row in rows) {
        final decoded = jsonDecode(row['payload_json'] as String? ?? '{}');
        if (decoded is! Map) continue;
        final payload = Map<String, Object?>.from(decoded);
        payload['revision'] = revision;
        await txn.update(
          DatabaseConstants.tableSyncOutbox,
          {
            'payload_json': jsonEncode(payload),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          where: 'operation_id=?',
          whereArgs: [row['operation_id']],
        );
      }
    });
  }
}

import 'package:sqflite/sqflite.dart';
import '../../core/constants/database_constants.dart';
import '../database/app_database.dart';
import '../models/sync_outbox_item.dart';
import 'sync_outbox_repository.dart';

class SyncOutboxRepositoryImpl implements SyncOutboxRepository {
  Database? _database;
  Future<Database> get _db async => AppDatabase.resolve(_database);
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
}

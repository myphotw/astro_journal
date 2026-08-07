import 'dart:convert';

import 'package:astro_journal/data/repositories/sync_outbox_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database database;
  late SyncOutboxRepositoryImpl repository;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    database = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await database.execute('''
      CREATE TABLE sync_outbox (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        operation_id TEXT NOT NULL UNIQUE,
        operation_type TEXT NOT NULL,
        local_record_id TEXT,
        local_photo_id TEXT,
        client_file_id TEXT,
        client_record_id TEXT,
        backend_file_id TEXT,
        backend_record_id TEXT,
        upload_job_id TEXT,
        state TEXT NOT NULL,
        retry_count INTEGER NOT NULL DEFAULT 0,
        next_retry_at TEXT,
        last_error TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        completed_at TEXT,
        payload_json TEXT
      )
    ''');
    repository = SyncOutboxRepositoryImpl(database: database);
  });

  tearDown(() => database.close());

  test('queued PATCH values coalesce on the same revision baseline', () async {
    await repository.enqueueRecordPatch(
      backendRecordId: 'record-1',
      expectedRevision: 3,
      fields: const {'favorite': true},
    );
    await repository.enqueueRecordPatch(
      backendRecordId: 'record-1',
      expectedRevision: 3,
      fields: const {'favorite': false, 'memo': 'latest'},
    );

    final rows = await database.query('sync_outbox');
    expect(rows, hasLength(1));
    expect(rows.single['operation_type'], 'RECORD_PATCH');
    expect(jsonDecode(rows.single['payload_json'] as String), {
      'revision': 3,
      'favorite': false,
      'memo': 'latest',
    });
  });

  test('delete cancels queued PATCH before enqueuing durable DELETE', () async {
    await repository.enqueueRecordPatch(
      backendRecordId: 'record-1',
      expectedRevision: 3,
      fields: const {'memo': 'obsolete'},
    );
    await repository.enqueueRecordDelete(backendRecordId: 'record-1');

    final rows = await database.query('sync_outbox', orderBy: 'id');
    expect(rows, hasLength(2));
    expect(rows.first['state'], 'CANCELLED');
    expect(rows.last['operation_type'], 'RECORD_DELETE');
    expect(rows.last['state'], 'QUEUED');
  });

  test('local-only delete terminally cancels pending upload', () async {
    await database.insert('sync_outbox', {
      'operation_id': 'upload-1',
      'operation_type': 'PHOTO_UPLOAD_AND_RECORD',
      'local_record_id': 'local-1',
      'client_file_id': 'file-client',
      'client_record_id': 'record-client',
      'state': 'PROCESSING',
      'retry_count': 0,
      'created_at': DateTime.utc(2026).toIso8601String(),
      'updated_at': DateTime.utc(2026).toIso8601String(),
      'payload_json': '{}',
    });

    await repository.cancelPendingUpload('local-1');

    final row = (await database.query('sync_outbox')).single;
    expect(row['state'], 'CANCELLED');
    expect(await repository.listPending(), isEmpty);
  });

  test('successful PATCH revision rebases later queued mutation', () async {
    await repository.enqueueRecordPatch(
      backendRecordId: 'record-1',
      expectedRevision: 3,
      fields: const {'favorite': true},
    );
    final first = (await database.query('sync_outbox')).single;
    await database.update(
      'sync_outbox',
      {'state': 'PROCESSING'},
      where: 'operation_id=?',
      whereArgs: [first['operation_id']],
    );
    await repository.enqueueRecordPatch(
      backendRecordId: 'record-1',
      expectedRevision: 3,
      fields: const {'memo': 'later'},
    );

    await repository.rebaseQueuedRecordPatches('record-1', 4);

    final queued = (await database.query(
      'sync_outbox',
      where: "state='QUEUED'",
    )).single;
    expect(jsonDecode(queued['payload_json'] as String), {
      'revision': 4,
      'memo': 'later',
    });
  });
}

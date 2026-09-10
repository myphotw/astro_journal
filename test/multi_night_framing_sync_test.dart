import 'package:astro_journal/core/constants/database_constants.dart';
import 'package:astro_journal/data/database/app_database.dart';
import 'package:astro_journal/data/datasources/multi_night_framing_local_datasource.dart';
import 'package:astro_journal/data/models/multi_night_framing_reference.dart';
import 'package:astro_journal/data/models/tc_backend_change.dart';
import 'package:astro_journal/services/multi_night_framing_sync_coordinator.dart';
import 'package:astro_journal/services/tc_backend_multi_night_framing_service.dart';
import 'package:astro_journal/services/tc_backend_settings_service.dart';
import 'package:astro_journal/services/tc_backend_sync_gate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late MultiNightFramingLocalDataSource local;
  late TcBackendSettingsService settings;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await AppDatabase.createForTest(db, DatabaseConstants.databaseVersion);
    addTearDown(db.close);
    local = MultiNightFramingLocalDataSource(
      database: db,
      syncMutationsEnabled: true,
    );
    SharedPreferences.setMockInitialValues({});
    settings = TcBackendSettingsService();
    await settings.save(
      const TcBackendSettings(
        baseUrl: 'https://backend.example',
        enabled: true,
      ),
    );
  });

  MultiNightFramingSyncCoordinator subject(_FakeApi api) =>
      MultiNightFramingSyncCoordinator(
        remoteApi: api,
        localDataSource: local,
        settingsService: settings,
        syncGate: TcBackendSyncGate(),
      );

  test(
    'v34 to v35 creates projection, metadata, outbox, and indexes',
    () async {
      final migrationDb = await databaseFactory.openDatabase(
        inMemoryDatabasePath,
      );
      addTearDown(migrationDb.close);

      await AppDatabase.migrateForTest(migrationDb, 34, 35);

      final names = (await migrationDb.rawQuery(
        "SELECT name FROM sqlite_master WHERE type IN ('table','index')",
      )).map((row) => row['name']).toSet();
      expect(
        names,
        contains(DatabaseConstants.tableMultiNightFramingReferences),
      );
      expect(
        names,
        contains(DatabaseConstants.tableMultiNightFramingSyncState),
      );
      expect(
        names,
        contains(DatabaseConstants.tableMultiNightFramingSyncOutbox),
      );
      expect(names, contains('idx_multi_night_framing_identity'));
      expect(names, contains('idx_multi_night_framing_outbox_pending'));
    },
  );

  test(
    'optimistic create is durable and resumes after coordinator restart',
    () async {
      await local.create(_reference(revision: 0));
      final offline = _FakeApi(
        listError: const MultiNightFramingRemoteException(
          type: MultiNightFramingRemoteErrorType.network,
          message: 'offline',
        ),
      );
      await subject(offline).drain();
      expect(await local.hasPendingSync(_referenceId), isTrue);
      expect(await local.get(_referenceId), isNotNull);

      final resumed = _FakeApi();
      await subject(resumed).drain();

      expect(resumed.created, [_referenceId]);
      expect((await local.getSyncMetadata(_referenceId))?.serverRevision, 1);
    },
  );

  test('network and endpoint 404 preserve cache and pending outbox', () async {
    for (final type in [
      MultiNightFramingRemoteErrorType.network,
      MultiNightFramingRemoteErrorType.notFound,
    ]) {
      await local.create(_reference(revision: 0));
      await subject(
        _FakeApi(
          listError: MultiNightFramingRemoteException(
            type: type,
            message: '$type',
          ),
        ),
      ).drain();
      expect(await local.get(_referenceId), isNotNull);
      expect(await local.hasPendingSync(_referenceId), isTrue);
      await db.delete(DatabaseConstants.tableMultiNightFramingSyncOutbox);
      await db.delete(DatabaseConstants.tableMultiNightFramingReferences);
    }
  });

  test('retryable mutation failure remains durable with backoff', () async {
    await local.create(_reference(revision: 0));
    final api = _FakeApi(
      createError: const MultiNightFramingRemoteException(
        type: MultiNightFramingRemoteErrorType.server,
        message: 'temporary failure',
      ),
    );

    await subject(api).drain();

    final rows = await db.query(
      DatabaseConstants.tableMultiNightFramingSyncOutbox,
      where: 'reference_id = ?',
      whereArgs: [_referenceId],
    );
    expect(rows.single['state'], 'FAILED');
    expect(rows.single['retry_count'], 1);
    expect(rows.single['next_retry_at'], isNotNull);
    expect(await local.get(_referenceId), isNotNull);
  });

  test(
    'PATCH and DELETE use canonical expected revision and tombstone',
    () async {
      final api = _FakeApi(listResult: [_reference(revision: 3)]);
      await subject(api).drain();
      await local.update(
        _reference(
          revision: 3,
        ).copyWith(referenceCapturedAt: DateTime(2026, 7, 15, 22)),
      );
      api.listResult = [_reference(revision: 3)];
      await subject(api).drain();
      expect(api.updatedAtRevisions, [3]);

      await local.delete(_referenceId);
      api.listResult = [_reference(revision: 4)];
      await subject(api).drain();
      expect(api.deletedAtRevisions, [4]);
      expect(await local.get(_referenceId), isNull);
    },
  );

  test(
    '409 conflict preserves optimistic local value and conflict row',
    () async {
      final api = _FakeApi(listResult: [_reference(revision: 2)]);
      await subject(api).drain();
      final edited = _reference(
        revision: 2,
      ).copyWith(referenceHourAngleDeg: -45);
      await local.update(edited);
      api
        ..listResult = [_reference(revision: 3)]
        ..updateError = const MultiNightFramingRemoteException(
          type: MultiNightFramingRemoteErrorType.revisionConflict,
          message: 'REVISION_CONFLICT',
          currentRevision: 3,
        )
        ..detail = _reference(revision: 3);

      await subject(api).drain();

      expect((await local.get(_referenceId))?.referenceHourAngleDeg, -45);
      final conflicts = await db.query(
        DatabaseConstants.tableMultiNightFramingSyncOutbox,
        where: "reference_id = ? AND state = 'CONFLICT'",
        whereArgs: [_referenceId],
      );
      expect(conflicts, hasLength(1));
      expect(conflicts.single['conflict_snapshot_json'], isNotNull);
    },
  );

  test('REFERENCE_ALREADY_EXISTS is durable and not retried', () async {
    await local.create(_reference(revision: 0));
    final api = _FakeApi(
      createError: const MultiNightFramingRemoteException(
        type: MultiNightFramingRemoteErrorType.referenceAlreadyExists,
        message: 'REFERENCE_ALREADY_EXISTS',
      ),
    );

    await subject(api).drain();

    final rows = await db.query(
      DatabaseConstants.tableMultiNightFramingSyncOutbox,
      where: "reference_id = ? AND state = 'CONFLICT'",
      whereArgs: [_referenceId],
    );
    expect(rows, hasLength(1));
    expect(rows.single['last_error'], 'REFERENCE_ALREADY_EXISTS');
  });

  test('common changes apply create update and delete tombstone', () async {
    final api = _FakeApi(detail: _reference(revision: 1));
    final coordinator = subject(api);
    await coordinator.applyChange(_change(TcBackendChangeOperation.create, 1));
    expect(await local.get(_referenceId), isNotNull);

    api.detail = _reference(revision: 2).copyWith(referenceHourAngleDeg: 12);
    await coordinator.applyChange(_change(TcBackendChangeOperation.update, 2));
    expect((await local.get(_referenceId))?.referenceHourAngleDeg, 12);

    await coordinator.applyChange(_change(TcBackendChangeOperation.delete, 3));
    expect(await local.get(_referenceId), isNull);
  });
}

TcBackendChange _change(TcBackendChangeOperation operation, int revision) =>
    TcBackendChange(
      resourceType: 'MultiNightFramingReference',
      resourceId: _referenceId,
      operation: operation,
      revision: revision,
      deletedAt: operation == TcBackendChangeOperation.delete
          ? DateTime.utc(2026, 7, 20)
          : null,
    );

const _referenceId = '11111111-1111-4111-8111-111111111111';

MultiNightFramingReference _reference({required int revision}) =>
    MultiNightFramingReference(
      id: _referenceId,
      catalogObjectId: 'M16',
      referenceCapturedAt: DateTime(2026, 7, 15, 21, 10),
      siteId: '22222222-2222-4222-8222-222222222222',
      equipmentId: '33333333-3333-4333-8333-333333333333',
      referenceHourAngleDeg: -18.25,
      referenceParallacticAngleDeg: 23.75,
      referenceBranch: MultiNightFramingBranch.rising,
      revision: revision,
      createdAt: DateTime.utc(2026, 7, 15),
      updatedAt: DateTime.utc(2026, 7, 16),
    );

class _FakeApi implements MultiNightFramingRemoteApi {
  _FakeApi({
    this.listResult = const [],
    this.detail,
    this.listError,
    this.createError,
  });

  List<MultiNightFramingReference> listResult;
  MultiNightFramingReference? detail;
  MultiNightFramingRemoteException? listError;
  MultiNightFramingRemoteException? createError;
  MultiNightFramingRemoteException? updateError;
  final List<String> created = [];
  final List<int> updatedAtRevisions = [];
  final List<int> deletedAtRevisions = [];

  @override
  Future<MultiNightFramingReference> create(
    MultiNightFramingReference reference,
  ) async {
    if (createError != null) throw createError!;
    created.add(reference.id);
    return reference.copyWith(revision: 1, clearDeletedAt: true);
  }

  @override
  Future<MultiNightFramingDeleteResult> delete(
    String referenceId, {
    required int expectedRevision,
  }) async {
    deletedAtRevisions.add(expectedRevision);
    return MultiNightFramingDeleteResult(
      referenceId: referenceId,
      revision: expectedRevision + 1,
      deletedAt: DateTime.utc(2026, 7, 20),
    );
  }

  @override
  Future<MultiNightFramingReference> get(String referenceId) async =>
      detail ?? _reference(revision: 1);

  @override
  Future<List<MultiNightFramingReference>> list({
    String? catalogObjectId,
    String? equipmentId,
  }) async {
    if (listError != null) throw listError!;
    return listResult;
  }

  @override
  Future<MultiNightFramingReference> update(
    MultiNightFramingReference reference, {
    required int expectedRevision,
  }) async {
    if (updateError != null) throw updateError!;
    updatedAtRevisions.add(expectedRevision);
    return reference.copyWith(revision: expectedRevision + 1);
  }
}

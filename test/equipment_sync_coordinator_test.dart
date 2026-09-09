import 'package:astro_journal/core/constants/database_constants.dart';
import 'package:astro_journal/core/constants/equipment_kind.dart';
import 'package:astro_journal/core/constants/equipment_purpose.dart';
import 'package:astro_journal/data/database/app_database.dart';
import 'package:astro_journal/data/datasources/equipment_local_datasource.dart';
import 'package:astro_journal/data/models/equipment.dart';
import 'package:astro_journal/data/models/equipment_exposure_capability.dart';
import 'package:astro_journal/data/models/equipment_remote.dart';
import 'package:astro_journal/data/models/eyepiece.dart';
import 'package:astro_journal/data/models/tc_backend_change.dart';
import 'package:astro_journal/services/equipment_sync_coordinator.dart';
import 'package:astro_journal/services/tc_backend_equipment_service.dart';
import 'package:astro_journal/services/tc_backend_settings_service.dart';
import 'package:astro_journal/services/tc_backend_sync_gate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late TcBackendSettingsService settings;
  late EquipmentLocalDataSource local;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await AppDatabase.createForTest(db, DatabaseConstants.databaseVersion);
    addTearDown(db.close);
    SharedPreferences.setMockInitialValues({});
    settings = TcBackendSettingsService();
    await settings.save(
      const TcBackendSettings(
        baseUrl: 'https://backend.example',
        enabled: true,
      ),
    );
    local = EquipmentLocalDataSource(database: db, syncMutationsEnabled: true);
  });

  EquipmentSyncCoordinator subject(_FakeEquipmentApi api) =>
      EquipmentSyncCoordinator(
        remoteApi: api,
        localDataSource: local,
        settingsService: settings,
        syncGate: TcBackendSyncGate(),
      );

  test(
    'successful list reconciles canonical aggregate into local cache',
    () async {
      final api = _FakeEquipmentApi(listResult: [_aggregate(revision: 3)]);

      await subject(api).drain();

      final cached = await local.getById(_equipmentId);
      expect(cached, isNotNull);
      expect(cached!.id, _equipmentId);
      expect(cached.name, 'Server Equipment');
      expect(cached.kind, EquipmentKind.smartTelescope);
      expect(cached.purpose, EquipmentPurpose.imaging);
      expect(cached.focalLengthMm, 240);
      expect(cached.apertureMm, 50);
      expect(cached.fovWidthDegrees, 2);
      expect(cached.fovHeightDegrees, 1.5);
      expect(cached.eyepieces.single.name, '25mm');
      expect(
        (cached.azExposureCapability! as DiscreteExposureCapability)
            .valuesSeconds,
        [1, 1.3, 1.6, 2.5, 3.2],
      );
      expect((await local.getSyncMetadata(_equipmentId))?.serverRevision, 3);
    },
  );

  test('existing local-only equipment bootstraps with the same UUID', () async {
    final legacy = EquipmentLocalDataSource(database: db);
    await legacy.insert(_equipment(name: 'Local Equipment'));
    final api = _FakeEquipmentApi();

    await subject(api).drain();

    expect(api.createdIds, [_equipmentId]);
    expect((await local.getById(_equipmentId))?.name, 'Local Equipment');
    expect((await local.getSyncMetadata(_equipmentId))?.serverRevision, 1);
  });

  test('pending update and delete use the stored server revision', () async {
    final api = _FakeEquipmentApi(listResult: [_aggregate(revision: 4)]);
    await subject(api).drain();

    await local.update(_equipment(name: 'Edited'));
    api.listResult = [
      _aggregate(equipment: _equipment(name: 'Edited'), revision: 4),
    ];
    await subject(api).drain();
    expect(api.updateRevisions, [4]);

    await local.delete(_equipmentId);
    api.listResult = [
      _aggregate(equipment: _equipment(name: 'Edited'), revision: 5),
    ];
    await subject(api).drain();
    expect(api.deleteRevisions, [5]);
    expect(await local.getById(_equipmentId), isNull);
  });

  test(
    'revision conflict keeps local edit and durable conflict snapshot',
    () async {
      final api = _FakeEquipmentApi(listResult: [_aggregate(revision: 2)]);
      await subject(api).drain();
      await local.update(_equipment(name: 'Unsynced local edit'));
      api
        ..listResult = [_aggregate(revision: 3)]
        ..updateError = const EquipmentRemoteException(
          type: EquipmentRemoteErrorType.conflict,
          message: 'REVISION_CONFLICT',
          statusCode: 409,
          currentRevision: 3,
        )
        ..detailResult = _aggregate(revision: 3);

      await subject(api).drain();

      expect((await local.getById(_equipmentId))?.name, 'Unsynced local edit');
      final rows = await db.query(
        DatabaseConstants.tableEquipmentSyncOutbox,
        where: "equipment_id = ? AND state = 'CONFLICT'",
        whereArgs: [_equipmentId],
      );
      expect(rows, hasLength(1));
      expect(rows.single['conflict_snapshot_json'], isNotNull);
    },
  );

  test(
    'network and endpoint 404 preserve local cache and pending work',
    () async {
      await local.insert(_equipment(name: 'Offline edit'));
      for (final type in [
        EquipmentRemoteErrorType.network,
        EquipmentRemoteErrorType.notFound,
      ]) {
        final api = _FakeEquipmentApi(
          listError: EquipmentRemoteException(type: type, message: '$type'),
        );
        await subject(api).drain();
        expect((await local.getById(_equipmentId))?.name, 'Offline edit');
        expect(await local.hasPendingSync(_equipmentId), isTrue);
      }
    },
  );

  test(
    'common changes apply create update and delete without polling',
    () async {
      final api = _FakeEquipmentApi(detailResult: _aggregate(revision: 1));
      final coordinator = subject(api);

      await coordinator.applyChange(
        _change(TcBackendChangeOperation.create, revision: 1),
      );
      expect(await local.getById(_equipmentId), isNotNull);

      api.detailResult = _aggregate(
        equipment: _equipment(name: 'Remote update'),
        revision: 2,
      );
      await coordinator.applyChange(
        _change(TcBackendChangeOperation.update, revision: 2),
      );
      expect((await local.getById(_equipmentId))?.name, 'Remote update');

      await coordinator.applyChange(
        _change(TcBackendChangeOperation.delete, revision: 3),
      );
      expect(await local.getById(_equipmentId), isNull);
    },
  );

  test('a new coordinator resumes the durable pending outbox', () async {
    await local.insert(_equipment(name: 'Pending after restart'));
    await subject(
      _FakeEquipmentApi(
        listError: const EquipmentRemoteException(
          type: EquipmentRemoteErrorType.network,
          message: 'offline',
        ),
      ),
    ).drain();

    final resumedApi = _FakeEquipmentApi();
    await subject(resumedApi).drain();

    expect(resumedApi.createdIds, [_equipmentId]);
    expect((await local.getSyncMetadata(_equipmentId))?.serverRevision, 1);
  });
}

TcBackendChange _change(
  TcBackendChangeOperation operation, {
  required int revision,
}) => TcBackendChange(
  resourceType: 'Equipment',
  resourceId: _equipmentId,
  operation: operation,
  revision: revision,
  deletedAt: operation == TcBackendChangeOperation.delete
      ? DateTime.utc(2026, 9, 9)
      : null,
);

const _equipmentId = '22222222-2222-4222-8222-222222222222';

Equipment _equipment({String name = 'Server Equipment'}) => Equipment(
  id: _equipmentId,
  name: name,
  kind: EquipmentKind.smartTelescope,
  purpose: EquipmentPurpose.imaging,
  focalLengthMm: 240,
  apertureMm: 50,
  fovWidthDegrees: 2,
  fovHeightDegrees: 1.5,
  eyepieces: const [
    Eyepiece(
      id: '33333333-3333-4333-8333-333333333333',
      equipmentId: _equipmentId,
      name: '25mm',
      focalLengthMm: 25,
      afovDegrees: 60,
      sortOrder: 0,
    ),
  ],
  azExposureCapability: const DiscreteExposureCapability(
    valuesSeconds: [1, 1.3, 1.6, 2.5, 3.2],
  ),
  eqExposureCapability: const RangeExposureCapability(
    minSeconds: 0.5,
    maxSeconds: 300,
    stepSeconds: 0.5,
  ),
);

EquipmentRemoteAggregate _aggregate({Equipment? equipment, int revision = 1}) =>
    EquipmentRemoteAggregate(
      equipment: equipment ?? _equipment(),
      revision: revision,
      createdAt: DateTime.utc(2026, 9, 1),
      updatedAt: DateTime.utc(2026, 9, 9),
    );

class _FakeEquipmentApi implements EquipmentRemoteApi {
  _FakeEquipmentApi({
    List<EquipmentRemoteAggregate>? listResult,
    this.listError,
    EquipmentRemoteAggregate? detailResult,
  }) : listResult = listResult ?? [],
       detailResult = detailResult ?? _aggregate();

  List<EquipmentRemoteAggregate> listResult;
  final EquipmentRemoteException? listError;
  EquipmentRemoteAggregate detailResult;
  EquipmentRemoteException? updateError;
  final List<String> createdIds = [];
  final List<int> updateRevisions = [];
  final List<int> deleteRevisions = [];

  @override
  Future<List<EquipmentRemoteAggregate>> list() async {
    if (listError != null) throw listError!;
    return listResult;
  }

  @override
  Future<EquipmentRemoteAggregate> get(String equipmentId) async =>
      detailResult;

  @override
  Future<EquipmentRemoteAggregate> create(Equipment equipment) async {
    createdIds.add(equipment.id);
    return _aggregate(equipment: equipment, revision: 1);
  }

  @override
  Future<EquipmentRemoteAggregate> update(
    Equipment equipment, {
    required int expectedRevision,
  }) async {
    updateRevisions.add(expectedRevision);
    if (updateError != null) throw updateError!;
    return _aggregate(equipment: equipment, revision: expectedRevision + 1);
  }

  @override
  Future<EquipmentRemoteDeleteResult> delete(
    String equipmentId, {
    required int expectedRevision,
  }) async {
    deleteRevisions.add(expectedRevision);
    return EquipmentRemoteDeleteResult(
      equipmentId: equipmentId,
      revision: expectedRevision + 1,
      deletedAt: DateTime.utc(2026, 9, 9),
    );
  }
}

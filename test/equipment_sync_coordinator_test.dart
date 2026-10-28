import 'dart:convert';

import 'package:astro_journal/core/constants/database_constants.dart';
import 'package:astro_journal/core/constants/equipment_kind.dart';
import 'package:astro_journal/core/constants/equipment_purpose.dart';
import 'package:astro_journal/data/database/app_database.dart';
import 'package:astro_journal/data/datasources/equipment_local_datasource.dart';
import 'package:astro_journal/data/models/equipment.dart';
import 'package:astro_journal/data/models/equipment_capture_capability.dart';
import 'package:astro_journal/data/models/equipment_exposure_capability.dart';
import 'package:astro_journal/data/models/equipment_remote.dart';
import 'package:astro_journal/data/models/eyepiece.dart';
import 'package:astro_journal/data/models/tc_backend_change.dart';
import 'package:astro_journal/services/equipment_sync_coordinator.dart';
import 'package:astro_journal/services/equipment/equipment_capture_presets.dart';
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
    await legacy.insert(
      _equipment(
        name: 'Local Equipment',
        captureCapability: EquipmentCapturePresets.build(
          EquipmentCapturePreset.seestarS30Pro,
        ),
      ),
    );
    final api = _FakeEquipmentApi();

    await subject(api).drain();

    expect(api.createdIds, [_equipmentId]);
    expect(api.createdCaptureCapabilities.single, isNotNull);
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

  test(
    'legacy canonical snapshot bootstraps local capture capability once',
    () async {
      final capability = EquipmentCapturePresets.build(
        EquipmentCapturePreset.draco,
      );
      final legacy = EquipmentLocalDataSource(database: db);
      await legacy.insert(_equipment(captureCapability: capability));
      final legacyCanonical = EquipmentRemoteAggregate(
        equipment: _equipment(),
        revision: 4,
        createdAt: DateTime.utc(2026, 9, 1),
        updatedAt: DateTime.utc(2026, 9, 9),
        captureCapabilityIncluded: false,
      );
      await db.insert(DatabaseConstants.tableEquipmentSyncState, {
        'equipment_id': _equipmentId,
        'server_revision': 4,
        'server_updated_at': '2026-09-09T00:00:00Z',
        'last_synced_at': '2026-09-09T00:00:00Z',
        'canonical_snapshot_json': jsonEncode(legacyCanonical.toJson()),
      });
      final api = _FakeEquipmentApi(listResult: [_aggregate(revision: 4)]);

      await subject(api).drain();

      expect(api.updateRevisions, [4]);
      expect(api.updateCaptureCapabilityIncluded, [isTrue]);
      expect((await local.getById(_equipmentId))!.captureCapability, isNotNull);

      api.listResult = [
        _aggregate(
          equipment: _equipment(captureCapability: capability),
          revision: 5,
        ),
      ];
      await subject(api).drain();
      expect(api.updateRevisions, [4]);
    },
  );

  test('capability bootstrap resumes after a network failure', () async {
    final capability = EquipmentCapturePresets.build(
      EquipmentCapturePreset.seestarS30Pro,
    );
    final legacy = EquipmentLocalDataSource(database: db);
    await legacy.insert(_equipment(captureCapability: capability));
    final legacyCanonical = EquipmentRemoteAggregate(
      equipment: _equipment(),
      revision: 2,
      createdAt: DateTime.utc(2026, 9, 1),
      updatedAt: DateTime.utc(2026, 9, 9),
      captureCapabilityIncluded: false,
    );
    await db.insert(DatabaseConstants.tableEquipmentSyncState, {
      'equipment_id': _equipmentId,
      'server_revision': 2,
      'server_updated_at': '2026-09-09T00:00:00Z',
      'last_synced_at': '2026-09-09T00:00:00Z',
      'canonical_snapshot_json': jsonEncode(legacyCanonical.toJson()),
    });
    final api = _FakeEquipmentApi(listResult: [_aggregate(revision: 2)])
      ..updateError = const EquipmentRemoteException(
        type: EquipmentRemoteErrorType.network,
        message: 'offline',
      );

    await subject(api).drain();
    expect(await local.hasPendingSync(_equipmentId), isTrue);
    expect((await local.getById(_equipmentId))!.captureCapability, isNotNull);

    api.updateError = null;
    await db.update(
      DatabaseConstants.tableEquipmentSyncOutbox,
      {'next_retry_at': null},
      where: 'equipment_id = ?',
      whereArgs: [_equipmentId],
    );
    await subject(api).drain();

    expect(api.updateRevisions, [2, 2]);
    expect((await local.getSyncMetadata(_equipmentId))?.serverRevision, 3);
  });

  test('legacy pending update is enriched before capability upload', () async {
    final capability = EquipmentCapturePresets.build(
      EquipmentCapturePreset.draco,
    );
    final legacy = EquipmentLocalDataSource(database: db);
    await legacy.insert(_equipment(captureCapability: capability));
    final legacyCanonical = EquipmentRemoteAggregate(
      equipment: _equipment(),
      revision: 2,
      createdAt: DateTime.utc(2026, 9, 1),
      updatedAt: DateTime.utc(2026, 9, 9),
      captureCapabilityIncluded: false,
    );
    await db.insert(DatabaseConstants.tableEquipmentSyncState, {
      'equipment_id': _equipmentId,
      'server_revision': 2,
      'server_updated_at': '2026-09-09T00:00:00Z',
      'last_synced_at': '2026-09-09T00:00:00Z',
      'canonical_snapshot_json': jsonEncode(legacyCanonical.toJson()),
    });
    await db.insert(DatabaseConstants.tableEquipmentSyncOutbox, {
      'operation_id': 'legacy-pending',
      'equipment_id': _equipmentId,
      'operation_type': 'UPDATE',
      'base_revision': 2,
      'payload_json': jsonEncode(legacyCanonical.toJson()),
      'state': 'QUEUED',
      'retry_count': 0,
      'created_at': '2026-09-09T00:00:00Z',
      'updated_at': '2026-09-09T00:00:00Z',
    });
    final api = _FakeEquipmentApi(listResult: [_aggregate(revision: 2)]);

    await subject(api).drain();

    expect(api.updateCaptureCapabilityIncluded, [isTrue]);
    expect((await local.getById(_equipmentId))!.captureCapability, isNotNull);
  });

  test(
    'unrelated update omits capability while explicit clear sends null',
    () async {
      final capability = EquipmentCapturePresets.build(
        EquipmentCapturePreset.draco,
      );
      final api = _FakeEquipmentApi(
        listResult: [
          _aggregate(
            equipment: _equipment(captureCapability: capability),
            revision: 3,
          ),
        ],
      );
      await subject(api).drain();

      await local.update(
        _equipment(name: 'Renamed', captureCapability: capability),
      );
      var queued = await local.listPendingSync();
      expect(queued.single.payload, isNot(contains('capture_capability')));
      await subject(api).drain();
      expect(api.updateCaptureCapabilityIncluded.last, isFalse);

      api.listResult = [
        _aggregate(
          equipment: _equipment(name: 'Renamed', captureCapability: capability),
          revision: 4,
        ),
      ];
      await local.update(
        _equipment(name: 'Renamed').copyWith(clearCaptureCapability: true),
      );
      queued = await local.listPendingSync();
      expect(queued.single.payload, containsPair('capture_capability', null));
      await subject(api).drain();

      expect(api.updateCaptureCapabilityIncluded.last, isTrue);
      expect((await local.getById(_equipmentId))!.captureCapability, isNull);
    },
  );

  test(
    'pending capability mutation survives pull and records server capability on conflict',
    () async {
      final first = EquipmentCapturePresets.build(
        EquipmentCapturePreset.seestarS30Pro,
      );
      final localEdit = EquipmentCapturePresets.build(
        EquipmentCapturePreset.draco,
      );
      final api = _FakeEquipmentApi(
        listResult: [
          _aggregate(
            equipment: _equipment(captureCapability: first),
            revision: 1,
          ),
        ],
      );
      await subject(api).drain();
      await local.update(_equipment(captureCapability: localEdit));

      api
        ..listResult = [
          _aggregate(
            equipment: _equipment(name: 'Remote', captureCapability: first),
            revision: 2,
          ),
        ]
        ..detailResult = _aggregate(
          equipment: _equipment(name: 'Remote', captureCapability: first),
          revision: 2,
        )
        ..updateError = const EquipmentRemoteException(
          type: EquipmentRemoteErrorType.conflict,
          message: 'REVISION_CONFLICT',
          statusCode: 409,
          currentRevision: 2,
        );

      await subject(api).drain();

      expect(
        (await local.getById(_equipmentId))!.captureCapability!.filters.length,
        localEdit.filters.length,
      );
      final rows = await db.query(
        DatabaseConstants.tableEquipmentSyncOutbox,
        where: "equipment_id = ? AND state = 'CONFLICT'",
        whereArgs: [_equipmentId],
      );
      final conflict =
          jsonDecode(rows.single['conflict_snapshot_json'] as String)
              as Map<String, dynamic>;
      expect(conflict['capture_capability'], isA<Map>());
    },
  );

  test(
    'server capability update and null are canonical without pending work',
    () async {
      final capability = EquipmentCapturePresets.build(
        EquipmentCapturePreset.draco,
      );
      final api = _FakeEquipmentApi(
        listResult: [
          _aggregate(
            equipment: _equipment(captureCapability: capability),
            revision: 1,
          ),
        ],
      );
      await subject(api).drain();
      expect((await local.getById(_equipmentId))!.captureCapability, isNotNull);

      api.listResult = [_aggregate(revision: 2)];
      await subject(api).drain();
      expect((await local.getById(_equipmentId))!.captureCapability, isNull);
      expect(api.updateRevisions, isEmpty);
    },
  );
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

Equipment _equipment({
  String name = 'Server Equipment',
  EquipmentCaptureCapability? captureCapability,
}) => Equipment(
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
  captureCapability: captureCapability,
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
  final List<EquipmentCaptureCapability?> createdCaptureCapabilities = [];
  final List<int> updateRevisions = [];
  final List<bool> updateCaptureCapabilityIncluded = [];
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
    createdCaptureCapabilities.add(equipment.captureCapability);
    return _aggregate(equipment: equipment, revision: 1);
  }

  @override
  Future<EquipmentRemoteAggregate> update(
    Equipment equipment, {
    required int expectedRevision,
    bool includeCaptureCapability = true,
  }) async {
    updateRevisions.add(expectedRevision);
    updateCaptureCapabilityIncluded.add(includeCaptureCapability);
    if (updateError != null) throw updateError!;
    EquipmentCaptureCapability? serverCapability;
    for (final item in listResult) {
      if (item.equipment.id == equipment.id) {
        serverCapability = item.equipment.captureCapability;
        break;
      }
    }
    final canonical = !includeCaptureCapability && serverCapability != null
        ? equipment.copyWith(captureCapability: serverCapability)
        : equipment;
    return _aggregate(equipment: canonical, revision: expectedRevision + 1);
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

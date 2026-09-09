import 'package:astro_journal/core/constants/database_constants.dart';
import 'package:astro_journal/data/database/app_database.dart';
import 'package:astro_journal/data/datasources/observation_site_local_datasource.dart';
import 'package:astro_journal/data/models/blocked_azimuth_range.dart';
import 'package:astro_journal/data/models/horizon_point.dart';
import 'package:astro_journal/data/models/imaging_suitability_assessment.dart';
import 'package:astro_journal/data/models/observation_site.dart';
import 'package:astro_journal/data/models/observation_site_remote.dart';
import 'package:astro_journal/data/models/tc_backend_change.dart';
import 'package:astro_journal/data/repositories/observation_site_repository_impl.dart';
import 'package:astro_journal/features/observation_site/viewmodel/active_observation_site_view_model.dart';
import 'package:astro_journal/services/observation_site_sync_coordinator.dart';
import 'package:astro_journal/services/tc_backend_observation_site_service.dart';
import 'package:astro_journal/services/tc_backend_settings_service.dart';
import 'package:astro_journal/services/tc_backend_sync_gate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late ObservationSiteLocalDataSource local;
  late TcBackendSettingsService settings;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await AppDatabase.createForTest(db, DatabaseConstants.databaseVersion);
    local = ObservationSiteLocalDataSource(
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

  tearDown(() => db.close());

  ObservationSiteSyncCoordinator subject(
    _FakeRemote remote, {
    Future<void> Function()? onCollectionChanged,
    Future<void> Function()? onObservingConditionsChanged,
    Future<bool> Function(String)? canReferenceDefaultEquipment,
    Future<bool> Function(String)? hasLocalDefaultEquipment,
  }) => ObservationSiteSyncCoordinator(
    remoteApi: remote,
    localDataSource: local,
    settingsService: settings,
    syncGate: TcBackendSyncGate(),
    onCollectionChanged: onCollectionChanged,
    onObservingConditionsChanged: onObservingConditionsChanged,
    canReferenceDefaultEquipment: canReferenceDefaultEquipment,
    hasLocalDefaultEquipment: hasLocalDefaultEquipment,
  );

  test('server list reconciles canonical aggregate into local cache', () async {
    final remote = _FakeRemote()..items[_siteId] = _remote(revision: 3);

    await subject(remote).drain();

    expect((await local.get(_siteId))?.name, 'Server site');
    expect((await local.getSyncMetadata(_siteId))?.serverRevision, 3);
  });

  test(
    'local-only site bootstraps once and UUID replay stays idempotent',
    () async {
      await local.create(_site(name: 'Local site'));
      final remote = _FakeRemote();
      final coordinator = subject(remote);

      await coordinator.drain();
      await coordinator.drain();

      expect(remote.createCalls, [_siteId]);
      expect(remote.items, hasLength(1));
      expect((await local.getSyncMetadata(_siteId))?.serverRevision, 1);
    },
  );

  test('update and delete send the durable expected revision', () async {
    final remote = _FakeRemote()..items[_siteId] = _remote(revision: 4);
    await local.applyRemoteAggregate(remote.items[_siteId]!);
    await local.update(_site(name: 'Local edit'));

    await subject(remote).drain();

    expect(remote.updateRevisions, [4]);
    expect((await local.getSyncMetadata(_siteId))?.serverRevision, 5);

    await local.delete(_siteId);
    await subject(remote).drain();

    expect(remote.deleteRevisions, [5]);
    expect(await local.get(_siteId), isNull);
    expect((await local.getSyncMetadata(_siteId))?.serverDeletedAt, isNotNull);
  });

  test(
    'horizon aggregate and circular blocked range survive round trip',
    () async {
      final remote = _FakeRemote()..items[_siteId] = _remote(revision: 2);

      await subject(remote).drain();
      final restored = await local.get(_siteId);

      expect(restored?.horizonPoints.single.minAltitude, 15);
      expect(restored?.blockedAzimuthRanges.single.startAzimuth, 350);
      expect(restored?.blockedAzimuthRanges.single.endAzimuth, 20);
      expect(restored?.blockedAzimuthRanges.single.contains(5), isTrue);
    },
  );

  test('offline and undeployed 404 preserve the local cache', () async {
    await local.create(_site());
    for (final type in [
      ObservationSiteRemoteErrorType.network,
      ObservationSiteRemoteErrorType.notFound,
    ]) {
      final remote = _FakeRemote()..listFailure = type;

      await subject(remote).drain();

      expect(await local.get(_siteId), isNotNull);
    }
  });

  test(
    'pending mutation survives datasource and coordinator restart',
    () async {
      await local.create(_site());
      final restartedLocal = ObservationSiteLocalDataSource(
        database: db,
        syncMutationsEnabled: true,
      );
      final remote = _FakeRemote();
      final restarted = ObservationSiteSyncCoordinator(
        remoteApi: remote,
        localDataSource: restartedLocal,
        settingsService: settings,
        syncGate: TcBackendSyncGate(),
      );

      await restarted.drain();

      expect(remote.createCalls, [_siteId]);
      final outbox = await db.query(
        DatabaseConstants.tableObservationSiteSyncOutbox,
      );
      expect(outbox.single['state'], 'SYNCED');
    },
  );

  test('retryable sync failure keeps the local mutation durable', () async {
    await local.create(_site(name: 'Offline edit'));
    final remote = _FakeRemote()
      ..createFailure = ObservationSiteRemoteErrorType.network;

    await subject(remote).drain();

    expect((await local.get(_siteId))?.name, 'Offline edit');
    final outbox = await db.query(
      DatabaseConstants.tableObservationSiteSyncOutbox,
    );
    expect(outbox.single['state'], 'FAILED');
    expect(outbox.single['retry_count'], 1);
    expect(outbox.single['payload_json'], isNotNull);
  });

  test(
    'revision conflict preserves local edit and stores server snapshot',
    () async {
      final remote = _FakeRemote()..items[_siteId] = _remote(revision: 2);
      await local.applyRemoteAggregate(remote.items[_siteId]!);
      await local.update(_site(name: 'Unsynced local edit'));
      remote.conflictOnUpdate = true;
      remote.items[_siteId] = _remote(revision: 3, name: 'Other device edit');

      await subject(remote).drain();

      expect((await local.get(_siteId))?.name, 'Unsynced local edit');
      final outbox = await db.query(
        DatabaseConstants.tableObservationSiteSyncOutbox,
        where: "state = 'CONFLICT'",
      );
      expect(outbox, hasLength(1));
      expect(outbox.single['server_payload_json'], isNotNull);
    },
  );

  test(
    'remote deletion falls active selection back to current location',
    () async {
      final initial = _remote(revision: 1);
      await local.applyRemoteAggregate(initial);
      final repository = ObservationSiteRepositoryImpl(dataSource: local);
      final active = ActiveObservationSiteViewModel(repository);
      await active.load();
      await active.selectSavedSite((await local.get(_siteId))!);
      expect(active.active.selectedSiteId, _siteId);

      await subject(
        _FakeRemote(),
        onCollectionChanged: () => active.load(force: true),
      ).drain();

      expect(active.active.isCurrentLocation, isTrue);
    },
  );

  test(
    'change feed CREATE UPDATE DELETE applies revisions and tombstone',
    () async {
      final remote = _FakeRemote()..items[_siteId] = _remote(revision: 1);
      final coordinator = subject(remote);

      await coordinator.applyChange(
        _change(TcBackendChangeOperation.create, revision: 1),
      );
      remote.items[_siteId] = _remote(revision: 2, name: 'Updated remotely');
      await coordinator.applyChange(
        _change(TcBackendChangeOperation.update, revision: 2),
      );
      await coordinator.applyChange(
        _change(
          TcBackendChangeOperation.delete,
          revision: 3,
          deletedAt: DateTime.utc(2026, 9, 9),
        ),
      );

      expect(await local.get(_siteId), isNull);
      expect((await local.getSyncMetadata(_siteId))?.serverRevision, 3);
    },
  );

  test('remote tombstone preserves a pending local edit as conflict', () async {
    await local.applyRemoteAggregate(_remote(revision: 1));
    await local.update(_site(name: 'Pending local edit'));

    await subject(_FakeRemote()).applyChange(
      _change(
        TcBackendChangeOperation.delete,
        revision: 2,
        deletedAt: DateTime.utc(2026, 9, 9),
      ),
    );

    expect((await local.get(_siteId))?.name, 'Pending local edit');
    expect(
      (await local.getSyncMetadata(_siteId))?.serverDeletedAt,
      DateTime.utc(2026, 9, 9),
    );
    final conflicts = await db.query(
      DatabaseConstants.tableObservationSiteSyncOutbox,
      where: "state = 'CONFLICT'",
    );
    expect(conflicts, hasLength(1));
  });

  test(
    'metadata-only revision does not invalidate observing conditions',
    () async {
      await local.applyRemoteAggregate(_remote(revision: 1));
      var collectionChanges = 0;
      var observingChanges = 0;
      final remote = _FakeRemote()..items[_siteId] = _remote(revision: 2);

      await subject(
        remote,
        onCollectionChanged: () async => collectionChanges++,
        onObservingConditionsChanged: () async => observingChanges++,
      ).drain();

      expect(collectionChanges, 0);
      expect(observingChanges, 0);
      expect((await local.getSyncMetadata(_siteId))?.serverRevision, 2);
    },
  );

  test('meaningful remote horizon change invalidates observers once', () async {
    await local.applyRemoteAggregate(_remote(revision: 1));
    var collectionChanges = 0;
    var observingChanges = 0;
    final changed = _remote(revision: 2, minAltitude: 35);
    final remote = _FakeRemote()..items[_siteId] = changed;

    await subject(
      remote,
      onCollectionChanged: () async => collectionChanges++,
      onObservingConditionsChanged: () async => observingChanges++,
    ).drain();

    expect(collectionChanges, 1);
    expect(observingChanges, 1);
    expect((await local.get(_siteId))?.horizonPoints.single.minAltitude, 35);
  });

  test(
    'repository reads remain local and require no backend request',
    () async {
      await local.applyRemoteAggregate(_remote(revision: 1));
      final repository = ObservationSiteRepositoryImpl(dataSource: local);

      final sites = await repository.list();

      expect(sites.single.id, _siteId);
    },
  );

  test(
    'server-cleared equipment default replaces the local reference',
    () async {
      const equipmentId = '22222222-2222-4222-8222-222222222222';
      await local.applyRemoteAggregate(
        _remote(revision: 1, defaultEquipmentId: equipmentId),
      );
      final remote = _FakeRemote()..items[_siteId] = _remote(revision: 2);

      await subject(
        remote,
        canReferenceDefaultEquipment: (_) async => true,
        hasLocalDefaultEquipment: (_) async => true,
      ).applyChange(_change(TcBackendChangeOperation.update, revision: 2));

      expect((await local.get(_siteId))?.defaultEquipmentId, isNull);
    },
  );

  test(
    'resolved legacy default equipment is queued after equipment sync',
    () async {
      const equipmentId = '22222222-2222-4222-8222-222222222222';
      final legacy = ObservationSiteLocalDataSource(database: db);
      await legacy.create(_site(defaultEquipmentId: equipmentId));
      final serverWithoutReference = _remote(revision: 1);
      await local.saveRemoteSnapshotOnly(serverWithoutReference);
      final remote = _FakeRemote()..items[_siteId] = serverWithoutReference;

      await subject(
        remote,
        canReferenceDefaultEquipment: (_) async => true,
      ).drain();

      expect(remote.updateRevisions, [1]);
      expect(remote.items[_siteId]?.site.defaultEquipmentId, equipmentId);
    },
  );
}

const _siteId = '11111111-1111-4111-8111-111111111111';

ObservationSite _site({
  String name = 'Server site',
  double minAltitude = 15,
  String? defaultEquipmentId,
}) => ObservationSite(
  id: _siteId,
  name: name,
  latitude: 37.25,
  longitude: 128.25,
  bortle: 3,
  sqm: 21.3,
  brightnessGrade: 'dark',
  trackingMode: TrackingMode.altAz,
  defaultEquipmentId: defaultEquipmentId,
  defaultMinAltitude: 20,
  createdAt: DateTime.utc(2026, 9, 1),
  updatedAt: DateTime.utc(2026, 9, 2),
  horizonPoints: [
    HorizonPoint(
      id: '33333333-3333-4333-8333-333333333333',
      observationSiteId: _siteId,
      azimuth: 0,
      minAltitude: minAltitude,
      source: HorizonDataSource.cameraScan,
    ),
  ],
  blockedAzimuthRanges: const [
    BlockedAzimuthRange(
      id: '44444444-4444-4444-8444-444444444444',
      observationSiteId: _siteId,
      startAzimuth: 350,
      endAzimuth: 20,
    ),
  ],
);

ObservationSiteRemoteAggregate _remote({
  required int revision,
  String name = 'Server site',
  double minAltitude = 15,
  String? defaultEquipmentId,
}) => ObservationSiteRemoteAggregate(
  site: _site(
    name: name,
    minAltitude: minAltitude,
    defaultEquipmentId: defaultEquipmentId,
  ),
  revision: revision,
);

TcBackendChange _change(
  TcBackendChangeOperation operation, {
  required int revision,
  DateTime? deletedAt,
}) => TcBackendChange(
  resourceType: 'ObservationSite',
  resourceId: _siteId,
  operation: operation,
  revision: revision,
  deletedAt: deletedAt,
);

class _FakeRemote implements ObservationSiteRemoteApi {
  final Map<String, ObservationSiteRemoteAggregate> items = {};
  final List<String> createCalls = [];
  final List<int> updateRevisions = [];
  final List<int> deleteRevisions = [];
  ObservationSiteRemoteErrorType? listFailure;
  ObservationSiteRemoteErrorType? createFailure;
  bool conflictOnUpdate = false;

  @override
  Future<List<ObservationSiteRemoteAggregate>> list() async {
    final failure = listFailure;
    if (failure != null) {
      throw ObservationSiteRemoteException(
        type: failure,
        message: 'unavailable',
        statusCode: failure == ObservationSiteRemoteErrorType.notFound
            ? 404
            : null,
      );
    }
    return items.values.toList(growable: false);
  }

  @override
  Future<ObservationSiteRemoteAggregate> get(String siteId) async =>
      items[siteId]!;

  @override
  Future<ObservationSiteRemoteAggregate> create(ObservationSite site) async {
    createCalls.add(site.id);
    final failure = createFailure;
    if (failure != null) {
      throw ObservationSiteRemoteException(
        type: failure,
        message: 'create unavailable',
      );
    }
    return items.putIfAbsent(
      site.id,
      () => ObservationSiteRemoteAggregate(site: site, revision: 1),
    );
  }

  @override
  Future<ObservationSiteRemoteAggregate> update(
    ObservationSite site, {
    required int expectedRevision,
  }) async {
    updateRevisions.add(expectedRevision);
    final current = items[site.id]!;
    if (conflictOnUpdate || current.revision != expectedRevision) {
      throw ObservationSiteRemoteException(
        type: ObservationSiteRemoteErrorType.conflict,
        message: 'REVISION_CONFLICT',
        statusCode: 409,
        currentRevision: current.revision,
      );
    }
    final result = ObservationSiteRemoteAggregate(
      site: site.copyWith(updatedAt: DateTime.utc(2026, 9, 9)),
      revision: current.revision + 1,
    );
    items[site.id] = result;
    return result;
  }

  @override
  Future<ObservationSiteRemoteDeleteResult> delete(
    String siteId, {
    required int expectedRevision,
  }) async {
    deleteRevisions.add(expectedRevision);
    final current = items.remove(siteId)!;
    return ObservationSiteRemoteDeleteResult(
      siteId: siteId,
      revision: current.revision + 1,
      deletedAt: DateTime.utc(2026, 9, 9),
    );
  }
}

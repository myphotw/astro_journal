import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/data/datasources/gallery_record_link_datasource.dart';
import 'package:astro_journal/data/models/catalog_candidate.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/exif_info.dart';
import 'package:astro_journal/data/models/gallery_item.dart';
import 'package:astro_journal/data/repositories/catalog_repository.dart';
import 'package:astro_journal/data/repositories/gallery_repository.dart';
import 'package:astro_journal/data/repositories/gallery_shooting_record_repository_adapter.dart';
import 'package:astro_journal/data/models/shooting_record.dart';
import 'package:astro_journal/data/repositories/shooting_record_repository.dart';
import 'package:astro_journal/data/repositories/sync_outbox_repository.dart';
import 'package:astro_journal/features/gallery/viewmodel/gallery_view_model.dart';
import 'package:astro_journal/features/stats/viewmodel/stats_view_model.dart';
import 'package:astro_journal/services/catalog_search_service.dart';
import 'package:astro_journal/services/catalog_capture_projection_service.dart';
import 'package:astro_journal/services/stats_analytics_service.dart';
import 'package:astro_journal/services/tc_backend_sync_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final capturedAt = DateTime.utc(2026, 8, 7, 1, 2, 3);
  const catalog = [
    CatalogObject(
      id: 'M42',
      number: 42,
      catalog: CatalogType.messier,
      name: 'Orion Nebula',
      type: 'Nebula',
      constellation: 'Orion',
      ra: '-',
      dec: '-',
      magnitude: '-',
    ),
    CatalogObject(
      id: 'M13',
      number: 13,
      catalog: CatalogType.messier,
      name: 'Hercules Cluster',
      type: 'Cluster',
      constellation: 'Hercules',
      ra: '-',
      dec: '-',
      magnitude: '-',
    ),
  ];

  _Harness harness({
    required GallerySnapshot snapshot,
    List<ShootingRecord> local = const [],
    Map<String, String> links = const {},
    List<CatalogObject> catalogObjects = catalog,
    GalleryItem? detail,
    _FakeOutbox? outbox,
    _FakeDrain? drain,
    bool enableCaptureProjection = false,
    void Function()? onRecordsChanged,
  }) {
    final gallery = _FakeGalleryRepository(snapshot, detail: detail);
    final localRepository = _FakeLocalRepository(local);
    final catalogRepository = _FakeCatalogRepository(catalogObjects);
    final recordLinks = _FakeLinks(links);
    final captureProjection = enableCaptureProjection
        ? CatalogCaptureProjectionService(
            catalogRepository: catalogRepository,
            localRecords: localRepository,
            galleryRepository: gallery,
            recordLinks: recordLinks,
          )
        : null;
    return _Harness(
      gallery,
      localRepository,
      GalleryShootingRecordRepositoryAdapter(
        galleryRepository: gallery,
        localRepository: localRepository,
        catalogRepository: catalogRepository,
        projectionMapper: GalleryObservationProjectionMapper(
          CatalogSearchService(),
        ),
        linkDataSource: recordLinks,
        syncOutboxRepository: outbox,
        syncCoordinator: drain,
        catalogCaptureProjection: captureProjection,
        onRecordsChanged: onRecordsChanged,
      ),
      catalogRepository,
      outbox,
      captureProjection,
    );
  }

  test('record_id revision and catalog_object_id form projection identity', () {
    final projection =
        GalleryObservationProjectionMapper(CatalogSearchService()).toProjection(
          _item('record-1', 'sha-1', 'M42', capturedAt),
          catalog: catalog,
        );

    expect(projection.backendRecordId, 'record-1');
    expect(projection.revision, 7);
    expect(projection.catalogObjectId, 'M42');
    expect(projection.targetName, contains('Orion'));
    expect(projection.thumbnailUrl, '/thumbnail/sha-1');
    expect(projection.previewUrl, '/preview/sha-1');
    expect(projection.originalUrl, '/original/sha-1');
  });

  test(
    'remote-only M54 drives capture projection and Catalog photo source',
    () async {
      const m54 = CatalogObject(
        id: 'M54',
        number: 54,
        catalog: CatalogType.messier,
        name: 'Sagittarius Cluster',
        type: 'Cluster',
        constellation: 'Sagittarius',
        ra: '-',
        dec: '-',
        magnitude: '-',
      );
      final result = harness(
        snapshot: _remoteSnapshot([
          _item('record-m54', 'sha-m54', 'M54', capturedAt),
        ]),
        catalogObjects: const [m54],
        enableCaptureProjection: true,
      );

      final projection = await result.captureProjection!.reconcileObject('M54');
      final records = await result.adapter.getByCelestialObjectId('M54');

      expect(projection.captured, isTrue);
      expect(projection.photoCount, 1);
      expect(records, hasLength(1));
      expect(records.single.thumbnailUrl, '/thumbnail/sha-m54');
      expect(records.single.photoUri, '/preview/sha-m54');
    },
  );

  test('linked local and remote M54 photo is exposed once', () async {
    const m54 = CatalogObject(
      id: 'M54',
      number: 54,
      catalog: CatalogType.messier,
      name: 'Sagittarius Cluster',
      type: 'Cluster',
      constellation: 'Sagittarius',
      ra: '-',
      dec: '-',
      magnitude: '-',
    );
    final result = harness(
      snapshot: _remoteSnapshot([
        _item('record-m54', 'sha-m54', 'M54', capturedAt),
      ]),
      local: [_local('local-m54', 'M54', capturedAt)],
      links: const {'record-m54': 'local-m54'},
      catalogObjects: const [m54],
    );

    final records = await result.adapter.getByCelestialObjectId('M54');

    expect(records, hasLength(1));
    expect(records.single.id, 'local-m54');
    expect(records.single.backendRecordId, 'record-m54');
  });

  test(
    'last remote M54 delete clears photo source and captured flag',
    () async {
      const m54 = CatalogObject(
        id: 'M54',
        number: 54,
        catalog: CatalogType.messier,
        name: 'Sagittarius Cluster',
        type: 'Cluster',
        constellation: 'Sagittarius',
        ra: '-',
        dec: '-',
        magnitude: '-',
      );
      final result = harness(
        snapshot: _remoteSnapshot([
          _item('record-m54', 'sha-m54', 'M54', capturedAt),
        ]),
        catalogObjects: const [m54],
        outbox: _FakeOutbox(),
        enableCaptureProjection: true,
      );
      final record = (await result.adapter.getAll()).single;

      await result.adapter.delete(record.id);

      final projection = await result.captureProjection!.reconcileObject('M54');
      expect(await result.adapter.getByCelestialObjectId('M54'), isEmpty);
      expect(projection.captured, isFalse);
      expect(projection.photoCount, 0);
    },
  );

  test(
    'unmatched catalog item is retained with canonical fallback name',
    () async {
      final item = _item('record-x', 'sha-x', 'CUSTOM-1', capturedAt);
      final result = harness(
        snapshot: _remoteSnapshot([item]),
        catalogObjects: const [],
      );
      final records = await result.adapter.getAll();

      expect(records.single.backendRecordId, 'record-x');
      expect(records.single.celestialObjectId, 'CUSTOM-1');
      expect(records.single.remoteTargetName, 'CUSTOM-1');

      final viewModel = GalleryViewModel(
        result.adapter,
        result.catalog,
        CatalogSearchService(),
      );
      await viewModel.load();
      expect(viewModel.filteredRecords, hasLength(1));
      expect(viewModel.targetGroups, hasLength(1));
    },
  );

  test('exact outbox record link merges canonical and local fields', () async {
    final local = _local('local-1', 'M42', capturedAt, filename: 'same.fit')
        .copyWith(
          exif: ExifInfo.placeholder(
            filename: 'same.fit',
          ).copyWith(locationName: 'Old local site', lat: 1, lng: 2),
        );
    final remote = _item(
      'record-1',
      'sha-1',
      'M42',
      capturedAt.add(const Duration(hours: 1)),
      filename: 'same.fit',
      favorite: true,
      representative: true,
      memo: 'server memo',
    );
    final result = await harness(
      snapshot: _remoteSnapshot([remote]),
      local: [local],
      links: const {'record-1': 'local-1'},
    ).adapter.getAll();

    final record = result.single;
    expect(record.id, 'local-1');
    expect(record.backendRecordId, 'record-1');
    expect(record.backendRevision, 7);
    expect(record.photoUri, '/local/local-1.jpg');
    expect(record.memo, 'server memo');
    expect(record.isFavorite, isTrue);
    expect(record.isRepresentative, isTrue);
    expect(record.capturedAt, remote.capturedAt);
    expect(record.location, 'Jeju');
    expect(record.exif?.locationName, 'Jeju');
  });

  test(
    'same filename is not used as canonical remote merge evidence',
    () async {
      final local = _local('local-1', 'M42', capturedAt, filename: 'same.fit');
      final remote = _item(
        'record-1',
        'sha-1',
        'M42',
        capturedAt,
        filename: 'same.fit',
      );
      final result = await harness(
        snapshot: _remoteSnapshot([remote]),
        local: [local],
      ).adapter.getAll();

      expect(result, hasLength(2));
      expect(result.any((record) => record.id == 'remote:record-1'), isTrue);
      expect(result.any((record) => record.id == 'local-1'), isTrue);
    },
  );

  test('Backend OFF cache precedes local SQLite fallback', () async {
    final result = await harness(
      snapshot: GallerySnapshot(
        items: [_item('cached', 'sha-c', 'M42', capturedAt)],
        source: GallerySnapshotSource.cache,
        backendEnabled: false,
      ),
      local: [_local('local', 'M13', capturedAt)],
    ).adapter.getAll();

    expect(result.first.backendRecordId, 'cached');
    expect(result.last.id, 'local');
  });

  test('remote failure uses cache before local-only records', () async {
    final result = await harness(
      snapshot: GallerySnapshot(
        items: [_item('stale', 'sha-s', 'M42', capturedAt)],
        source: GallerySnapshotSource.cache,
        backendEnabled: true,
        remoteFailed: true,
      ),
      local: [_local('local', 'M13', capturedAt)],
    ).adapter.getAll();

    expect(result.first.backendRecordId, 'stale');
    expect(result.last.id, 'local');
  });

  test('no cache falls back to existing SQLite Gallery records', () async {
    final local = _local('local', 'M13', capturedAt);
    final result = await harness(
      snapshot: const GallerySnapshot(
        items: [],
        source: GallerySnapshotSource.none,
        backendEnabled: true,
        remoteFailed: true,
      ),
      local: [local],
    ).adapter.getAll();

    expect(result.single, same(local));
  });

  test('remote detail is requested using record_id', () async {
    final listItem = _item('record-1', 'sha-1', 'M42', capturedAt);
    final detail = _item(
      'record-1',
      'sha-1',
      'M42',
      capturedAt,
      memo: 'detail memo',
    );
    final result = harness(
      snapshot: _remoteSnapshot([listItem]),
      detail: detail,
    );
    final listRecord = (await result.adapter.getAll()).first;

    final detailed = await result.adapter.getById(listRecord.id);

    expect(result.gallery.detailIds, ['record-1']);
    expect(detailed?.memo, 'detail memo');
  });

  test(
    'remote-only detail restores common file identity separately from record id',
    () async {
      final listItem = _item('record-1', 'sha-1', 'M42', capturedAt);
      final detail = _item(
        'record-1',
        'sha-1',
        'M42',
        capturedAt,
        commonFileId: 178,
      );
      final first = harness(
        snapshot: _remoteSnapshot([listItem]),
        detail: detail,
      );
      final remoteOnly = (await first.adapter.getAll()).single;
      expect(remoteOnly.id, 'remote:record-1');
      expect(remoteOnly.commonFileId, isNull);
      await first.adapter.update(remoteOnly);

      final recreated = GalleryShootingRecordRepositoryAdapter(
        galleryRepository: first.gallery,
        localRepository: first.local,
        catalogRepository: first.catalog,
        projectionMapper: GalleryObservationProjectionMapper(
          CatalogSearchService(),
        ),
      );
      final restoredRemoteOnly = (await recreated.getAll()).single;

      final detailed = await recreated.getById(restoredRemoteOnly.id);

      expect(detailed?.id, 'remote:record-1');
      expect(detailed?.backendRecordId, 'record-1');
      expect(detailed?.backendFileId, 'sha-1');
      expect(detailed?.commonFileId, 178);
    },
  );

  test('Gallery search favorite and date sorting remain unchanged', () async {
    final result = harness(
      snapshot: _remoteSnapshot([
        _item('newest', 'sha-new', 'M42', capturedAt, favorite: true),
        _item(
          'oldest',
          'sha-old',
          'M13',
          capturedAt.subtract(const Duration(days: 1)),
        ),
      ]),
    );
    final viewModel = GalleryViewModel(
      result.adapter,
      result.catalog,
      CatalogSearchService(),
    );

    await viewModel.load();
    viewModel.setSearchQuery('M13');
    expect(viewModel.filteredRecords.single.backendRecordId, 'oldest');
    viewModel.clearFilters();
    viewModel.toggleFavoritesOnly();
    expect(viewModel.filteredRecords.single.backendRecordId, 'newest');
    viewModel.clearFilters();
    viewModel.setSortOrder(GallerySortOrder.oldestFirst);
    expect(viewModel.filteredRecords.first.backendRecordId, 'oldest');
  });

  test(
    'remote favorite and memo are local-first durable PATCH operations',
    () async {
      final outbox = _FakeOutbox();
      final drain = _FakeDrain();
      final result = harness(
        snapshot: _remoteSnapshot([
          _item('record-1', 'sha-1', 'M42', capturedAt),
        ]),
        outbox: outbox,
        drain: drain,
      );
      final record = (await result.adapter.getAll()).single;

      await result.adapter.update(record.copyWith(isFavorite: true));
      await result.adapter.update(
        record.copyWith(isFavorite: true, memo: 'new memo'),
      );

      expect(outbox.patches, hasLength(2));
      expect(outbox.patches.first.fields, {'favorite': true});
      expect(outbox.patches.last.fields, {'memo': 'new memo'});
      expect(result.gallery.localPatches.last['memo'], 'new memo');
      expect(drain.calls, 2);
    },
  );

  test('linked record location queues name and coordinates together', () async {
    final outbox = _FakeOutbox();
    final result = harness(
      snapshot: _remoteSnapshot([
        _item('record-1', 'sha-1', 'M42', capturedAt),
      ]),
      local: [_local('local-1', 'M42', capturedAt)],
      links: const {'record-1': 'local-1'},
      outbox: outbox,
    );
    final record = (await result.adapter.getAll()).single;
    final updated = record.copyWith(
      location: 'New site',
      exif: record.exif!.copyWith(
        locationName: 'New site',
        lat: 37.55,
        lng: 126.98,
      ),
    );

    await result.adapter.update(updated);

    expect(outbox.patches.single.fields, {
      'location_name': 'New site',
      'latitude': 37.55,
      'longitude': 126.98,
    });
  });

  test('remote-only editable metadata survives adapter recreation', () async {
    final result = harness(
      snapshot: _remoteSnapshot([
        _item('record-1', 'sha-1', 'M42', capturedAt),
      ]),
    );
    final remote = (await result.adapter.getAll()).single;

    await result.adapter.update(
      remote.copyWith(
        location: '회사 옥상',
        exif: remote.exif!.copyWith(
          exposure: '1시간',
          equipment: 'Seestar S30 Pro',
          locationName: '회사 옥상',
        ),
      ),
    );

    final recreated = GalleryShootingRecordRepositoryAdapter(
      galleryRepository: result.gallery,
      localRepository: result.local,
      catalogRepository: result.catalog,
      projectionMapper: GalleryObservationProjectionMapper(
        CatalogSearchService(),
      ),
    );
    final restored = (await recreated.getAll()).single;

    expect(restored.id, 'remote:record-1');
    expect(restored.exif?.exposure, '1시간');
    expect(restored.exif?.equipment, 'Seestar S30 Pro');
    expect(restored.exif?.locationName, 'Jeju');
  });

  test('metadata edit invalidates and reloads canonical stats', () async {
    late StatsViewModel stats;
    final local = _local('local-1', 'M42', capturedAt).copyWith(
      exif: ExifInfo.placeholder(
        filename: 'local.fit',
      ).copyWith(exposure: '30분'),
    );
    final result = harness(
      snapshot: const GallerySnapshot(
        items: [],
        source: GallerySnapshotSource.none,
        backendEnabled: false,
      ),
      local: [local],
      onRecordsChanged: () => stats.invalidateRecords(),
    );
    stats = StatsViewModel(
      result.adapter,
      result.catalog,
      StatsAnalyticsService(),
    );
    await stats.load();
    expect(stats.topTargets.single.integrationSeconds, 1800);

    await result.adapter.update(
      local.copyWith(exif: local.exif!.copyWith(exposure: '1시간')),
    );
    expect(stats.hasLoaded, isFalse);

    await stats.load();
    expect(stats.topTargets.single.integrationSeconds, 3600);
  });

  test('representative queues only the selected canonical record', () async {
    final outbox = _FakeOutbox();
    final result = harness(
      snapshot: _remoteSnapshot([
        _item('record-1', 'sha-1', 'M42', capturedAt),
        _item('record-2', 'sha-2', 'M42', capturedAt),
      ]),
      outbox: outbox,
    );
    final selected = (await result.adapter.getAll()).first;

    await result.adapter.setRepresentative(selected.id);

    expect(outbox.patches, hasLength(1));
    expect(outbox.patches.single.recordId, 'record-1');
    expect(outbox.patches.single.fields, {'representative': true});
  });

  test('remote delete updates local projection then queues DELETE', () async {
    final outbox = _FakeOutbox();
    final result = harness(
      snapshot: _remoteSnapshot([
        _item('record-1', 'sha-1', 'M42', capturedAt),
      ]),
      outbox: outbox,
    );
    final record = (await result.adapter.getAll()).single;

    await result.adapter.delete(record.id);

    expect(result.gallery.localDeletes, ['record-1']);
    expect(outbox.deletes, ['record-1']);
  });

  test(
    'local-only mutation creates no orphan PATCH and delete cancels upload',
    () async {
      final outbox = _FakeOutbox();
      final result = harness(
        snapshot: const GallerySnapshot(
          items: [],
          source: GallerySnapshotSource.none,
          backendEnabled: false,
        ),
        local: [_local('local-1', 'M42', capturedAt)],
        outbox: outbox,
      );
      final local = (await result.adapter.getAll()).single;

      await result.adapter.update(local.copyWith(memo: 'latest local value'));
      expect(outbox.patches, isEmpty);
      await result.adapter.delete(local.id);
      expect(outbox.cancelledLocalIds, ['local-1']);
    },
  );

  test('Gallery last local photo delete clears Catalog projection', () async {
    final result = harness(
      snapshot: const GallerySnapshot(
        items: [],
        source: GallerySnapshotSource.none,
        backendEnabled: false,
      ),
      local: [_local('local-1', 'M42', capturedAt)],
      enableCaptureProjection: true,
    );
    await result.captureProjection!.reconcileObject('M42');
    await result.adapter.getAll();

    await result.adapter.delete('local-1');

    expect((await result.catalog.getById('M42'))?.captured, isFalse);
  });
}

GallerySnapshot _remoteSnapshot(List<GalleryItem> items) => GallerySnapshot(
  items: items,
  source: GallerySnapshotSource.remote,
  backendEnabled: true,
);

GalleryItem _item(
  String recordId,
  String fileId,
  String catalogId,
  DateTime capturedAt, {
  String? filename,
  bool favorite = false,
  bool representative = false,
  String memo = '',
  int? commonFileId,
}) => GalleryItem(
  backendRecordId: recordId,
  revision: 7,
  catalogObjectId: catalogId,
  capturedAt: capturedAt,
  favorite: favorite,
  representative: representative,
  backendFileId: fileId,
  commonFileId: commonFileId,
  thumbnailUrl: '/thumbnail/$fileId',
  previewUrl: '/preview/$fileId',
  originalUrl: '/original/$fileId',
  originalFilename: filename,
  location: 'Jeju',
  memo: memo,
);

ShootingRecord _local(
  String id,
  String catalogId,
  DateTime capturedAt, {
  String? filename,
}) => ShootingRecord(
  id: id,
  celestialObjectId: catalogId,
  capturedAt: capturedAt,
  photoUri: '/local/$id.jpg',
  originalFilename: filename,
  createdAt: capturedAt,
);

class _Harness {
  const _Harness(
    this.gallery,
    this.local,
    this.adapter,
    this.catalog,
    this.outbox,
    this.captureProjection,
  );
  final _FakeGalleryRepository gallery;
  final _FakeLocalRepository local;
  final GalleryShootingRecordRepositoryAdapter adapter;
  final _FakeCatalogRepository catalog;
  final _FakeOutbox? outbox;
  final CatalogCaptureProjectionService? captureProjection;
}

class _FakeGalleryRepository implements GalleryRepository {
  _FakeGalleryRepository(this.snapshot, {this.detail});
  GallerySnapshot snapshot;
  final GalleryItem? detail;
  final List<String> detailIds = [];
  final List<Map<String, Object?>> localPatches = [];
  final List<String> localDeletes = [];

  @override
  Future<GallerySnapshot> getSnapshot({bool forceRefresh = false}) async =>
      snapshot;

  @override
  Future<List<GalleryItem>> getAll({bool forceRefresh = false}) async =>
      snapshot.items;

  @override
  Future<GalleryItem?> getById(
    String backendRecordId, {
    bool forceRefresh = false,
  }) async {
    detailIds.add(backendRecordId);
    return detail;
  }

  @override
  Future<void> applyLocalPatch(
    String backendRecordId,
    Map<String, Object?> fields, {
    int? revision,
  }) async {
    localPatches.add({'record_id': backendRecordId, ...fields});
  }

  @override
  Future<void> applyLocalDelete(String backendRecordId) async {
    localDeletes.add(backendRecordId);
    snapshot = GallerySnapshot(
      items: snapshot.items
          .where((item) => item.backendRecordId != backendRecordId)
          .toList(),
      source: snapshot.source,
      backendEnabled: snapshot.backendEnabled,
      remoteFailed: snapshot.remoteFailed,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLinks implements GalleryRecordLinkDataSource {
  const _FakeLinks(this.links);
  final Map<String, String> links;

  @override
  Future<Map<String, String>> localIdsByBackendRecordId() async => links;
}

class _FakeLocalRepository implements ShootingRecordRepository {
  _FakeLocalRepository(List<ShootingRecord> records)
    : records = List<ShootingRecord>.from(records);
  final List<ShootingRecord> records;

  @override
  Future<List<ShootingRecord>> getAll() async => records;

  @override
  Future<ShootingRecord?> getById(String id) async {
    for (final record in records) {
      if (record.id == id) return record;
    }
    return null;
  }

  @override
  Future<void> save(ShootingRecord record) async {
    final index = records.indexWhere((item) => item.id == record.id);
    if (index == -1) {
      records.add(record);
    } else {
      records[index] = record;
    }
  }

  @override
  Future<void> update(ShootingRecord record) async {
    final index = records.indexWhere((item) => item.id == record.id);
    if (index >= 0) records[index] = record;
  }

  @override
  Future<void> delete(String id) async {
    records.removeWhere((record) => record.id == id);
  }

  @override
  Future<void> setRepresentative(String recordId) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PatchCall {
  const _PatchCall(this.recordId, this.revision, this.fields);
  final String recordId;
  final int revision;
  final Map<String, Object?> fields;
}

class _FakeOutbox implements SyncOutboxRepository {
  final List<_PatchCall> patches = [];
  final List<String> deletes = [];
  final List<String> cancelledLocalIds = [];

  @override
  Future<void> enqueueRecordPatch({
    required String backendRecordId,
    required int expectedRevision,
    required Map<String, Object?> fields,
    String? localRecordId,
  }) async {
    patches.add(_PatchCall(backendRecordId, expectedRevision, fields));
  }

  @override
  Future<void> enqueueRecordDelete({
    required String backendRecordId,
    String? localRecordId,
  }) async {
    deletes.add(backendRecordId);
  }

  @override
  Future<void> cancelPendingUpload(String localRecordId) async {
    cancelledLocalIds.add(localRecordId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDrain implements TcBackendDrainRunner {
  int calls = 0;

  @override
  Future<void> drain() async {
    calls++;
  }
}

class _FakeCatalogRepository implements CatalogRepository {
  _FakeCatalogRepository(this.objects);
  List<CatalogObject> objects;

  @override
  Future<List<CatalogObject>> getAll({bool listOnly = true}) async => objects;

  @override
  Future<CatalogObject?> getById(String id) async {
    for (final object in objects) {
      if (object.id == id) return object;
    }
    return null;
  }

  @override
  Future<List<CatalogObject>> getByCatalog(CatalogType type) async =>
      objects.where((object) => object.catalog == type).toList();

  @override
  Future<List<CatalogObject>> search(String query, {int limit = 50}) async =>
      objects.where((object) => object.id.contains(query)).take(limit).toList();

  @override
  Future<List<CatalogCandidate>> findNearbyObjects({
    required double raDeg,
    required double decDeg,
    required double radiusDeg,
  }) async => const [];

  @override
  Future<List<CatalogObject>> findObjectsInPhotoField({
    required double centerRaDeg,
    required double centerDecDeg,
    required double fovWidthDeg,
    required double fovHeightDeg,
    required double rotationDeg,
  }) async => const [];

  @override
  Future<void> delete(String id) async {}
  @override
  Future<void> insert(CatalogObject object) async {}
  @override
  Future<void> updateCaptured(
    String id, {
    required bool captured,
    String? capturedDate,
  }) async {
    objects = [
      for (final object in objects)
        if (object.id == id)
          CatalogObject(
            id: object.id,
            number: object.number,
            catalog: object.catalog,
            name: object.name,
            type: object.type,
            constellation: object.constellation,
            ra: object.ra,
            dec: object.dec,
            magnitude: object.magnitude,
            captured: captured,
            capturedDate: capturedDate,
          )
        else
          object,
    ];
  }
}

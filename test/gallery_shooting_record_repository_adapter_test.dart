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
import 'package:astro_journal/features/gallery/viewmodel/gallery_view_model.dart';
import 'package:astro_journal/services/catalog_search_service.dart';
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
  }) {
    final gallery = _FakeGalleryRepository(snapshot, detail: detail);
    final localRepository = _FakeLocalRepository(local);
    final catalogRepository = _FakeCatalogRepository(catalogObjects);
    return _Harness(
      gallery,
      GalleryShootingRecordRepositoryAdapter(
        galleryRepository: gallery,
        localRepository: localRepository,
        catalogRepository: catalogRepository,
        projectionMapper: GalleryObservationProjectionMapper(
          CatalogSearchService(),
        ),
        linkDataSource: _FakeLinks(links),
      ),
      catalogRepository,
    );
  }

  test('record_id revision and catalog_object_id form projection identity', () {
    final projection = GalleryObservationProjectionMapper(
      CatalogSearchService(),
    ).toProjection(
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

  test('unmatched catalog item is retained with canonical fallback name', () async {
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
  });

  test('exact outbox record link merges canonical and local fields', () async {
    final local = _local(
      'local-1',
      'M42',
      capturedAt,
      filename: 'same.fit',
    ).copyWith(
      exif: ExifInfo.placeholder(filename: 'same.fit').copyWith(
        locationName: 'Old local site',
        lat: 1,
        lng: 2,
      ),
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

  test('same filename is not used as canonical remote merge evidence', () async {
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
  });

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

  test('Gallery search favorite and date sorting remain unchanged', () async {
    final result = harness(
      snapshot: _remoteSnapshot([
        _item(
          'newest',
          'sha-new',
          'M42',
          capturedAt,
          favorite: true,
        ),
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
}) => GalleryItem(
  backendRecordId: recordId,
  revision: 7,
  catalogObjectId: catalogId,
  capturedAt: capturedAt,
  favorite: favorite,
  representative: representative,
  backendFileId: fileId,
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
  const _Harness(this.gallery, this.adapter, this.catalog);
  final _FakeGalleryRepository gallery;
  final GalleryShootingRecordRepositoryAdapter adapter;
  final _FakeCatalogRepository catalog;
}

class _FakeGalleryRepository implements GalleryRepository {
  _FakeGalleryRepository(this.snapshot, {this.detail});
  final GallerySnapshot snapshot;
  final GalleryItem? detail;
  final List<String> detailIds = [];

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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLinks implements GalleryRecordLinkDataSource {
  const _FakeLinks(this.links);
  final Map<String, String> links;

  @override
  Future<Map<String, String>> localIdsByBackendRecordId() async => links;
}

class _FakeLocalRepository implements ShootingRecordRepository {
  _FakeLocalRepository(this.records);
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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCatalogRepository implements CatalogRepository {
  _FakeCatalogRepository(this.objects);
  final List<CatalogObject> objects;

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
  }) async {}
}

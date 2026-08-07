import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/data/models/catalog_candidate.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/gallery_item.dart';
import 'package:astro_journal/data/models/gallery_observation_projection.dart';
import 'package:astro_journal/data/models/shooting_record.dart';
import 'package:astro_journal/data/repositories/catalog_repository.dart';
import 'package:astro_journal/data/repositories/gallery_repository.dart';
import 'package:astro_journal/data/repositories/gallery_shooting_record_repository_adapter.dart';
import 'package:astro_journal/data/repositories/shooting_record_repository.dart';
import 'package:astro_journal/features/gallery/viewmodel/gallery_view_model.dart';
import 'package:astro_journal/services/catalog_search_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 8, 7, 12);
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

  GalleryShootingRecordRepositoryAdapter adapter({
    required GallerySnapshot snapshot,
    List<ShootingRecord> local = const [],
  }) => GalleryShootingRecordRepositoryAdapter(
    galleryRepository: _FakeGalleryRepository(snapshot),
    localRepository: _FakeLocalRepository(local),
    catalogRepository: _FakeCatalogRepository(catalog),
    projectionMapper: GalleryObservationProjectionMapper(
      CatalogSearchService(),
    ),
    now: () => now,
  );

  test('GalleryItem converts to ObservationProjection fields', () {
    final projection = GalleryObservationProjection.fromGalleryItem(
      GalleryItem(
        backendFileId: 'sha-1',
        thumbnailUrl: 'https://backend/thumb',
        previewUrl: 'https://backend/preview',
        originalUrl: 'https://backend/original',
        capturedAt: now,
        favorite: true,
        location: 'Jeju',
        targetName: 'M42',
        catalogObjectId: 'M42',
        syncState: 'SYNCED',
      ),
      fallbackTime: now.subtract(const Duration(days: 1)),
    );

    expect(projection.backendFileId, 'sha-1');
    expect(projection.thumbnailUrl, 'https://backend/thumb');
    expect(projection.previewUrl, 'https://backend/preview');
    expect(projection.originalUrl, 'https://backend/original');
    expect(projection.captureDatetime, now);
    expect(projection.favorite, isTrue);
    expect(projection.location, 'Jeju');
    expect(projection.targetName, 'M42');
    expect(projection.syncState, 'SYNCED');
  });

  test('backend ON remote snapshot is projected for Gallery UI', () async {
    final records = await adapter(
      snapshot: GallerySnapshot(
        items: [_remoteItem('remote-1', target: 'M42', capturedAt: now)],
        source: GallerySnapshotSource.remote,
        backendEnabled: true,
      ),
    ).getAll();

    final record = records.single;
    expect(record.id, 'remote:remote-1');
    expect(record.backendFileId, 'remote-1');
    expect(record.celestialObjectId, 'M42');
    expect(record.galleryThumbnailUri, contains('/thumbnail/remote-1'));
    expect(record.galleryPreviewUri, contains('/preview/remote-1'));
    expect(record.isRemoteAsset, isTrue);
  });

  test('backend OFF without cache falls back to SQLite records', () async {
    final local = _localRecord('local-1', 'M42', now);
    final records = await adapter(
      snapshot: const GallerySnapshot(
        items: [],
        source: GallerySnapshotSource.none,
        backendEnabled: false,
      ),
      local: [local],
    ).getAll();

    expect(records.single, same(local));
  });

  test('backend OFF uses gallery cache before SQLite records', () async {
    final records = await adapter(
      snapshot: GallerySnapshot(
        items: [_remoteItem('cached', target: 'M42', capturedAt: now)],
        source: GallerySnapshotSource.cache,
        backendEnabled: false,
      ),
      local: [_localRecord('local', 'M13', now)],
    ).getAll();

    expect(records.single.backendFileId, 'cached');
  });

  test('remote error uses cached projection when cache exists', () async {
    final records = await adapter(
      snapshot: GallerySnapshot(
        items: [_remoteItem('stale', target: 'M42', capturedAt: now)],
        source: GallerySnapshotSource.cache,
        backendEnabled: true,
        remoteFailed: true,
      ),
      local: [_localRecord('local', 'M13', now)],
    ).getAll();

    expect(records.single.backendFileId, 'stale');
  });

  test('remote error without cache falls back to SQLite records', () async {
    final local = _localRecord('local', 'M13', now);
    final records = await adapter(
      snapshot: const GallerySnapshot(
        items: [],
        source: GallerySnapshotSource.none,
        backendEnabled: true,
        remoteFailed: true,
      ),
      local: [local],
    ).getAll();

    expect(records.single, same(local));
  });

  test('GalleryViewModel search favorite and date sorting regressions', () async {
    final repository = adapter(
      snapshot: GallerySnapshot(
        items: [
          _remoteItem(
            'newest',
            target: 'M42',
            capturedAt: now,
            favorite: true,
          ),
          _remoteItem(
            'oldest',
            target: 'M13',
            capturedAt: now.subtract(const Duration(days: 1)),
          ),
        ],
        source: GallerySnapshotSource.remote,
        backendEnabled: true,
      ),
    );
    final viewModel = GalleryViewModel(
      repository,
      _FakeCatalogRepository(catalog),
      CatalogSearchService(),
    );

    await viewModel.load();
    expect(viewModel.filteredRecords.first.backendFileId, 'newest');

    viewModel.setSearchQuery('M13');
    expect(viewModel.filteredRecords.single.backendFileId, 'oldest');

    viewModel.clearFilters();
    viewModel.toggleFavoritesOnly();
    expect(viewModel.filteredRecords.single.backendFileId, 'newest');

    viewModel.clearFilters();
    viewModel.setSortOrder(GallerySortOrder.oldestFirst);
    expect(viewModel.filteredRecords.first.backendFileId, 'oldest');
  });
}

GalleryItem _remoteItem(
  String id, {
  required String target,
  required DateTime capturedAt,
  bool favorite = false,
}) => GalleryItem(
  backendFileId: id,
  thumbnailUrl: 'https://backend/thumbnail/$id',
  previewUrl: 'https://backend/preview/$id',
  originalUrl: 'https://backend/original/$id',
  capturedAt: capturedAt,
  favorite: favorite,
  location: 'Jeju',
  targetName: target,
  catalogObjectId: target,
  syncState: 'SYNCED',
);

ShootingRecord _localRecord(String id, String target, DateTime capturedAt) =>
    ShootingRecord(
      id: id,
      celestialObjectId: target,
      capturedAt: capturedAt,
      photoUri: '/local/$id.jpg',
      createdAt: capturedAt,
    );

class _FakeGalleryRepository implements GalleryRepository {
  _FakeGalleryRepository(this.snapshot);
  final GallerySnapshot snapshot;

  @override
  Future<GallerySnapshot> getSnapshot({bool forceRefresh = false}) async =>
      snapshot;

  @override
  Future<List<GalleryItem>> getAll({bool forceRefresh = false}) async =>
      snapshot.items;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLocalRepository implements ShootingRecordRepository {
  _FakeLocalRepository(this.records);
  final List<ShootingRecord> records;

  @override
  Future<List<ShootingRecord>> getAll() async => records;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCatalogRepository implements CatalogRepository {
  _FakeCatalogRepository(this.objects);
  final List<CatalogObject> objects;

  @override
  Future<List<CatalogObject>> getAll({bool listOnly = true}) async => objects;

  @override
  Future<CatalogObject?> getById(String id) async =>
      objects.where((object) => object.id == id).firstOrNull;

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

import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/core/constants/gallery_object_category.dart';
import 'package:astro_journal/data/models/catalog_candidate.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/shooting_record.dart';
import 'package:astro_journal/data/repositories/catalog_repository.dart';
import 'package:astro_journal/data/repositories/shooting_record_repository.dart';
import 'package:astro_journal/features/gallery/viewmodel/gallery_view_model.dart';
import 'package:astro_journal/services/catalog_search_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GalleryCategoryMapper', () {
    test('성운 분류', () {
      const obj = CatalogObject(
        id: 'M42',
        number: 42,
        catalog: CatalogType.messier,
        name: '오리온 대성운',
        type: '성운',
        constellation: '오리온',
        ra: '-',
        dec: '-',
        magnitude: '-',
      );
      expect(GalleryCategoryMapper.isNebula(obj), isTrue);
      expect(
        GalleryCategoryMapper.matches(obj, GalleryObjectCategory.nebula),
        isTrue,
      );
    });

    test('은하수는 milky catalog로 분류', () {
      const obj = CatalogObject(
        id: 'mw',
        number: 1,
        catalog: CatalogType.milky,
        name: '은하수',
        type: '은하',
        constellation: '-',
        ra: '-',
        dec: '-',
        magnitude: '-',
      );
      expect(
        GalleryCategoryMapper.matches(obj, GalleryObjectCategory.milkyWay),
        isTrue,
      );
      expect(
        GalleryCategoryMapper.matches(obj, GalleryObjectCategory.galaxy),
        isFalse,
      );
    });

    test('태양계 분류', () {
      const obj = CatalogObject(
        id: 'jupiter',
        number: 5,
        catalog: CatalogType.solar,
        name: '목성',
        type: '행성',
        constellation: '-',
        ra: '-',
        dec: '-',
        magnitude: '-',
      );
      expect(
        GalleryCategoryMapper.matches(obj, GalleryObjectCategory.solar),
        isTrue,
      );
    });
  });

  group('GalleryViewModel filtering', () {
    late GalleryViewModel viewModel;

    final catalog = [
      const CatalogObject(
        id: 'M27',
        number: 27,
        catalog: CatalogType.messier,
        name: '아령 성운',
        type: '성운',
        constellation: '여우',
        ra: '-',
        dec: '-',
        magnitude: '-',
      ),
      const CatalogObject(
        id: 'M13',
        number: 13,
        catalog: CatalogType.messier,
        name: '허큘리스 구상성단',
        type: '구상성단',
        constellation: '허큘리스',
        ra: '-',
        dec: '-',
        magnitude: '-',
      ),
    ];

    final records = [
      ShootingRecord(
        id: 'r1',
        celestialObjectId: 'M27',
        capturedAt: DateTime(2026, 1, 10),
        photoUri: '/a.jpg',
        createdAt: DateTime(2026, 1, 10),
        isFavorite: true,
      ),
      ShootingRecord(
        id: 'r2',
        celestialObjectId: 'M13',
        capturedAt: DateTime(2026, 2, 1),
        photoUri: '/b.jpg',
        createdAt: DateTime(2026, 2, 1),
      ),
    ];

    setUp(() {
      viewModel = GalleryViewModel(
        _FakeShootingRecordRepository(records),
        _FakeCatalogRepository(catalog),
        CatalogSearchService(),
      );
    });

    test('기본 보기 모드는 천체별', () {
      expect(viewModel.viewMode, GalleryViewMode.byObject);
    });

    test('카테고리 필터 - 성운만', () async {
      await viewModel.load();
      viewModel.setCategoryFilter(GalleryObjectCategory.nebula);
      expect(viewModel.filteredRecords.length, 1);
      expect(viewModel.filteredRecords.first.celestialObjectId, 'M27');
    });

    test('즐겨찾기 필터', () async {
      await viewModel.load();
      viewModel.toggleFavoritesOnly();
      expect(viewModel.filteredRecords.length, 1);
      expect(viewModel.filteredRecords.first.isFavorite, isTrue);
    });

    test('대상별 그룹 촬영횟수', () async {
      final extra = [
        ...records,
        ShootingRecord(
          id: 'r3',
          celestialObjectId: 'M27',
          capturedAt: DateTime(2026, 3, 1),
          photoUri: '/c.jpg',
          createdAt: DateTime(2026, 3, 1),
        ),
      ];
      viewModel = GalleryViewModel(
        _FakeShootingRecordRepository(extra),
        _FakeCatalogRepository(catalog),
        CatalogSearchService(),
      );
      await viewModel.load();
      final group =
          viewModel.targetGroups.firstWhere((g) => g.object.id == 'M27');
      expect(group.photoCount, 2);
    });

    test('촬영횟수 많은 순 정렬', () async {
      final extra = [
        ...records,
        ShootingRecord(
          id: 'r3',
          celestialObjectId: 'M27',
          capturedAt: DateTime(2026, 3, 1),
          photoUri: '/c.jpg',
          createdAt: DateTime(2026, 3, 1),
        ),
      ];
      viewModel = GalleryViewModel(
        _FakeShootingRecordRepository(extra),
        _FakeCatalogRepository(catalog),
        CatalogSearchService(),
      );
      await viewModel.load();
      viewModel.setSortOrder(GallerySortOrder.shootCountDesc);
      expect(viewModel.targetGroups.first.object.id, 'M27');
    });
  });
}

class _FakeShootingRecordRepository implements ShootingRecordRepository {
  _FakeShootingRecordRepository(this._records);

  final List<ShootingRecord> _records;

  @override
  Future<void> clearRepresentativeForObject(String celestialObjectId) async {}

  @override
  Future<void> delete(String id) async {}

  @override
  Future<ShootingRecord?> findByObjectAndCapturedAt(
    String celestialObjectId,
    DateTime capturedAt, {
    Duration tolerance = const Duration(minutes: 1),
  }) async =>
      null;

  @override
  Future<ShootingRecord?> findByOriginalFilename(String originalFilename) async =>
      null;

  @override
  Future<List<ShootingRecord>> getAll() async => _records;

  @override
  Future<List<ShootingRecord>> getByCelestialObjectId(
    String celestialObjectId,
  ) async =>
      _records.where((r) => r.celestialObjectId == celestialObjectId).toList();

  @override
  Future<ShootingRecord?> getById(String id) async => null;

  @override
  Future<void> save(ShootingRecord record) async {}

  @override
  Future<void> setRepresentative(String recordId) async {}

  @override
  Future<void> update(ShootingRecord record) async {}
}

class _FakeCatalogRepository implements CatalogRepository {
  _FakeCatalogRepository(this._objects);

  final List<CatalogObject> _objects;

  @override
  Future<List<CatalogObject>> getAll({bool listOnly = true}) async => _objects;

  @override
  Future<List<CatalogCandidate>> findNearbyObjects({
    required double raDeg,
    required double decDeg,
    required double radiusDeg,
  }) async =>
      const [];

  @override
  Future<List<CatalogObject>> findObjectsInPhotoField({
    required double centerRaDeg,
    required double centerDecDeg,
    required double fovWidthDeg,
    required double fovHeightDeg,
    required double rotationDeg,
  }) async =>
      const [];

  @override
  Future<CatalogObject?> getById(String id) async {
    for (final object in _objects) {
      if (object.id == id) return object;
    }
    return null;
  }

  @override
  Future<List<CatalogObject>> getByCatalog(CatalogType type) async =>
      _objects.where((o) => o.catalog == type).toList();

  @override
  Future<List<CatalogObject>> search(String query, {int limit = 50}) async =>
      const [];

  @override
  Future<void> updateCaptured(
    String id, {
    required bool captured,
    String? capturedDate,
  }) async {}

  @override
  Future<void> insert(CatalogObject object) async {}

  @override
  Future<void> delete(String id) async {}
}

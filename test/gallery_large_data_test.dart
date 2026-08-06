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

class _LargeShootingRecordRepository implements ShootingRecordRepository {
  _LargeShootingRecordRepository(this.records);

  final List<ShootingRecord> records;

  @override
  Future<List<ShootingRecord>> getAll() async => records;

  @override
  Future<List<ShootingRecord>> getByCelestialObjectId(String id) async =>
      records.where((record) => record.celestialObjectId == id).toList();

  @override
  Future<ShootingRecord?> getById(String id) async =>
      records.where((record) => record.id == id).firstOrNull;

  @override
  Future<ShootingRecord?> findByOriginalFilename(String originalFilename) async =>
      records
          .where((record) => record.originalFilename == originalFilename)
          .firstOrNull;

  @override
  Future<ShootingRecord?> findByObjectAndCapturedAt(
    String celestialObjectId,
    DateTime capturedAt, {
    Duration tolerance = const Duration(minutes: 1),
  }) async =>
      null;

  @override
  Future<void> save(ShootingRecord record) async {}

  @override
  Future<void> update(ShootingRecord record) async {}

  @override
  Future<void> delete(String id) async {}

  @override
  Future<void> clearRepresentativeForObject(String celestialObjectId) async {}

  @override
  Future<void> setRepresentative(String recordId) async {}
}

class _LargeCatalogRepository implements CatalogRepository {
  _LargeCatalogRepository(this.objects);

  final List<CatalogObject> objects;

  @override
  Future<List<CatalogObject>> getAll({bool listOnly = true}) async => objects;

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

void main() {
  group('GalleryViewModel large data', () {
    late GalleryViewModel viewModel;
    late List<ShootingRecord> records;
    late List<CatalogObject> catalog;

    setUp(() {
      catalog = List.generate(
        1000,
        (index) => CatalogObject(
          id: 'NGC$index',
          number: index,
          catalog: CatalogType.ngc,
          name: 'Target $index',
          type: index.isEven ? '성운' : '은하',
          constellation: 'Test',
          ra: '-',
          dec: '-',
          magnitude: '-',
          aliases: ['alias$index'],
        ),
      );

      records = List.generate(
        1000,
        (index) {
          final capturedAt = DateTime(2024, 1, 1).add(Duration(hours: index));
          return ShootingRecord(
            id: 'record_$index',
            celestialObjectId: 'NGC$index',
            capturedAt: capturedAt,
            photoUri: '/photos/$index.jpg',
            createdAt: capturedAt,
            isFavorite: index % 10 == 0,
          );
        },
      );

      viewModel = GalleryViewModel(
        _LargeShootingRecordRepository(records),
        _LargeCatalogRepository(catalog),
        CatalogSearchService(),
      );
    });

    test('load and filter 1,000 records within 2 seconds', () async {
      final stopwatch = Stopwatch()..start();
      await viewModel.load();
      viewModel.setSearchQuery('NGC 0');
      viewModel.setCategoryFilter(GalleryObjectCategory.nebula);
      viewModel.toggleFavoritesOnly();
      final filtered = viewModel.filteredRecords;
      final groups = viewModel.targetGroups;
      stopwatch.stop();

      expect(filtered, isNotEmpty);
      expect(groups, isNotEmpty);
      expect(stopwatch.elapsedMilliseconds, lessThan(2000));
    });

    test('pipeline cache avoids repeated filtering cost', () async {
      await viewModel.load();

      final first = Stopwatch()..start();
      final countA = viewModel.filteredRecords.length;
      final countB = viewModel.targetGroups.length;
      first.stop();

      final second = Stopwatch()..start();
      final countC = viewModel.filteredRecords.length;
      final countD = viewModel.targetGroups.length;
      second.stop();

      expect(countA, countC);
      expect(countB, countD);
      expect(second.elapsedMilliseconds, lessThanOrEqualTo(first.elapsedMilliseconds));
    });
  });
}

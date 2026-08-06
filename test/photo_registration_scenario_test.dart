import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/data/models/catalog_candidate.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/shooting_record.dart';
import 'package:astro_journal/data/repositories/catalog_repository.dart';
import 'package:astro_journal/data/repositories/shooting_record_repository.dart';
import 'package:astro_journal/features/gallery/viewmodel/gallery_view_model.dart';
import 'package:astro_journal/features/stats/viewmodel/stats_view_model.dart';
import 'package:astro_journal/services/catalog_search_service.dart';
import 'package:astro_journal/services/stats_analytics_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _ScenarioCatalogRepository implements CatalogRepository {
  _ScenarioCatalogRepository(this.objects);

  List<CatalogObject> objects;

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
  }) async {
    objects = objects
        .map(
          (object) => object.id == id
              ? CatalogObject(
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
              : object,
        )
        .toList();
  }

  @override
  Future<void> insert(CatalogObject object) async {
    objects = [...objects, object];
  }

  @override
  Future<void> delete(String id) async {}
}

class _ScenarioShootingRecordRepository implements ShootingRecordRepository {
  _ScenarioShootingRecordRepository(this.records);

  List<ShootingRecord> records;

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
  Future<void> save(ShootingRecord record) async {
    records = [...records, record];
  }

  @override
  Future<void> update(ShootingRecord record) async {
    records = records
        .map((existing) => existing.id == record.id ? record : existing)
        .toList();
  }

  @override
  Future<void> delete(String id) async {
    records = records.where((record) => record.id != id).toList();
  }

  @override
  Future<void> clearRepresentativeForObject(String celestialObjectId) async {}

  @override
  Future<void> setRepresentative(String recordId) async {}
}

void main() {
  group('Photo registration user scenario', () {
    test('record save reflects in gallery and stats', () async {
      final catalogRepository = _ScenarioCatalogRepository([
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
      ]);
      final shootingRepository = _ScenarioShootingRecordRepository([]);

      final capturedAt = DateTime(2026, 7, 20, 22, 30);
      final record = ShootingRecord(
        id: 'record_1',
        celestialObjectId: 'M27',
        capturedAt: capturedAt,
        photoUri: '/photos/m27.jpg',
        originalFilename: 'm27.jpg',
        createdAt: capturedAt,
        isRepresentative: true,
      );

      await shootingRepository.save(record);
      await catalogRepository.updateCaptured(
        'M27',
        captured: true,
        capturedDate: capturedAt.toIso8601String(),
      );

      final galleryViewModel = GalleryViewModel(
        shootingRepository,
        catalogRepository,
        CatalogSearchService(),
      );
      await galleryViewModel.load();

      expect(galleryViewModel.filteredRecords.length, 1);
      expect(galleryViewModel.targetGroups.length, 1);
      expect(galleryViewModel.targetGroups.first.object.captured, isTrue);

      final statsViewModel = StatsViewModel(
        shootingRepository,
        catalogRepository,
        StatsAnalyticsService(),
      );
      await statsViewModel.load();

      expect(statsViewModel.kpi?.totalShootCount, 1);
      expect(statsViewModel.kpi?.totalTargetCount, 1);
    });
  });
}

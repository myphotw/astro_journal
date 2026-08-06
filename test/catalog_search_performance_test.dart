import 'package:astro_journal/core/constants/catalog_kind_filter.dart';
import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/core/constants/object_type.dart';
import 'package:astro_journal/data/datasources/catalog_local_datasource.dart';
import 'package:astro_journal/data/models/catalog_candidate.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/equipment.dart';
import 'package:astro_journal/data/models/shooting_record.dart';
import 'package:astro_journal/data/repositories/catalog_repository.dart';
import 'package:astro_journal/data/repositories/equipment_repository.dart';
import 'package:astro_journal/data/repositories/shooting_record_repository.dart';
import 'package:astro_journal/features/catalog/viewmodel/catalog_view_model.dart';
import 'package:astro_journal/services/catalog_search_index.dart';
import 'package:astro_journal/services/catalog_search_service.dart';
import 'package:astro_journal/services/equipment/equipment_recommendation_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/test_database_helper.dart';

class _EmptyShootingRecordRepository implements ShootingRecordRepository {
  @override
  Future<List<ShootingRecord>> getAll() async => [];

  @override
  Future<List<ShootingRecord>> getByCelestialObjectId(String id) async => [];

  @override
  Future<ShootingRecord?> getById(String id) async => null;

  @override
  Future<ShootingRecord?> findByOriginalFilename(String originalFilename) async =>
      null;

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

class _EmptyEquipmentRepository implements EquipmentRepository {
  @override
  Future<List<Equipment>> getAll({bool activeOnly = false}) async => [];

  @override
  Future<Equipment?> getById(String id) async => null;

  @override
  Future<void> save(Equipment equipment) async {}

  @override
  Future<void> delete(String id) async {}
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Catalog search and filter performance', () {
    test('CatalogSearchIndex searches 13,000 objects quickly', () {
      final objects = List.generate(
        13000,
        (index) => CatalogObject(
          id: 'NGC$index',
          number: index,
          catalog: CatalogType.ngc,
          name: 'Target $index',
          type: '성운',
          constellation: 'Test',
          ra: '-',
          dec: '-',
          magnitude: '-',
          searchKeywords: 'search$index|alias$index',
          aliases: ['alias$index'],
        ),
      );

      final index = CatalogSearchIndex.build(objects);
      final stopwatch = Stopwatch()..start();
      final results = index.search('search4200');
      stopwatch.stop();

      expect(results, isNotEmpty);
      expect(stopwatch.elapsedMilliseconds, lessThan(200));
    });

    test('CatalogSearchService searches 1,000 objects quickly', () {
      final objects = List.generate(
        1000,
        (index) => CatalogObject(
          id: 'NGC$index',
          number: index,
          catalog: CatalogType.ngc,
          name: 'Target $index',
          type: '성운',
          constellation: 'Test',
          ra: '-',
          dec: '-',
          magnitude: '-',
          aliases: ['alias$index', 'search$index'],
        ),
      );

      final service = CatalogSearchService();
      final index = CatalogSearchIndex.build(objects);
      final stopwatch = Stopwatch()..start();
      final results = service.search('search42', objects, index: index);
      stopwatch.stop();

      expect(results, isNotEmpty);
      expect(stopwatch.elapsedMilliseconds, lessThan(500));
    });

    test('CatalogLocalDataSource getAll with explicit columns is fast', () async {
      final db = await openTestDatabase();
      final dataSource = CatalogLocalDataSource(database: db);

      for (var index = 0; index < 1200; index++) {
        await dataSource.insert(
          CatalogObject(
            id: 'NGC$index',
            number: index,
            catalog: CatalogType.ngc,
            name: 'Target $index',
            type: '성운',
            constellation: 'Test',
            ra: '-',
            dec: '-',
            magnitude: '-',
          ),
        );
      }

      final stopwatch = Stopwatch()..start();
      final objects = await dataSource.getAll();
      stopwatch.stop();

      expect(objects.length, 1200);
      expect(stopwatch.elapsedMilliseconds, lessThan(2000));
    });

    test('CatalogViewModel filters 1,000 objects quickly', () async {
      final objects = List.generate(
        1000,
        (index) => CatalogObject(
          id: 'M$index',
          number: index,
          catalog: CatalogType.messier,
          name: 'Target $index',
          type: index.isEven ? '성운' : '은하',
          constellation: 'Test',
          ra: '-',
          dec: '-',
          magnitude: '-',
          captured: index.isEven,
          objectType: index.isEven
              ? ObjectType.emissionNebula.label
              : ObjectType.galaxy.label,
        ),
      );

      final viewModel = CatalogViewModel(
        _InlineCatalogRepository(objects),
        _EmptyShootingRecordRepository(),
        _EmptyEquipmentRepository(),
        const EquipmentRecommendationService(),
      );

      final stopwatch = Stopwatch()..start();
      await viewModel.load();
      viewModel.selectTab(CatalogType.messier);
      viewModel.selectShootingFilter(ShootingFilter.captured);
      viewModel.selectKindFilter(CatalogKindFilter.nebula);
      final filtered = viewModel.objects;
      stopwatch.stop();

      expect(filtered, isNotEmpty);
      expect(stopwatch.elapsedMilliseconds, lessThan(2000));
    });
  });
}

class _InlineCatalogRepository implements CatalogRepository {
  _InlineCatalogRepository(this.objects);

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

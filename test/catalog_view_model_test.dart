import 'package:astro_journal/core/constants/catalog_kind_filter.dart';
import 'package:astro_journal/core/constants/catalog_sort_order.dart';
import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/core/constants/object_type.dart';
import 'package:astro_journal/data/models/catalog_candidate.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/shooting_record.dart';
import 'package:astro_journal/data/repositories/catalog_repository.dart';
import 'package:astro_journal/data/repositories/equipment_repository.dart';
import 'package:astro_journal/data/repositories/shooting_record_repository.dart';
import 'package:astro_journal/data/models/equipment.dart';
import 'package:astro_journal/features/catalog/viewmodel/catalog_detail_view_model.dart';
import 'package:astro_journal/features/catalog/viewmodel/catalog_view_model.dart';
import 'package:astro_journal/services/catalog_search_service.dart';
import 'package:astro_journal/services/equipment/equipment_recommendation_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeCatalogRepository implements CatalogRepository {
  _FakeCatalogRepository(this.objects);

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
      objects.where((o) => o.catalog == type).toList();

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

class _FakeShootingRecordRepository implements ShootingRecordRepository {
  @override
  Future<List<ShootingRecord>> getAll() async => [];

  @override
  Future<List<ShootingRecord>> getByCelestialObjectId(String id) async => [];

  @override
  Future<ShootingRecord?> getById(String id) async => null;

  @override
  Future<ShootingRecord?> findByOriginalFilename(String name) async => null;

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

class _FakeEquipmentRepository implements EquipmentRepository {
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
  CatalogObject obj({
    required String id,
    required String type,
    bool captured = false,
    CatalogType catalog = CatalogType.messier,
    String? commonName,
    List<String> aliases = const [],
    String? searchKeywords,
    bool isPrimary = true,
    String? primaryCatalogId,
  }) {
    return CatalogObject(
      id: id,
      number: int.tryParse(id.replaceAll(RegExp(r'\D'), '')) ?? 1,
      catalog: catalog,
      name: id,
      type: type,
      commonName: commonName,
      objectType: type,
      constellation: 'Test',
      ra: '00h',
      dec: "+00°00'",
      magnitude: '8',
      captured: captured,
      aliases: aliases,
      searchKeywords: searchKeywords,
      isPrimaryCatalog: isPrimary,
      primaryCatalogId: primaryCatalogId,
    );
  }

  group('CatalogViewModel filters', () {
    late CatalogViewModel vm;

    setUp(() async {
      vm = CatalogViewModel(
        _FakeCatalogRepository([
          obj(id: 'm31', type: '은하'),
          obj(id: 'm42', type: '발광성운'),
          obj(id: 'm13', type: '구상성단'),
          obj(id: 'm40', type: '쌍성'),
        ]),
        _FakeShootingRecordRepository(),
        _FakeEquipmentRepository(),
        const EquipmentRecommendationService(),
      );
      await vm.load();
    });

    test('kind filter narrows by object type', () {
      vm.selectKindFilter(CatalogKindFilter.galaxy);
      expect(vm.objects.map((o) => o.id), ['m31']);

      vm.selectKindFilter(CatalogKindFilter.nebula);
      expect(vm.objects.map((o) => o.id), ['m42']);

      vm.selectKindFilter(CatalogKindFilter.cluster);
      expect(vm.objects.map((o) => o.id), ['m13']);

      vm.selectKindFilter(CatalogKindFilter.star);
      expect(vm.objects.map((o) => o.id), ['m40']);
    });

    test('shooting and kind filters combine', () {
      vm.selectShootingFilter(ShootingFilter.captured);
      vm.selectKindFilter(CatalogKindFilter.galaxy);
      expect(vm.objects, isEmpty);

      vm.selectShootingFilter(ShootingFilter.all);
      expect(vm.objects.single.id, 'm31');
    });

    test('sort order changes list ordering', () async {
      final sortVm = CatalogViewModel(
        _FakeCatalogRepository([
          obj(
            id: 'm42',
            type: '발광성운',
            commonName: '오리온 대성운',
          ),
          obj(
            id: 'm1',
            type: '초신성잔해',
            commonName: '게성운',
          ),
        ]),
        _FakeShootingRecordRepository(),
        _FakeEquipmentRepository(),
        const EquipmentRecommendationService(),
      );
      await sortVm.load();

      sortVm.selectSortOrder(CatalogSortOrder.nameAsc);
      expect(sortVm.objects.map((object) => object.id).toList(), ['m1', 'm42']);
    });
  });

  group('CatalogViewModel search navigation', () {
    late CatalogViewModel vm;
    late CatalogObject ngc6818;
    late CatalogObject m1;

    setUp(() async {
      m1 = obj(id: 'M1', type: '초신성잔해', commonName: '게 성운');
      ngc6818 = obj(
        id: 'NGC6818',
        catalog: CatalogType.ngc,
        type: '행성상성운',
        commonName: 'NGC 6818',
        aliases: const ['Little Gem Nebula, Green Mars Nebula'],
        searchKeywords: 'NGC 6818|Little Gem Nebula, Green Mars Nebula',
      );

      vm = CatalogViewModel(
        _FakeCatalogRepository([
          m1,
          obj(id: 'M42', type: '발광성운'),
          ngc6818,
        ]),
        _FakeShootingRecordRepository(),
        _FakeEquipmentRepository(),
        const EquipmentRecommendationService(),
      );
      await vm.load();
    });

    test('green search finds NGC6818 via Green Mars Nebula alias', () {
      final results =
          CatalogSearchService().search('green', vm.allObjects, index: vm.searchIndex);
      expect(results.map((object) => object.id), contains('NGC6818'));
    });

    test('search navigation keeps selected object first on Messier tab', () {
      vm.selectTab(CatalogType.messier);

      final resolved = vm.resolveForNavigation(ngc6818);
      final navigation = vm.navigationTargetsForSearch(ngc6818);

      expect(resolved.id, 'NGC6818');
      expect(navigation.first.id, 'NGC6818');
      expect(
        CatalogDetailViewModel.indexOfObject(navigation, resolved),
        0,
      );
    });

    test('search navigation keeps selected object first on all tab', () {
      final navigation = vm.navigationTargetsForSearch(ngc6818);

      expect(navigation.first.id, 'NGC6818');
      expect(
        CatalogDetailViewModel.indexOfObject(navigation, ngc6818),
        0,
      );
    });
  });

  group('CatalogKindFilter', () {
    test('matches coarse categories', () {
      expect(
        CatalogKindFilter.nebula.matches(ObjectType.emissionNebula),
        isTrue,
      );
      expect(
        CatalogKindFilter.cluster.matches(ObjectType.globularCluster),
        isTrue,
      );
      expect(CatalogKindFilter.galaxy.matches(ObjectType.galaxyGroup), isTrue);
    });
  });
}

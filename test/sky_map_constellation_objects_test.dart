import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/core/constants/equipment_kind.dart';
import 'package:astro_journal/core/constants/equipment_purpose.dart';
import 'package:astro_journal/core/constants/object_type.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/equipment.dart';
import 'package:astro_journal/data/models/sky_map_render_object.dart';
import 'package:astro_journal/data/repositories/catalog_repository.dart';
import 'package:astro_journal/data/repositories/equipment_repository.dart';
import 'package:astro_journal/data/models/catalog_candidate.dart';
import 'package:astro_journal/features/sky_map/viewmodel/sky_map_view_model.dart';
import 'package:astro_journal/features/sky_map/widgets/sky_map_object_detail_sheet.dart';
import 'package:astro_journal/features/sky_map/widgets/sky_map_object_symbol.dart';
import 'package:astro_journal/features/sky_map/widgets/painters/catalog_object_painter.dart';
import 'package:astro_journal/features/sky_map/widgets/sky_map_visual_style.dart';
import 'package:astro_journal/services/celestial_position_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SkyMapObjectSymbolKind', () {
    test('종류별 심볼 매핑', () {
      expect(ObjectType.galaxy.skyMapSymbolKind, SkyMapObjectSymbolKind.galaxy);
      expect(
        ObjectType.openCluster.skyMapSymbolKind,
        SkyMapObjectSymbolKind.openCluster,
      );
      expect(
        ObjectType.globularCluster.skyMapSymbolKind,
        SkyMapObjectSymbolKind.globularCluster,
      );
      expect(
        ObjectType.emissionNebula.skyMapSymbolKind,
        SkyMapObjectSymbolKind.nebula,
      );
      expect(
        ObjectType.planetaryNebula.skyMapSymbolKind,
        SkyMapObjectSymbolKind.planetaryNebula,
      );
    });
  });

  group('SkyMapRenderObject.shapeKind', () {
    SkyMapRenderObject render(ObjectType type) {
      return SkyMapRenderObject(
        catalogId: 'x',
        name: 'x',
        objectType: type,
        catalog: CatalogType.messier,
        raDeg: 0,
        decDeg: 0,
        altitudeDeg: 10,
        screenX: 0,
        screenY: 0,
        renderWidth: 10,
        renderHeight: 10,
      );
    }

    test('구상/산개/행성상을 구분한다', () {
      expect(
        render(ObjectType.openCluster).shapeKind,
        SkyMapShapeKind.openCluster,
      );
      expect(
        render(ObjectType.globularCluster).shapeKind,
        SkyMapShapeKind.globularCluster,
      );
      expect(
        render(ObjectType.planetaryNebula).shapeKind,
        SkyMapShapeKind.planetaryNebula,
      );
      expect(render(ObjectType.galaxy).shapeKind, SkyMapShapeKind.galaxy);
      expect(
        render(ObjectType.emissionNebula).shapeKind,
        SkyMapShapeKind.nebula,
      );
    });
  });

  test('catalog labels use the shared object-type color hierarchy', () {
    final messier = SkyMapRenderObject(
      catalogId: 'M42',
      name: 'M42',
      objectType: ObjectType.emissionNebula,
      catalog: CatalogType.messier,
      raDeg: 0,
      decDeg: 0,
      altitudeDeg: 10,
      screenX: 0,
      screenY: 0,
      renderWidth: 10,
      renderHeight: 10,
    );
    final ngc = SkyMapRenderObject(
      catalogId: 'NGC1976',
      name: 'NGC1976',
      objectType: ObjectType.emissionNebula,
      catalog: CatalogType.ngc,
      raDeg: 0,
      decDeg: 0,
      altitudeDeg: 10,
      screenX: 0,
      screenY: 0,
      renderWidth: 10,
      renderHeight: 10,
    );
    final galaxy = SkyMapRenderObject(
      catalogId: 'M31',
      name: 'M31',
      objectType: ObjectType.galaxy,
      catalog: CatalogType.messier,
      raDeg: 0,
      decDeg: 0,
      altitudeDeg: 10,
      screenX: 0,
      screenY: 0,
      renderWidth: 10,
      renderHeight: 10,
    );

    expect(
      CatalogObjectPainter.labelColorFor(messier, false),
      SkyMapVisualStyle.nebula.withValues(alpha: 0.92),
    );
    expect(
      CatalogObjectPainter.labelColorFor(messier, true),
      SkyMapVisualStyle.nebula,
    );
    expect(
      CatalogObjectPainter.labelColorFor(ngc, false),
      SkyMapVisualStyle.nebula.withValues(alpha: 0.92),
    );
    expect(
      CatalogObjectPainter.labelColorFor(galaxy, true),
      SkyMapVisualStyle.galaxy,
    );
  });

  testWidgets('symbol legend is compact and expands without narrow overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 180, child: SkyMapSymbolLegend()),
          ),
        ),
      ),
    );

    expect(find.text('천체 기호'), findsOneWidget);
    expect(find.text('은하'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('sky-map-symbol-legend-toggle')),
    );
    await tester.pumpAndSettle();

    expect(find.text('은하'), findsOneWidget);
    expect(find.text('성운'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('SkyMapViewModel.objectsInConstellation', () {
    test('별자리 정규화 매칭 + 촬영 카운트용 captured 유지', () async {
      final catalog = _FakeCatalogRepository([
        _obj(
          id: 'M31',
          number: 31,
          constellation: '안드로메다',
          type: '은하',
          captured: true,
        ),
        _obj(
          id: 'M32',
          number: 32,
          constellation: '안드로메다자리',
          type: '은하',
          captured: true,
        ),
        _obj(
          id: 'M110',
          number: 110,
          constellation: '안드로메다자리',
          type: '은하',
          captured: false,
        ),
        _obj(
          id: 'NGC891',
          number: 891,
          constellation: '안드로메다자리',
          type: '은하',
          catalogType: CatalogType.ngc,
          captured: false,
        ),
        _obj(
          id: 'M42',
          number: 42,
          constellation: '오리온자리',
          type: '발광성운',
          captured: false,
        ),
      ]);
      final vm = SkyMapViewModel(catalog, _FakeEquipmentRepository());
      await vm.load();

      final list = vm.objectsInConstellation('안드로메다자리');
      expect(list.map((e) => e.id), ['M110', 'M31', 'M32', 'NGC891']);
      expect(list.where((e) => e.captured).length, 2);

      final messierOnly = vm.objectsInConstellation(
        '안드로메다자리',
        catalogs: {ConstellationCatalogFilter.messier},
      );
      expect(messierOnly.map((e) => e.id), ['M110', 'M31', 'M32']);

      final ngcOnly = vm.objectsInConstellation(
        '안드로메다자리',
        catalogs: {ConstellationCatalogFilter.ngc},
      );
      expect(ngcOnly.map((e) => e.id), ['NGC891']);

      final multiCatalog = vm.objectsInConstellation(
        '안드로메다자리',
        catalogs: {
          ConstellationCatalogFilter.messier,
          ConstellationCatalogFilter.ngc,
        },
      );
      expect(multiCatalog.map((e) => e.id), ['M110', 'M31', 'M32', 'NGC891']);
    });

    test('범례 종류 필터 다중선택 + Catalog 필터 조합', () async {
      final catalog = _FakeCatalogRepository([
        _obj(
          id: 'M31',
          number: 31,
          constellation: '안드로메다자리',
          type: '은하',
          captured: true,
        ),
        _obj(
          id: 'M42',
          number: 42,
          constellation: '오리온자리',
          type: '발광성운',
          captured: false,
        ),
        _obj(
          id: 'M45',
          number: 45,
          constellation: '황소자리',
          type: '산개성단',
          captured: false,
        ),
        _obj(
          id: 'M13',
          number: 13,
          constellation: '헤르쿨레스자리',
          type: '구상성단',
          captured: false,
        ),
        _obj(
          id: 'M57',
          number: 57,
          constellation: '거문고자리',
          type: '행성상성운',
          captured: false,
        ),
        _obj(
          id: 'NGC1977',
          number: 1977,
          constellation: '오리온자리',
          type: '반사성운',
          catalogType: CatalogType.ngc,
          captured: false,
        ),
      ]);
      final vm = SkyMapViewModel(catalog, _FakeEquipmentRepository());
      await vm.load();

      expect(
        vm
            .objectsInConstellation(
              '오리온자리',
              objectTypes: {SkyMapObjectTypeFilter.nebula},
            )
            .map((e) => e.id),
        ['NGC1977', 'M42'],
      );
      expect(
        vm
            .objectsInConstellation(
              '오리온자리',
              catalogs: {ConstellationCatalogFilter.messier},
              objectTypes: {SkyMapObjectTypeFilter.nebula},
            )
            .map((e) => e.id),
        ['M42'],
      );
      expect(
        vm
            .objectsInConstellation(
              '황소자리',
              objectTypes: {SkyMapObjectTypeFilter.openCluster},
            )
            .map((e) => e.id),
        ['M45'],
      );
      expect(
        vm
            .objectsInConstellation(
              '헤르쿨레스자리',
              objectTypes: {SkyMapObjectTypeFilter.globularCluster},
            )
            .map((e) => e.id),
        ['M13'],
      );
      expect(
        vm
            .objectsInConstellation(
              '거문고자리',
              objectTypes: {SkyMapObjectTypeFilter.planetaryNebula},
            )
            .map((e) => e.id),
        ['M57'],
      );
      expect(
        vm
            .objectsInConstellation(
              '안드로메다자리',
              objectTypes: {
                SkyMapObjectTypeFilter.galaxy,
                SkyMapObjectTypeFilter.nebula,
              },
            )
            .map((e) => e.id),
        ['M31'],
      );
    });

    test('성도 필터 종류는 범례와 동일', () {
      expect(SkyMapFilters.supportedObjectTypes.map((e) => e.label).toList(), [
        '은하',
        '산개성단',
        '구상성단',
        '성운',
        '행성상성운',
      ]);
      expect(
        SkyMapObjectTypeFilter.forObjectType(ObjectType.emissionNebula),
        SkyMapObjectTypeFilter.nebula,
      );
      expect(
        SkyMapObjectTypeFilter.forObjectType(ObjectType.planetaryNebula),
        SkyMapObjectTypeFilter.planetaryNebula,
      );
    });

    test('별자리 라벨 히트 영역', () {
      const render = SkyMapConstellationRender(
        id: 'And',
        name: '안드로메다자리',
        segments: [],
        labelX: 100,
        labelY: 80,
        labelWidth: 80,
        labelHeight: 16,
        labelAltitudeDeg: 20,
      );
      expect(render.labelHitRect.contains(const Offset(100, 80)), isTrue);
      expect(render.labelHitRect.contains(const Offset(200, 200)), isFalse);
    });

    test('V2에서도 검색·선택·필터·히트·장비 FOV 계약을 유지한다', () async {
      final object = _obj(
        id: 'M42',
        number: 42,
        constellation: '오리온자리',
        type: '발광성운',
        captured: true,
        commonName: '오리온대성운',
      );
      const equipment = Equipment(
        id: 'scope-1',
        name: 'Wide scope',
        kind: EquipmentKind.smartTelescope,
        purpose: EquipmentPurpose.imaging,
        fovWidthDegrees: 2,
        fovHeightDegrees: 1,
      );
      final vm = SkyMapViewModel(
        _FakeCatalogRepository([object]),
        _FakeEquipmentRepository([equipment]),
        null,
        () => DateTime.utc(2026, 1, 15, 12),
      );
      await vm.load();
      vm.updateCanvasSize(const Size(800, 800));

      final result = vm.searchResults('M42').single;
      expect(result.catalogObject?.id, 'M42');
      expect(result.catalogObject?.captured, isTrue);

      vm.selectObject(object);
      final render = vm.selectedRenderObject;
      expect(render?.catalogId, 'M42');
      expect(
        vm.hitTest(Offset(render!.screenX, render.screenY))?.catalogId,
        'M42',
      );

      vm.showFovForEquipment(equipment);
      expect(vm.showFovOverlay, isTrue);
      expect(vm.fovCorners, hasLength(4));
      expect(vm.filters.catalogs, contains(CatalogType.messier));
      vm.dispose();
    });

    test('지평선 아래 천체도 전천 화면에 남고 선택할 수 있다', () async {
      final time = DateTime.utc(2026, 1, 15, 12);
      final raHour = List<int>.generate(24, (index) => index).firstWhere((ra) {
        final altitude = CelestialPositionService.computeAltAz(
          raHours: ra.toDouble(),
          decDeg: 0,
          latDeg: 0,
          lonDeg: 0,
          time: time,
        ).altitude;
        return altitude < -5 && altitude > -15;
      });
      final object = _obj(
        id: 'M900',
        number: 900,
        constellation: '테스트자리',
        type: '은하',
        captured: false,
        ra: '${raHour}h0m',
      );
      final vm = SkyMapViewModel(
        _FakeCatalogRepository([object]),
        _FakeEquipmentRepository(),
        null,
        () => time,
      );
      await vm.load();
      vm.updateCanvasSize(const Size(1000, 800));

      final render = vm.visibleObjects.single;
      expect(render.altitudeDeg, lessThan(0));
      expect(render.screenX, inInclusiveRange(0, 1000));
      expect(render.screenY, inInclusiveRange(0, 800));
      expect(
        vm.hitTest(Offset(render.screenX, render.screenY))?.catalogId,
        object.id,
      );
      expect(vm.visibleStars.any((star) => star.altitudeDeg < 0), isTrue);
      expect(
        vm.visibleConstellations.any(
          (constellation) => constellation.segments.any(
            (segment) =>
                segment.$1.altitudeDeg < 0 || segment.$2.altitudeDeg < 0,
          ),
        ),
        isTrue,
      );
      vm.dispose();
    });

    testWidgets('V2에서도 대상 상세정보와 촬영 장비가 표시된다', (tester) async {
      final object = _obj(
        id: 'M42',
        number: 42,
        constellation: '오리온자리',
        type: '발광성운',
        captured: true,
        commonName: '오리온대성운',
      );
      const equipment = Equipment(
        id: 'scope-1',
        name: 'Wide scope',
        kind: EquipmentKind.smartTelescope,
        purpose: EquipmentPurpose.imaging,
        fovWidthDegrees: 2,
        fovHeightDegrees: 1,
      );
      final vm = SkyMapViewModel(
        _FakeCatalogRepository([object]),
        _FakeEquipmentRepository([equipment]),
        null,
        () => DateTime.utc(2026, 1, 15, 12),
      );
      await vm.load();

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showSkyMapObjectDetailSheet(
                context: context,
                viewModel: vm,
                object: object,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('M42'), findsOneWidget);
      expect(find.text('오리온대성운'), findsOneWidget);
      expect(find.text('촬영 기록'), findsOneWidget);
      expect(find.text('있음'), findsOneWidget);
      expect(find.text('Wide scope'), findsOneWidget);
      expect(find.text(equipment.fovLabel), findsOneWidget);
      vm.dispose();
    });
  });
}

CatalogObject _obj({
  required String id,
  required int number,
  required String constellation,
  required String type,
  required bool captured,
  String? commonName,
  String ra = '0h0m',
  String dec = '+0d0m',
  CatalogType catalogType = CatalogType.messier,
}) {
  return CatalogObject(
    id: id,
    number: number,
    catalog: catalogType,
    name: id,
    commonName: commonName,
    type: type,
    objectType: type,
    constellation: constellation,
    ra: ra,
    dec: dec,
    magnitude: '5',
    captured: captured,
  );
}

class _FakeCatalogRepository implements CatalogRepository {
  _FakeCatalogRepository(this.objects);

  final List<CatalogObject> objects;

  @override
  Future<List<CatalogObject>> getAll({bool listOnly = true}) async => objects;

  @override
  Future<CatalogObject?> getById(String id) async => objects
      .cast<CatalogObject?>()
      .firstWhere((o) => o?.id == id, orElse: () => null);

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
}

class _FakeEquipmentRepository implements EquipmentRepository {
  _FakeEquipmentRepository([this.equipment = const []]);

  final List<Equipment> equipment;

  @override
  Future<List<Equipment>> getAll({bool activeOnly = false}) async => equipment;

  @override
  Future<Equipment?> getById(String id) async => null;

  @override
  Future<void> save(Equipment equipment) async {}

  @override
  Future<void> delete(String id) async {}
}

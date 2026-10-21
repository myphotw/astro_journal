import 'dart:async';

import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/data/models/catalog_candidate.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/equipment.dart';
import 'package:astro_journal/data/models/sky_map_render_object.dart';
import 'package:astro_journal/data/repositories/catalog_repository.dart';
import 'package:astro_journal/data/repositories/equipment_repository.dart';
import 'package:astro_journal/features/sky_map/viewmodel/sky_map_view_model.dart';
import 'package:astro_journal/features/sky_map/widgets/sky_map_filter_sheet.dart';
import 'package:astro_journal/features/sky_map/widgets/sky_map_object_detail_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SkyMapViewModel viewModel;

  setUp(() async {
    viewModel = SkyMapViewModel(
      _CatalogRepository(const [..._solarObjects, _pluto]),
      _EquipmentRepository(),
      null,
      () => DateTime.utc(2026, 1, 1),
    );
    await viewModel.load();
    viewModel.updateCanvasSize(const Size(900, 700));
  });

  tearDown(() => viewModel.dispose());

  test('loads exactly the supported Sun Moon and seven planets', () {
    expect(viewModel.filters.showSolarSystem, isTrue);
    expect(viewModel.solarSystemObjects.map((object) => object.id), [
      'solar_1',
      'solar_2',
      'solar_3',
      'solar_4',
      'solar_5',
      'solar_6',
      'solar_7',
      'solar_8',
      'solar_9',
    ]);
    expect(viewModel.solarSystemPositions, hasLength(9));
    expect(viewModel.solarSystemObjects, isNot(contains(_pluto)));
  });

  test('each body can be selected and projected at its dynamic location', () {
    for (final object in viewModel.solarSystemObjects) {
      viewModel.selectObject(object);
      final render = viewModel.visibleObjects.singleWhere(
        (candidate) => candidate.catalogId == object.id,
      );
      final dynamicPosition = viewModel.solarSystemPositionFor(object.id)!;
      expect(render.raDeg, dynamicPosition.raDeg);
      expect(render.decDeg, dynamicPosition.decDeg);
      expect(render.altitudeDeg, dynamicPosition.altAz.altitude);
    }
  });

  test('solar symbols distinguish Sun Moon and planets', () {
    SkyMapRenderObject render(String id) => SkyMapRenderObject(
      catalogId: id,
      name: id,
      objectType: _solarObjects
          .singleWhere((object) => object.id == id)
          .resolvedObjectType,
      catalog: CatalogType.solar,
      raDeg: 0,
      decDeg: 0,
      altitudeDeg: 0,
      screenX: 0,
      screenY: 0,
      renderWidth: 18,
      renderHeight: 18,
    );

    expect(render('solar_1').shapeKind, SkyMapShapeKind.sun);
    expect(render('solar_2').shapeKind, SkyMapShapeKind.moon);
    expect(render('solar_6').shapeKind, SkyMapShapeKind.planet);
  });

  test('filter hides markers but retains ephemerides and Sun background', () {
    final sunAltitude = viewModel.sunAltitudeDeg;
    viewModel.setShowSolarSystem(false);

    expect(viewModel.filters.showSolarSystem, isFalse);
    expect(
      viewModel.visibleObjects.where(
        (object) => object.catalog == CatalogType.solar,
      ),
      isEmpty,
    );
    expect(viewModel.solarSystemPositions, hasLength(9));
    expect(viewModel.sunAltitudeDeg, sunAltitude);
  });

  test('search accepts Korean and English aliases independent of filter', () {
    viewModel.setShowSolarSystem(false);

    final korean = viewModel.searchResults('목성');
    final english = viewModel.searchResults('Jupiter');

    expect(korean.single.id, 'solar_6');
    expect(english.single.id, 'solar_6');
    viewModel.selectObject(english.single.catalogObject);
    expect(viewModel.filters.showSolarSystem, isTrue);
    expect(viewModel.selectedObject?.id, 'solar_6');
  });

  testWidgets('time changes update coordinates without resetting view state', (
    tester,
  ) async {
    viewModel.selectObject(
      viewModel.solarSystemObjects.singleWhere(
        (object) => object.id == 'solar_5',
      ),
    );
    viewModel.panByPixels(const Offset(20, 10));
    viewModel.setViewHeightDeg(35);
    await tester.pump();
    final centerAzimuth = viewModel.centerAzimuthDeg;
    final centerAltitude = viewModel.centerAltitudeDeg;
    final viewHeight = viewModel.viewHeightDeg;
    final selectedId = viewModel.selectedObject?.id;
    final before = viewModel.solarSystemPositionFor('solar_5')!;

    viewModel.setObservationTime(DateTime.utc(2026, 1, 2));
    await tester.pump();
    final after = viewModel.solarSystemPositionFor('solar_5')!;

    expect(after.raDeg, isNot(before.raDeg));
    expect(after.altAz.azimuth, isNot(before.altAz.azimuth));
    expect(viewModel.centerAzimuthDeg, centerAzimuth);
    expect(viewModel.centerAltitudeDeg, centerAltitude);
    expect(viewModel.viewHeightDeg, viewHeight);
    expect(viewModel.selectedObject?.id, selectedId);
  });

  testWidgets('filter sheet exposes an independent Solar System switch', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => unawaited(
                showSkyMapFilterSheet(context: context, viewModel: viewModel),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final switchFinder = find.byKey(
      const ValueKey('sky-map-solar-system-filter'),
    );
    expect(switchFinder, findsOneWidget);
    expect(find.text('태양계'), findsOneWidget);
    await tester.tap(switchFinder);
    await tester.pump();
    expect(viewModel.filters.showSolarSystem, isFalse);
  });

  testWidgets('detail sheet presents dynamic coordinates instead of dashes', (
    tester,
  ) async {
    final jupiter = viewModel.solarSystemObjects.singleWhere(
      (object) => object.id == 'solar_6',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => unawaited(
                showSkyMapObjectDetailSheet(
                  context: context,
                  viewModel: viewModel,
                  object: jupiter,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('sky-map-dynamic-time')), findsOneWidget);
    expect(find.byKey(const ValueKey('sky-map-dynamic-ra')), findsOneWidget);
    expect(find.byKey(const ValueKey('sky-map-dynamic-dec')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('sky-map-dynamic-alt-az')),
      findsOneWidget,
    );
    for (final key in const [
      ValueKey('sky-map-dynamic-ra'),
      ValueKey('sky-map-dynamic-dec'),
      ValueKey('sky-map-dynamic-alt-az'),
    ]) {
      expect(
        find.descendant(of: find.byKey(key), matching: find.text('-')),
        findsNothing,
      );
    }
  });
}

const _solarObjects = <CatalogObject>[
  CatalogObject(
    id: 'solar_1',
    number: 1,
    catalog: CatalogType.solar,
    name: '태양',
    commonName: '태양',
    type: '항성',
    objectType: '항성',
    constellation: '-',
    ra: '-',
    dec: '-',
    magnitude: '-26.7',
    aliases: ['Sun', 'Sol'],
  ),
  CatalogObject(
    id: 'solar_2',
    number: 2,
    catalog: CatalogType.solar,
    name: '달',
    commonName: '달',
    type: '위성',
    objectType: '위성',
    constellation: '-',
    ra: '-',
    dec: '-',
    magnitude: '-12.7',
    aliases: ['Moon', 'Luna'],
  ),
  CatalogObject(
    id: 'solar_3',
    number: 3,
    catalog: CatalogType.solar,
    name: '수성',
    type: '행성',
    objectType: '행성',
    constellation: '-',
    ra: '-',
    dec: '-',
    magnitude: '-2.0',
    aliases: ['Mercury'],
  ),
  CatalogObject(
    id: 'solar_4',
    number: 4,
    catalog: CatalogType.solar,
    name: '금성',
    type: '행성',
    objectType: '행성',
    constellation: '-',
    ra: '-',
    dec: '-',
    magnitude: '-4.6',
    aliases: ['Venus'],
  ),
  CatalogObject(
    id: 'solar_5',
    number: 5,
    catalog: CatalogType.solar,
    name: '화성',
    type: '행성',
    objectType: '행성',
    constellation: '-',
    ra: '-',
    dec: '-',
    magnitude: '-2.9',
    aliases: ['Mars'],
  ),
  CatalogObject(
    id: 'solar_6',
    number: 6,
    catalog: CatalogType.solar,
    name: '목성',
    type: '행성',
    objectType: '행성',
    constellation: '-',
    ra: '-',
    dec: '-',
    magnitude: '-2.9',
    aliases: ['Jupiter'],
  ),
  CatalogObject(
    id: 'solar_7',
    number: 7,
    catalog: CatalogType.solar,
    name: '토성',
    type: '행성',
    objectType: '행성',
    constellation: '-',
    ra: '-',
    dec: '-',
    magnitude: '+0.7',
    aliases: ['Saturn'],
  ),
  CatalogObject(
    id: 'solar_8',
    number: 8,
    catalog: CatalogType.solar,
    name: '천왕성',
    type: '행성',
    objectType: '행성',
    constellation: '-',
    ra: '-',
    dec: '-',
    magnitude: '+5.7',
    aliases: ['Uranus'],
  ),
  CatalogObject(
    id: 'solar_9',
    number: 9,
    catalog: CatalogType.solar,
    name: '해왕성',
    type: '행성',
    objectType: '행성',
    constellation: '-',
    ra: '-',
    dec: '-',
    magnitude: '+7.8',
    aliases: ['Neptune'],
  ),
];

const _pluto = CatalogObject(
  id: 'solar_10',
  number: 10,
  catalog: CatalogType.solar,
  name: '명왕성',
  type: '왜소행성',
  constellation: '-',
  ra: '-',
  dec: '-',
  magnitude: '+14.4',
);

class _CatalogRepository implements CatalogRepository {
  const _CatalogRepository(this.objects);

  final List<CatalogObject> objects;

  @override
  Future<List<CatalogObject>> getAll({bool listOnly = true}) async => objects;
  @override
  Future<CatalogObject?> getById(String id) async => null;
  @override
  Future<List<CatalogObject>> getByCatalog(CatalogType type) async => const [];
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

class _EquipmentRepository implements EquipmentRepository {
  @override
  Future<List<Equipment>> getAll({bool activeOnly = false}) async => const [];
  @override
  Future<Equipment?> getById(String id) async => null;
  @override
  Future<void> save(Equipment equipment) async {}
  @override
  Future<void> delete(String id) async {}
}

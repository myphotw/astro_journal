import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/data/models/blocked_azimuth_range.dart';
import 'package:astro_journal/data/models/catalog_candidate.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/equipment.dart';
import 'package:astro_journal/data/models/horizon_point.dart';
import 'package:astro_journal/data/models/observation_site.dart';
import 'package:astro_journal/data/repositories/catalog_repository.dart';
import 'package:astro_journal/data/repositories/equipment_repository.dart';
import 'package:astro_journal/data/repositories/observation_site_repository.dart';
import 'package:astro_journal/features/observation_site/viewmodel/active_observation_site_view_model.dart';
import 'package:astro_journal/features/sky_map/view/sky_map_screen.dart';
import 'package:astro_journal/features/sky_map/viewmodel/sky_map_view_model.dart';
import 'package:astro_journal/services/location_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  late List<ObservationSite> sites;
  late ActiveObservationSiteViewModel activeSite;
  late SkyMapViewModel skyMap;

  setUp(() async {
    sites = [
      _site('home', '집 베란다', 37.5, 127),
      _site('gurye', '구례 관측지', 35.2, 127.5),
    ];
    activeSite = ActiveObservationSiteViewModel(_SiteRepository(sites));
    await activeSite.load();
    await activeSite.selectSavedSite(sites.first);
    skyMap = SkyMapViewModel(
      _CatalogRepository(),
      _EquipmentRepository(),
      activeSite,
      () => DateTime(2026, 10, 21, 20),
    );
  });

  tearDown(() => skyMap.dispose());

  testWidgets('selects a registered site from the sky map header', (
    tester,
  ) async {
    await _pumpSkyMap(tester, activeSite, skyMap, _LocationService());

    await tester.tap(find.byKey(const Key('active-observation-site-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('구례 관측지').last);
    await tester.pumpAndSettle();

    expect(activeSite.active.selectedSiteId, 'gurye');
    expect(skyMap.observerLabel, '구례 관측지');
    expect(activeSite.active.latitude, 35.2);
    expect(activeSite.active.longitude, 127.5);
  });

  testWidgets('current location failure keeps the previous valid site', (
    tester,
  ) async {
    await _pumpSkyMap(tester, activeSite, skyMap, _LocationService(fail: true));

    await tester.tap(find.byKey(const Key('active-observation-site-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('현재 위치').last);
    await tester.pumpAndSettle();

    expect(activeSite.active.selectedSiteId, 'home');
    expect(find.text('현재 위치를 확인할 수 없습니다.'), findsOneWidget);
  });

  testWidgets('current location is applied atomically with coordinates', (
    tester,
  ) async {
    await _pumpSkyMap(tester, activeSite, skyMap, _LocationService());

    await tester.tap(find.byKey(const Key('active-observation-site-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('현재 위치').last);
    await tester.pumpAndSettle();

    expect(activeSite.active.isCurrentLocation, isTrue);
    expect(activeSite.active.latitude, 37.55);
    expect(activeSite.active.longitude, 126.98);
    expect(skyMap.observerLabel, '현재 위치');
    expect(skyMap.observationSiteHorizonProfile.hasRestrictions, isFalse);
  });

  testWidgets('narrow header keeps site, search, and filter without overflow', (
    tester,
  ) async {
    await _pumpSkyMap(
      tester,
      activeSite,
      skyMap,
      _LocationService(),
      size: const Size(360, 760),
    );

    expect(
      find.byKey(const Key('sky-map-observation-site-selector')),
      findsOneWidget,
    );
    expect(find.text('천체 · 별 · 별자리 검색'), findsOneWidget);
    expect(find.byTooltip('필터'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('site change recalculates sky while preserving view state', () async {
    await skyMap.load();
    skyMap.updateCanvasSize(const Size(800, 600));
    final object = (await _CatalogRepository().getAll()).single;
    skyMap.selectObject(object);
    final beforePosition = Offset(
      skyMap.visibleObjects.single.screenX,
      skyMap.visibleObjects.single.screenY,
    );
    final beforeSunAltitude = skyMap.sunAltitudeDeg;
    final beforeSunset = skyMap.nightTimeline.sunset;
    final beforeAzimuth = skyMap.centerAzimuthDeg;
    final beforeAltitude = skyMap.centerAltitudeDeg;
    final beforeViewHeight = skyMap.viewHeightDeg;
    final beforeFilters = skyMap.filters;

    await activeSite.selectSavedSite(sites.last);

    expect(
      Offset(
        skyMap.visibleObjects.single.screenX,
        skyMap.visibleObjects.single.screenY,
      ),
      isNot(beforePosition),
    );
    expect(skyMap.sunAltitudeDeg, isNot(beforeSunAltitude));
    expect(skyMap.nightTimeline.sunset, isNot(beforeSunset));
    expect(skyMap.observerLabel, '구례 관측지');
    expect(skyMap.selectedObject?.id, object.id);
    expect(skyMap.centerAzimuthDeg, beforeAzimuth);
    expect(skyMap.centerAltitudeDeg, beforeAltitude);
    expect(skyMap.viewHeightDeg, beforeViewHeight);
    expect(skyMap.filters, same(beforeFilters));
  });
}

class _LocationService extends LocationService {
  _LocationService({this.fail = false});

  final bool fail;

  @override
  Future<LocationData> getCurrentLocation({
    bool preferLastKnown = false,
    Duration timeLimit = const Duration(seconds: 12),
  }) async {
    if (fail) throw Exception('현재 위치를 확인할 수 없습니다.');
    return LocationData(
      latitude: 37.55,
      longitude: 126.98,
      accuracy: 10,
      timestamp: DateTime(2026, 10, 21, 20),
    );
  }
}

Future<void> _pumpSkyMap(
  WidgetTester tester,
  ActiveObservationSiteViewModel activeSite,
  SkyMapViewModel skyMap,
  LocationService locationService, {
  Size size = const Size(900, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: activeSite),
        ChangeNotifierProvider.value(value: skyMap),
        Provider<LocationService>.value(value: locationService),
      ],
      child: const MaterialApp(home: SkyMapScreen()),
    ),
  );
  await tester.pump();
}

ObservationSite _site(
  String id,
  String name,
  double latitude,
  double longitude,
) => ObservationSite(
  id: id,
  name: name,
  latitude: latitude,
  longitude: longitude,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  horizonPoints: id == 'home'
      ? const [
          HorizonPoint(
            id: 'home-horizon',
            observationSiteId: 'home',
            azimuth: 180,
            minAltitude: 30,
          ),
        ]
      : const [],
);

class _SiteRepository implements ObservationSiteRepository {
  const _SiteRepository(this.sites);

  final List<ObservationSite> sites;

  @override
  Future<List<ObservationSite>> list({bool includeDeleted = false}) async =>
      sites;
  @override
  Future<void> markLastUsed(String id, DateTime usedAt) async {}
  @override
  Future<ObservationSite?> get(
    String id, {
    bool includeDeleted = false,
  }) async => null;
  @override
  Future<void> create(ObservationSite site) async {}
  @override
  Future<void> createFavorite(ObservationSite site) async {}
  @override
  Future<void> update(ObservationSite site) async {}
  @override
  Future<void> delete(String id, {bool hard = false}) async {}
  @override
  Future<void> setFavorite(String id, bool favorite) async {}
  @override
  Future<List<HorizonPoint>> listHorizonPoints(String siteId) async => const [];
  @override
  Future<void> addHorizonPoint(HorizonPoint point) async {}
  @override
  Future<void> updateHorizonPoint(HorizonPoint point) async {}
  @override
  Future<void> deleteHorizonPoint(String id) async {}
  @override
  Future<void> replaceHorizonPoints(
    String siteId,
    List<HorizonPoint> points,
  ) async {}
  @override
  Future<List<BlockedAzimuthRange>> listBlockedRanges(String siteId) async =>
      const [];
  @override
  Future<void> addBlockedRange(BlockedAzimuthRange range) async {}
  @override
  Future<void> updateBlockedRange(BlockedAzimuthRange range) async {}
  @override
  Future<void> deleteBlockedRange(String id) async {}
  @override
  Future<void> replaceBlockedRanges(
    String siteId,
    List<BlockedAzimuthRange> ranges,
  ) async {}
}

class _CatalogRepository implements CatalogRepository {
  @override
  Future<List<CatalogObject>> getAll({bool listOnly = true}) async => const [
    CatalogObject(
      id: 'M-test',
      number: 999,
      catalog: CatalogType.messier,
      name: 'M-test',
      commonName: 'Site target',
      type: '은하',
      objectType: '은하',
      constellation: '오리온자리',
      ra: '5h0m',
      dec: '+20d0m',
      magnitude: '5',
    ),
  ];
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

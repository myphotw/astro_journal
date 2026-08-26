import 'dart:async';

import 'package:astro_journal/data/models/blocked_azimuth_range.dart';
import 'package:astro_journal/data/models/equipment.dart';
import 'package:astro_journal/data/models/horizon_point.dart';
import 'package:astro_journal/data/models/observation_site.dart';
import 'package:astro_journal/data/models/observation_condition.dart';
import 'package:astro_journal/data/models/imaging_suitability_assessment.dart';
import 'package:astro_journal/data/repositories/bortle_repository.dart';
import 'package:astro_journal/core/constants/equipment_kind.dart';
import 'package:astro_journal/core/constants/equipment_purpose.dart';
import 'package:astro_journal/data/repositories/equipment_repository.dart';
import 'package:astro_journal/data/repositories/observation_site_repository.dart';
import 'package:astro_journal/features/settings/view/observation_site_list_screen.dart';
import 'package:astro_journal/services/geocoding_service.dart';
import 'package:astro_journal/services/location_service.dart';
import 'package:astro_journal/services/observation_condition_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _FakeObservationSiteRepository implements ObservationSiteRepository {
  final List<ObservationSite> sites = [];

  @override
  Future<void> create(ObservationSite site) async => sites.add(site);

  @override
  Future<void> delete(String id, {bool hard = false}) async =>
      sites.removeWhere((site) => site.id == id);

  @override
  Future<ObservationSite?> get(String id, {bool includeDeleted = false}) async {
    for (final site in sites) {
      if (site.id == id) return site;
    }
    return null;
  }

  @override
  Future<List<ObservationSite>> list({bool includeDeleted = false}) async =>
      List.of(sites);

  @override
  Future<void> setFavorite(String id, bool favorite) async {
    final index = sites.indexWhere((site) => site.id == id);
    sites[index] = sites[index].copyWith(isFavorite: favorite);
  }

  @override
  Future<void> update(ObservationSite site) async {
    final index = sites.indexWhere((item) => item.id == site.id);
    sites[index] = site;
  }

  @override
  Future<void> markLastUsed(String id, DateTime usedAt) async {}
  @override
  Future<void> addBlockedRange(BlockedAzimuthRange range) async {}
  @override
  Future<void> addHorizonPoint(HorizonPoint point) async {}
  @override
  Future<void> deleteBlockedRange(String id) async {}
  @override
  Future<void> deleteHorizonPoint(String id) async {}
  @override
  Future<List<BlockedAzimuthRange>> listBlockedRanges(String siteId) async =>
      const [];
  @override
  Future<List<HorizonPoint>> listHorizonPoints(String siteId) async => const [];
  @override
  Future<void> replaceBlockedRanges(
    String siteId,
    List<BlockedAzimuthRange> ranges,
  ) async {}
  @override
  Future<void> replaceHorizonPoints(
    String siteId,
    List<HorizonPoint> points,
  ) async {}
  @override
  Future<void> updateBlockedRange(BlockedAzimuthRange range) async {}
  @override
  Future<void> updateHorizonPoint(HorizonPoint point) async {}
}

class _FakeEquipmentRepository implements EquipmentRepository {
  _FakeEquipmentRepository([this.items = const []]);
  final List<Equipment> items;
  @override
  Future<void> delete(String id) async {}
  @override
  Future<List<Equipment>> getAll({bool activeOnly = false}) async => items;
  @override
  Future<Equipment?> getById(String id) async => null;
  @override
  Future<void> save(Equipment equipment) async {}
}

class _UnusedBortleRepository implements BortleRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeObservationConditionService extends ObservationConditionService {
  _FakeObservationConditionService()
    : super(LocationService(), _UnusedBortleRepository());

  @override
  Future<ObservationCondition> getConditionAt(
    double latitude,
    double longitude,
  ) async => ObservationCondition(
    latitude: latitude,
    longitude: longitude,
    brightness: 1.5,
    bortle: 6,
    sqm: 20.42,
    createdAt: DateTime(2026),
  );
}

class _FakeGeocodingService extends GeocodingService {
  final List<String> autocompleteQueries = [];

  @override
  Future<List<LocationSearchSuggestion>> autocompleteLocations(
    String query, [
    String? legacyApiKey,
  ]) async {
    autocompleteQueries.add(query);
    return const [
      LocationSearchSuggestion(
        mainText: '서울 천문대',
        secondaryText: '서울특별시 테스트구',
        latitude: 37.55,
        longitude: 126.98,
      ),
    ];
  }

  @override
  Future<GeocodeForwardResult?> geocodeAddress(
    String query, [
    String? legacyApiKey,
  ]) async => const GeocodeForwardResult(
    latitude: 37.55,
    longitude: 126.98,
    formattedAddress: '서울특별시 테스트구',
    placeName: '서울 천문대',
  );
}

class _RacingGeocodingService extends GeocodingService {
  final Map<String, Completer<List<LocationSearchSuggestion>>> requests = {};

  @override
  Future<List<LocationSearchSuggestion>> autocompleteLocations(
    String query, [
    String? legacyApiKey,
  ]) => requests
      .putIfAbsent(query, () => Completer<List<LocationSearchSuggestion>>())
      .future;
}

class _FailingDetailsGeocodingService extends GeocodingService {
  @override
  Future<List<LocationSearchSuggestion>> autocompleteLocations(
    String query, [
    String? legacyApiKey,
  ]) async => const [
    LocationSearchSuggestion(placeId: 'failed', mainText: '실패 장소'),
  ];

  @override
  Future<GeocodeForwardResult?> getPlaceDetails(
    String placeId, [
    String? legacyApiKey,
  ]) async => throw StateError('details failed');
}

Widget _app(
  _FakeObservationSiteRepository repository, {
  List<Equipment> equipment = const [],
  GeocodingService? geocodingService,
}) {
  return MultiProvider(
    providers: [
      Provider<ObservationSiteRepository>.value(value: repository),
      Provider<EquipmentRepository>.value(
        value: _FakeEquipmentRepository(equipment),
      ),
      Provider<GeocodingService>.value(
        value: geocodingService ?? _FakeGeocodingService(),
      ),
      Provider<ObservationConditionService>.value(
        value: _FakeObservationConditionService(),
      ),
    ],
    child: const MaterialApp(home: ObservationSiteListScreen()),
  );
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets('lists a canonical observation site', (tester) async {
    final repository = _FakeObservationSiteRepository()
      ..sites.add(
        ObservationSite(
          id: 'site-1',
          name: '서울',
          latitude: 37.5,
          longitude: 127,
          bortle: 8,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      );
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    expect(find.text('서울'), findsOneWidget);
    expect(find.textContaining('Bortle 8'), findsOneWidget);
  });

  testWidgets('creates a site and exposes manual horizon controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _FakeObservationSiteRepository();
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('add-observation-site')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('site-name')), '테스트 관측지');
    await tester.enterText(find.byKey(const Key('site-latitude')), '37.5');
    await tester.enterText(find.byKey(const Key('site-longitude')), '127.0');
    expect(find.byKey(const Key('add-blocked-range')), findsOneWidget);
    expect(find.byKey(const Key('add-horizon-point')), findsOneWidget);
    expect(find.byKey(const Key('start-horizon-scan')), findsOneWidget);
    expect(find.textContaining('기본 최소 고도'), findsNothing);
    expect(find.textContaining('기본 최대 고도'), findsNothing);

    await tester.tap(find.byKey(const Key('add-blocked-range')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('blocked-range-start')), '350');
    await tester.enterText(find.byKey(const Key('blocked-range-end')), '20');
    await tester.tap(find.widgetWithText(FilledButton, '적용'));
    await tester.pumpAndSettle();
    expect(find.text('350.0° → 20.0°'), findsOneWidget);

    final blockedRangeTile = find.ancestor(
      of: find.text('350.0° → 20.0°'),
      matching: find.byType(ListTile),
    );
    await tester.tap(
      find.descendant(
        of: blockedRangeTile,
        matching: find.byIcon(Icons.delete_outline),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('350.0° → 20.0°'), findsNothing);

    await tester.tap(find.byKey(const Key('add-horizon-point')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('horizon-azimuth')), '120');
    await tester.enterText(find.byKey(const Key('horizon-min-altitude')), '25');
    await tester.tap(find.widgetWithText(FilledButton, '적용'));
    await tester.pumpAndSettle();
    expect(find.text('방향 120.0°'), findsOneWidget);

    await tester.tap(find.text('방향 120.0°'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('horizon-min-altitude')), '30');
    await tester.tap(find.widgetWithText(FilledButton, '적용'));
    await tester.pumpAndSettle();
    expect(find.textContaining('최소 가시 고도 30°'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('save-observation-site')));
    await tester.tap(find.byKey(const Key('save-observation-site')));
    await tester.pumpAndSettle();

    expect(repository.sites, hasLength(1));
    expect(repository.sites.single.name, '테스트 관측지');
    expect(repository.sites.single.horizonPoints, hasLength(1));
    expect(repository.sites.single.horizonPoints.single.minAltitude, 30);
    expect(repository.sites.single.blockedAzimuthRanges, isEmpty);
    expect(find.text('테스트 관측지'), findsOneWidget);
  });

  testWidgets('address selection derives coordinates, Bortle, and SQM', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _FakeObservationSiteRepository();
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('add-observation-site')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('site-name')), '자동 관측지');
    await tester.tap(find.byKey(const Key('site-location-selection')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('location-search-field')),
      '서울',
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    await tester.tap(find.text('서울 천문대'));
    await tester.pumpAndSettle();

    String fieldText(Key key) =>
        tester.widget<TextFormField>(find.byKey(key)).controller!.text;
    expect(fieldText(const Key('site-latitude')), '37.550000');
    expect(fieldText(const Key('site-longitude')), '126.980000');
    expect(fieldText(const Key('site-bortle')), '6');
    expect(fieldText(const Key('site-sqm')), '20.42');
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const Key('site-location-selection')),
          )
          .controller!
          .text,
      '서울 천문대 · 서울특별시 테스트구',
    );

    await tester.ensureVisible(find.byKey(const Key('save-observation-site')));
    await tester.tap(find.byKey(const Key('save-observation-site')));
    await tester.pumpAndSettle();
    expect(repository.sites.single.latitude, 37.55);
    expect(repository.sites.single.longitude, 126.98);
    expect(repository.sites.single.bortle, 6);
    expect(repository.sites.single.sqm, 20.42);

    await tester.tap(find.text('자동 관측지'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-observation-site-detail')));
    await tester.pumpAndSettle();
    expect(fieldText(const Key('site-latitude')), '37.55');
    expect(fieldText(const Key('site-longitude')), '126.98');
    expect(fieldText(const Key('site-bortle')), '6');
    expect(fieldText(const Key('site-sqm')), '20.42');
  });

  testWidgets('location search ignores empty input and stale responses', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final geocoding = _RacingGeocodingService();
    await tester.pumpWidget(
      _app(_FakeObservationSiteRepository(), geocodingService: geocoding),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-observation-site')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('site-location-selection')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('location-search-field')), '서');
    await tester.pump(const Duration(milliseconds: 500));
    expect(geocoding.requests, isEmpty);

    await tester.enterText(
      find.byKey(const Key('location-search-field')),
      '서울',
    );
    await tester.pump(const Duration(milliseconds: 350));
    expect(geocoding.requests, contains('서울'));
    await tester.enterText(
      find.byKey(const Key('location-search-field')),
      '부산',
    );
    await tester.pump(const Duration(milliseconds: 350));
    expect(geocoding.requests, contains('부산'));

    geocoding.requests['부산']!.complete(const [
      LocationSearchSuggestion(
        mainText: '부산 천문대',
        latitude: 35.1,
        longitude: 129,
      ),
    ]);
    await tester.pump();
    expect(find.text('부산 천문대'), findsOneWidget);

    geocoding.requests['서울']!.complete(const [
      LocationSearchSuggestion(
        mainText: '서울 천문대',
        latitude: 37.5,
        longitude: 127,
      ),
    ]);
    await tester.pump();
    expect(find.text('부산 천문대'), findsOneWidget);
    expect(find.text('서울 천문대'), findsNothing);
  });

  testWidgets('failed location details preserve the existing location', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _FakeObservationSiteRepository()
      ..sites.add(
        ObservationSite(
          id: 'site-existing',
          name: '기존 위치',
          address: '기존 주소',
          latitude: 37.5,
          longitude: 127,
          bortle: 7,
          sqm: 19.5,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      );
    await tester.pumpWidget(
      _app(repository, geocodingService: _FailingDetailsGeocodingService()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('기존 위치'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-observation-site-detail')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('site-location-selection')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('location-search-field')),
      '실패',
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    await tester.tap(find.text('실패 장소'));
    await tester.pumpAndSettle();

    String fieldText(Key key) =>
        tester.widget<TextFormField>(find.byKey(key)).controller!.text;
    expect(fieldText(const Key('site-latitude')), '37.5');
    expect(fieldText(const Key('site-longitude')), '127.0');
    expect(fieldText(const Key('site-bortle')), '7');
    expect(fieldText(const Key('site-sqm')), '19.5');
    expect(find.textContaining('기존 위치는 유지됩니다'), findsOneWidget);
  });

  testWidgets('quick horizon controls save eight directions and can reset', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _FakeObservationSiteRepository();
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('add-observation-site')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('site-name')), '빠른 시야');
    await tester.enterText(find.byKey(const Key('site-latitude')), '37.5');
    await tester.enterText(find.byKey(const Key('site-longitude')), '127');

    final northSlider = tester.widget<Slider>(
      find.descendant(
        of: find.byKey(const Key('horizon-direction-0')),
        matching: find.byType(Slider),
      ),
    );
    northSlider.onChanged!(25);
    await tester.pump();
    expect(find.text('실제 시야: 등록됨'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('save-observation-site')));
    await tester.tap(find.byKey(const Key('save-observation-site')));
    await tester.pumpAndSettle();
    expect(repository.sites.single.horizonPoints, hasLength(8));
    expect(
      repository.sites.single.horizonPoints
          .firstWhere((point) => point.azimuth == 0)
          .minAltitude,
      25,
    );

    await tester.tap(find.text('빠른 시야'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-observation-site-detail')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('clear-horizon')));
    await tester.tap(find.byKey(const Key('clear-horizon')));
    await tester.pump();
    expect(find.text('실제 시야: 제한 없음'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('save-observation-site')));
    await tester.tap(find.byKey(const Key('save-observation-site')));
    await tester.pumpAndSettle();
    expect(repository.sites.single.horizonPoints, isEmpty);
    expect(repository.sites.single.blockedAzimuthRanges, isEmpty);
  });

  testWidgets('shows validation error for an empty site name', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _FakeObservationSiteRepository();
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-observation-site')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('site-latitude')), '37.5');
    await tester.enterText(find.byKey(const Key('site-longitude')), '127');
    await tester.ensureVisible(find.byKey(const Key('save-observation-site')));
    await tester.tap(find.byKey(const Key('save-observation-site')));
    await tester.pump();
    expect(find.text('관측지 이름은 필수입니다.'), findsOneWidget);
    expect(repository.sites, isEmpty);
  });

  testWidgets('edits and deletes without touching shooting records', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _FakeObservationSiteRepository()
      ..sites.add(
        ObservationSite(
          id: 'site-1',
          name: '기존 관측지',
          latitude: 37.5,
          longitude: 127,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      );
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('기존 관측지'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('observation-site-detail')), findsOneWidget);
    await tester.tap(find.byKey(const Key('edit-observation-site-detail')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('site-name')), '수정 관측지');
    await tester.ensureVisible(find.byKey(const Key('save-observation-site')));
    await tester.tap(find.byKey(const Key('save-observation-site')));
    await tester.pumpAndSettle();
    expect(repository.sites.single.name, '수정 관측지');

    await tester.tap(find.byKey(const Key('edit-observation-site-detail')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-observation-site')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '삭제'));
    await tester.pumpAndSettle();
    expect(repository.sites, isEmpty);
  });

  testWidgets(
    'site detail changes tracking and equipment and shows horizon summary',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _FakeObservationSiteRepository()
        ..sites.add(
          ObservationSite(
            id: 'site-detail',
            name: '우리집',
            latitude: 37.5,
            longitude: 127,
            bortle: 8,
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
            blockedAzimuthRanges: const [
              BlockedAzimuthRange(
                id: 'range-1',
                observationSiteId: 'site-detail',
                startAzimuth: 350,
                endAzimuth: 20,
              ),
            ],
            horizonPoints: const [
              HorizonPoint(
                id: 'point-1',
                observationSiteId: 'site-detail',
                azimuth: 120,
                minAltitude: 25,
              ),
            ],
          ),
        );
      const equipment = Equipment(
        id: 'seestar',
        name: 'Seestar S30 Pro',
        kind: EquipmentKind.smartTelescope,
        purpose: EquipmentPurpose.imaging,
      );
      await tester.pumpWidget(_app(repository, equipment: const [equipment]));
      await tester.pumpAndSettle();
      await tester.tap(find.text('우리집'));
      await tester.pumpAndSettle();

      expect(find.text('촬영 가능 시야'), findsOneWidget);
      expect(
        find.byKey(const Key('observation-site-horizon-visualization')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('site-detail-horizon-scan')), findsOneWidget);
      expect(
        find.byKey(const Key('site-detail-manual-horizon')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('site-detail-tracking')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('EQ').last);
      await tester.pumpAndSettle();
      expect(repository.sites.single.trackingMode, TrackingMode.eq);

      await tester.tap(find.byKey(const Key('site-detail-equipment')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Seestar S30 Pro').last);
      await tester.pumpAndSettle();
      expect(repository.sites.single.defaultEquipmentId, 'seestar');

      await tester.tap(find.byKey(const Key('site-detail-manual-horizon')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('save-observation-site')), findsOneWidget);
      expect(find.text('막힌 방향'), findsOneWidget);
    },
  );
}

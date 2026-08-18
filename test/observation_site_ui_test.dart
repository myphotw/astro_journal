import 'package:astro_journal/data/models/blocked_azimuth_range.dart';
import 'package:astro_journal/data/models/equipment.dart';
import 'package:astro_journal/data/models/horizon_point.dart';
import 'package:astro_journal/data/models/observation_site.dart';
import 'package:astro_journal/data/repositories/equipment_repository.dart';
import 'package:astro_journal/data/repositories/observation_site_repository.dart';
import 'package:astro_journal/features/settings/view/observation_site_list_screen.dart';
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
  @override
  Future<void> delete(String id) async {}
  @override
  Future<List<Equipment>> getAll({bool activeOnly = false}) async => const [];
  @override
  Future<Equipment?> getById(String id) async => null;
  @override
  Future<void> save(Equipment equipment) async {}
}

Widget _app(_FakeObservationSiteRepository repository) {
  return MultiProvider(
    providers: [
      Provider<ObservationSiteRepository>.value(value: repository),
      Provider<EquipmentRepository>.value(value: _FakeEquipmentRepository()),
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
    expect(find.text('방위각 120.0°'), findsOneWidget);

    await tester.tap(find.text('방위각 120.0°'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('horizon-min-altitude')), '30');
    await tester.tap(find.widgetWithText(FilledButton, '적용'));
    await tester.pumpAndSettle();
    expect(find.textContaining('최소 30.0°'), findsOneWidget);

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
    await tester.enterText(find.byKey(const Key('site-name')), '수정 관측지');
    await tester.ensureVisible(find.byKey(const Key('save-observation-site')));
    await tester.tap(find.byKey(const Key('save-observation-site')));
    await tester.pumpAndSettle();
    expect(repository.sites.single.name, '수정 관측지');

    await tester.tap(find.text('수정 관측지'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-observation-site')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '삭제'));
    await tester.pumpAndSettle();
    expect(repository.sites, isEmpty);
  });
}

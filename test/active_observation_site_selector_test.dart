import 'package:astro_journal/data/models/blocked_azimuth_range.dart';
import 'package:astro_journal/data/models/horizon_point.dart';
import 'package:astro_journal/data/models/observation_site.dart';
import 'package:astro_journal/data/models/weather_data.dart';
import 'package:astro_journal/data/repositories/observation_site_repository.dart';
import 'package:astro_journal/features/observation_site/viewmodel/active_observation_site_view_model.dart';
import 'package:astro_journal/features/observation_site/widgets/active_observation_site_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Repository implements ObservationSiteRepository {
  _Repository(this.sites);
  final List<ObservationSite> sites;
  @override
  Future<List<ObservationSite>> list({bool includeDeleted = false}) async =>
      List.of(sites);
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
  Future<void> createFavorite(ObservationSite site) => create(site);
  @override
  Future<void> update(ObservationSite site) async {}
  @override
  Future<void> delete(String id, {bool hard = false}) async {}
  @override
  Future<void> setFavorite(String id, bool favorite) async {}
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

void main() {
  testWidgets('selects current location and a saved active site', (
    tester,
  ) async {
    final site = ObservationSite(
      id: 'home',
      name: '우리집',
      address: '서울 구로구 천왕동',
      latitude: 37.5,
      longitude: 127,
      bortle: 8,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    final viewModel = ActiveObservationSiteViewModel(_Repository([site]));
    await viewModel.load();
    var selectedCurrent = 0;
    String? selectedSite;
    var detailOpens = 0;
    var manageOpens = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ActiveObservationSiteSelector(
            viewModel: viewModel,
            onSelectCurrentLocation: () async {
              selectedCurrent++;
              await viewModel.selectCurrentLocation();
            },
            onSelectSite: (id) async {
              selectedSite = id;
              await viewModel.selectSavedSite(site);
            },
            onOpenDetail: () => detailOpens++,
            onManageSites: () => manageOpens++,
            equipmentName: 'Seestar S30 Pro',
            activeWeather: WeatherData(
              temperature: 27,
              feelsLike: 28,
              humidity: 60,
              windSpeed: 0.8,
              windDegree: 0,
              pressure: 1012,
              cloudCoverage: 38,
              visibility: 10000,
              sunrise: DateTime(2026),
              sunset: DateTime(2026),
              description: '흐림',
              cityName: '서울',
            ),
          ),
        ),
      ),
    );

    expect(find.text('관측지'), findsOneWidget);
    expect(find.text('현재 위치'), findsOneWidget);
    expect(find.text('Alt-Az · Seestar S30 Pro'), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const Key('active-observation-site-card')))
          .height,
      lessThanOrEqualTo(80),
    );

    await tester.tap(find.byKey(const Key('active-observation-site-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('우리집').last);
    await tester.pumpAndSettle();
    expect(selectedSite, 'home');
    expect(selectedCurrent, 0);
    expect(find.text('우리집'), findsOneWidget);
    expect(find.textContaining('서울 구로구 천왕동'), findsOneWidget);
    expect(find.textContaining('Bortle 8'), findsOneWidget);
    expect(find.textContaining('흐림 38% · 27°C'), findsOneWidget);

    await tester.tap(find.byKey(const Key('open-active-site-detail')));
    await tester.tap(find.byKey(const Key('manage-observation-sites')));
    expect(detailOpens, 1);
    expect(manageOpens, 1);

    await tester.tap(find.byKey(const Key('active-observation-site-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('현재 위치').last);
    await tester.pumpAndSettle();
    expect(selectedCurrent, 1);
  });

  testWidgets('compact selector keeps registered sites and checked selection', (
    tester,
  ) async {
    final sites = [
      ObservationSite(
        id: 'home',
        name: '이름이 아주 긴 집 베란다 관측지',
        latitude: 37.5,
        longitude: 127,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
      ObservationSite(
        id: 'gurye',
        name: '구례 관측지',
        latitude: 35.2,
        longitude: 127.5,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    ];
    final viewModel = ActiveObservationSiteViewModel(_Repository(sites));
    await viewModel.load();
    await viewModel.selectSavedSite(sites.first);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 180,
            child: ActiveObservationSiteSelector(
              viewModel: viewModel,
              onSelectCurrentLocation: () async {},
              onSelectSite: (id) async {
                await viewModel.selectSavedSite(
                  sites.singleWhere((site) => site.id == id),
                );
              },
              onOpenDetail: () {},
              onManageSites: () {},
              embedded: true,
              compact: true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('관측지'), findsNothing);
    expect(
      tester
          .getSize(find.byKey(const Key('active-observation-site-card')))
          .height,
      44,
    );
    final selectedName = tester.widget<Text>(
      find.text('이름이 아주 긴 집 베란다 관측지').first,
    );
    expect(selectedName.overflow, TextOverflow.ellipsis);

    await tester.tap(find.byKey(const Key('active-observation-site-selector')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('observation-site-option-home')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('observation-site-option-gurye')),
      findsOneWidget,
    );

    await tester.tap(find.text('구례 관측지').last);
    await tester.pumpAndSettle();
    expect(viewModel.active.selectedSiteId, 'gurye');
  });
}

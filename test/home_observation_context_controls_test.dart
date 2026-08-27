import 'package:astro_journal/core/constants/equipment_kind.dart';
import 'package:astro_journal/core/constants/equipment_purpose.dart';
import 'package:astro_journal/core/services/performance_probe.dart';
import 'package:astro_journal/data/models/blocked_azimuth_range.dart';
import 'package:astro_journal/data/models/equipment.dart';
import 'package:astro_journal/data/models/horizon_point.dart';
import 'package:astro_journal/data/models/imaging_suitability_assessment.dart';
import 'package:astro_journal/data/models/observation_site.dart';
import 'package:astro_journal/data/models/weather_data.dart';
import 'package:astro_journal/data/repositories/observation_site_repository.dart';
import 'package:astro_journal/features/home/view/widgets/home_observation_context_controls.dart';
import 'package:astro_journal/features/observation_site/viewmodel/active_observation_site_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _SiteRepository implements ObservationSiteRepository {
  _SiteRepository(this.sites);

  final List<ObservationSite> sites;

  @override
  Future<List<ObservationSite>> list({bool includeDeleted = false}) async =>
      List.of(sites);
  @override
  Future<void> markLastUsed(String id, DateTime usedAt) async {}
  @override
  Future<ObservationSite?> get(String id, {bool includeDeleted = false}) async {
    for (final site in sites) {
      if (site.id == id) return site;
    }
    return null;
  }

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
  final site = ObservationSite(
    id: 'site-long',
    name: '서울특별시 도심 옥상 장기 관측 테스트 장소 이름',
    address: '서울특별시 구로구 천왕동 매우 긴 주소 이름',
    latitude: 37.5,
    longitude: 127,
    defaultEquipmentId: 'equipment-long',
    bortle: 8,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  const equipment = Equipment(
    id: 'equipment-long',
    name: 'Seestar S30 Pro 장비 이름이 매우 긴 테스트 구성',
    kind: EquipmentKind.smartTelescope,
    purpose: EquipmentPurpose.imaging,
    focalLengthMm: 250,
    fovWidthDegrees: 4.2,
    fovHeightDegrees: 2.4,
  );

  Future<void> pumpControls(
    WidgetTester tester,
    Size size, {
    ValueChanged<String?>? onEquipmentChanged,
    ValueChanged<TrackingMode>? onTrackingChanged,
    bool withWeather = true,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final viewModel = ActiveObservationSiteViewModel(_SiteRepository([site]));
    await viewModel.load();
    await viewModel.selectSavedSite(site);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: HomeObservationContextControls(
              siteViewModel: viewModel,
              equipment: const [equipment],
              selectedEquipmentId: equipment.id,
              selectedEquipmentName: equipment.name,
              trackingMode: TrackingMode.altAz,
              onSelectCurrentLocation: () async {},
              onSelectSite: (_) async {},
              onOpenSiteDetail: () {},
              onManageSites: () {},
              onEquipmentChanged: onEquipmentChanged ?? (_) {},
              onTrackingChanged: onTrackingChanged ?? (_) {},
              activeWeather: withWeather
                  ? WeatherData(
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
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders long site and equipment names on a phone', (
    tester,
  ) async {
    await pumpControls(tester, const Size(360, 800));

    expect(find.byKey(const Key('home-equipment-selector')), findsOneWidget);
    expect(
      find.byKey(const Key('home-tracking-mode-selector')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('home-context-compact-layout')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    expect(find.textContaining('서울특별시 구로구 천왕동'), findsOneWidget);
    expect(find.textContaining('Bortle 8'), findsOneWidget);
    expect(find.textContaining('흐림 38% · 27°C'), findsOneWidget);
    expect(find.byKey(const Key('manage-observation-sites')), findsNothing);
    expect(
      tester
          .getSize(find.byKey(const Key('active-observation-site-card')))
          .height,
      tester.getSize(find.byKey(const Key('home-equipment-card'))).height,
    );
    await tester.tap(find.byKey(const Key('active-observation-site-selector')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('observation-site-option-site-long')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.check_rounded), findsWidgets);
  });

  testWidgets('renders selectors without overflow on a tablet', (tester) async {
    await pumpControls(tester, const Size(1200, 800));

    expect(
      find.byKey(const Key('home-observation-context-controls')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('home-context-wide-layout')), findsOneWidget);
    expect(find.text('Alt-Az'), findsOneWidget);
    final segmented = tester.widget<SegmentedButton<TrackingMode>>(
      find.byType(SegmentedButton<TrackingMode>),
    );
    expect(segmented.expandedInsets, EdgeInsets.zero);
    expect(
      tester
          .getSize(find.byKey(const Key('active-observation-site-card')))
          .height,
      tester.getSize(find.byKey(const Key('home-equipment-card'))).height,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('equipment and tracking selectors emit the selected context', (
    tester,
  ) async {
    String? selectedEquipment = 'not-called';
    TrackingMode? selectedTracking;
    await pumpControls(
      tester,
      const Size(360, 800),
      onEquipmentChanged: (value) => selectedEquipment = value,
      onTrackingChanged: (value) => selectedTracking = value,
    );

    await tester.tap(find.byKey(const Key('home-equipment-selector')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('equipment-option-equipment-long')),
      findsOneWidget,
    );
    expect(find.textContaining('250mm · 스마트망원경 · 촬영 장비'), findsWidgets);
    await tester.tap(find.text('자동 선택').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('EQ'));
    await tester.pumpAndSettle();

    expect(selectedEquipment, isNull);
    expect(selectedTracking, TrackingMode.eq);
  });

  testWidgets('site selector shows a friendly missing-weather fallback', (
    tester,
  ) async {
    await pumpControls(tester, const Size(360, 800), withWeather: false);

    expect(find.textContaining('날씨 없음'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('idle context controls do not rebuild repeatedly', (tester) async {
    PerformanceProbe.reset();
    await pumpControls(tester, const Size(360, 800));

    expect(
      PerformanceProbe.count('widget.observation_context_controls.build'),
      1,
    );
    expect(PerformanceProbe.count('widget.equipment_selector.build'), 1);
    expect(PerformanceProbe.count('widget.tracking_selector.build'), 1);
    expect(
      PerformanceProbe.count('widget.observation_site_selector.build'),
      1,
    );

    await tester.pump();

    expect(
      PerformanceProbe.count('widget.observation_context_controls.build'),
      1,
    );
    expect(
      PerformanceProbe.count('widget.observation_site_selector.build'),
      1,
    );
  });
}

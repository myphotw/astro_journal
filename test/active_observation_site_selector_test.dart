import 'package:astro_journal/data/models/blocked_azimuth_range.dart';
import 'package:astro_journal/data/models/horizon_point.dart';
import 'package:astro_journal/data/models/observation_site.dart';
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
      latitude: 37.5,
      longitude: 127,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    final viewModel = ActiveObservationSiteViewModel(_Repository([site]));
    await viewModel.load();
    var selectedCurrent = 0;
    String? selectedSite;

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
            onOpenDetail: () {},
            onManageSites: () {},
          ),
        ),
      ),
    );

    expect(find.text('오늘의 관측지'), findsOneWidget);
    expect(find.text('현재 위치 (임시)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('active-observation-site-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('우리집').last);
    await tester.pumpAndSettle();
    expect(selectedSite, 'home');
    expect(selectedCurrent, 0);

    await tester.tap(find.byKey(const Key('active-observation-site-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('현재 위치 (임시)').last);
    await tester.pumpAndSettle();
    expect(selectedCurrent, 1);
  });
}

import 'package:astro_journal/data/models/blocked_azimuth_range.dart';
import 'package:astro_journal/data/models/horizon_point.dart';
import 'package:astro_journal/data/models/observation_site.dart';
import 'package:astro_journal/data/repositories/observation_site_repository.dart';
import 'package:astro_journal/features/observation_site/models/active_observation_site.dart';
import 'package:astro_journal/features/observation_site/viewmodel/active_observation_site_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

class _Repository implements ObservationSiteRepository {
  final List<ObservationSite> sites = [];
  String? markedId;

  @override
  Future<List<ObservationSite>> list({bool includeDeleted = false}) async =>
      List.of(sites);
  @override
  Future<ObservationSite?> get(
    String id, {
    bool includeDeleted = false,
  }) async => sites.where((site) => site.id == id).firstOrNull;
  @override
  Future<void> markLastUsed(String id, DateTime usedAt) async {
    markedId = id;
    final index = sites.indexWhere((site) => site.id == id);
    sites[index] = sites[index].copyWith(lastUsedAt: usedAt);
  }

  @override
  Future<void> create(ObservationSite site) async => sites.add(site);
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

ObservationSite _site(
  String id, {
  DateTime? lastUsedAt,
  bool favorite = false,
}) => ObservationSite(
  id: id,
  name: id,
  latitude: 37.5,
  longitude: 127,
  isFavorite: favorite,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  lastUsedAt: lastUsedAt,
);

void main() {
  test('starts with a temporary current-location site', () {
    final viewModel = ActiveObservationSiteViewModel(_Repository());
    expect(viewModel.active.kind, ActiveObservationSiteKind.currentLocation);
    expect(viewModel.active.selectedSiteId, isNull);
  });

  test(
    'selecting a saved site marks lastUsed and preserves identity',
    () async {
      final repository = _Repository()..sites.add(_site('home'));
      final viewModel = ActiveObservationSiteViewModel(repository);
      await viewModel.load();
      await viewModel.selectSavedSite(repository.sites.single);
      expect(repository.markedId, 'home');
      expect(viewModel.active.selectedSiteId, 'home');
      expect(viewModel.active.site!.lastUsedAt, isNotNull);
    },
  );

  test('recent sites sort before favorite and name', () async {
    final repository = _Repository()
      ..sites.addAll([
        _site('favorite', favorite: true),
        _site('recent', lastUsedAt: DateTime(2026, 8, 1)),
        _site('alpha'),
      ]);
    final viewModel = ActiveObservationSiteViewModel(repository);
    await viewModel.load();
    expect(viewModel.sites.map((site) => site.id), [
      'recent',
      'favorite',
      'alpha',
    ]);
  });
}

import 'package:astro_journal/core/services/observation_context_invalidator.dart';
import 'package:astro_journal/core/services/performance_probe.dart';
import 'package:astro_journal/data/datasources/equipment_local_datasource.dart';
import 'package:astro_journal/data/datasources/observation_site_local_datasource.dart';
import 'package:astro_journal/data/models/imaging_suitability_assessment.dart';
import 'package:astro_journal/data/models/horizon_point.dart';
import 'package:astro_journal/data/models/observation_site.dart';
import 'package:astro_journal/data/repositories/equipment_repository_impl.dart';
import 'package:astro_journal/data/repositories/observation_site_repository.dart';
import 'package:astro_journal/data/repositories/observation_site_repository_impl.dart';
import 'package:astro_journal/features/observation_site/viewmodel/active_observation_site_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

class _EquipmentDataSource extends EquipmentLocalDataSource {
  @override
  Future<void> delete(String id) async {}
}

class _SiteDataSource extends ObservationSiteLocalDataSource {
  int creates = 0;
  final List<ObservationSite> sites = [];

  @override
  Future<void> create(ObservationSite site) async {
    creates++;
    sites.add(site);
  }

  @override
  Future<List<ObservationSite>> list({bool includeDeleted = false}) async =>
      List<ObservationSite>.from(sites);

  @override
  Future<void> replaceHorizonPoints(
    String siteId,
    List<HorizonPoint> points,
  ) async {}
}

class _SiteRepository implements ObservationSiteRepository {
  _SiteRepository(this.site);

  final ObservationSite site;

  @override
  Future<List<ObservationSite>> list({bool includeDeleted = false}) async => [
    site,
  ];

  @override
  Future<void> markLastUsed(String id, DateTime usedAt) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('user context changes enter one serialized rebuild pipeline', () async {
    final invalidator = ObservationContextInvalidator();
    final changes = <ObservationContextChange>[];
    invalidator.bind((change, _) async => changes.add(change));

    final now = DateTime(2026, 8, 26);
    final site = ObservationSite(
      id: 'site-1',
      name: 'Test site',
      latitude: 37.5,
      longitude: 127,
      trackingMode: TrackingMode.altAz,
      defaultMinAltitude: 20,
      createdAt: now,
      updatedAt: now,
    );
    final active = ActiveObservationSiteViewModel(
      _SiteRepository(site),
      contextInvalidator: invalidator,
    );

    await active.load();
    await active.selectSavedSite(site);
    await active.setTemporaryTrackingOverride(TrackingMode.eq);
    await active.setTemporaryEquipmentOverride('equipment-1');
    await EquipmentRepositoryImpl(
      dataSource: _EquipmentDataSource(),
      contextInvalidator: invalidator,
    ).delete('equipment-1');
    final sites = ObservationSiteRepositoryImpl(
      dataSource: _SiteDataSource(),
      contextInvalidator: invalidator,
    );
    await sites.create(site);
    await sites.replaceHorizonPoints('site-1', const []);

    expect(changes, [
      ObservationContextChange.activeSite,
      ObservationContextChange.trackingMode,
      ObservationContextChange.equipment,
      ObservationContextChange.equipment,
      ObservationContextChange.observationSite,
      ObservationContextChange.horizon,
    ]);
    expect(invalidator.revision, 6);
  });

  test('disposing an old binding does not remove its replacement', () async {
    final invalidator = ObservationContextInvalidator();
    var oldCalls = 0;
    var replacementCalls = 0;
    final oldToken = invalidator.bind((_, _) async => oldCalls++);
    invalidator.bind((_, _) async => replacementCalls++);

    invalidator.unbind(oldToken);
    await invalidator.invalidate(ObservationContextChange.equipment);

    expect(oldCalls, 0);
    expect(replacementCalls, 1);
  });

  test('map favorite creation does not invalidate observation context', () async {
    final invalidator = ObservationContextInvalidator();
    final changes = <ObservationContextChange>[];
    invalidator.bind((change, _) async => changes.add(change));
    final dataSource = _SiteDataSource();
    final repository = ObservationSiteRepositoryImpl(
      dataSource: dataSource,
      contextInvalidator: invalidator,
    );
    final now = DateTime(2026, 8, 27);

    await repository.createFavorite(
      ObservationSite(
        id: 'map-favorite',
        name: 'Map favorite',
        latitude: 37.5,
        longitude: 127,
        createdAt: now,
        updatedAt: now,
      ),
    );

    expect(changes, isEmpty);
    expect(invalidator.revision, 0);
    expect(dataSource.creates, 1);
  });

  test(
    'map favorite refreshes Home site collection without context rebuild',
    () async {
      final invalidator = ObservationContextInvalidator();
      final dataSource = _SiteDataSource();
      late ActiveObservationSiteViewModel activeSites;
      final repository = ObservationSiteRepositoryImpl(
        dataSource: dataSource,
        contextInvalidator: invalidator,
        onCollectionChanged: () => activeSites.load(force: true),
      );
      activeSites = ActiveObservationSiteViewModel(
        repository,
        contextInvalidator: invalidator,
      );
      await activeSites.load();
      expect(activeSites.sites, isEmpty);

      final now = DateTime(2026, 8, 27);
      await repository.createFavorite(
        ObservationSite(
          id: 'map-favorite',
          name: 'Map favorite',
          latitude: 37.5,
          longitude: 127,
          createdAt: now,
          updatedAt: now,
        ),
      );

      expect(activeSites.sites.single.id, 'map-favorite');
      expect(activeSites.active.isCurrentLocation, isTrue);
      expect(invalidator.revision, 0);
    },
  );

  test('performance probe aggregates count, total and maximum', () {
    PerformanceProbe.reset();

    PerformanceProbe.record('diagnostic', const Duration(milliseconds: 12));
    PerformanceProbe.record('diagnostic', const Duration(milliseconds: 55));

    final stats = PerformanceProbe.stats('diagnostic');
    expect(stats.count, 2);
    expect(stats.totalElapsedMs, 67);
    expect(stats.maxElapsedMs, 55);
    expect(stats.averageElapsedMs, 33.5);
  });
}

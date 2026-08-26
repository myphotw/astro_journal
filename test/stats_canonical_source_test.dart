import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/data/datasources/gallery_record_link_datasource.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/exif_info.dart';
import 'package:astro_journal/data/models/gallery_item.dart';
import 'package:astro_journal/data/models/shooting_record.dart';
import 'package:astro_journal/data/repositories/catalog_repository.dart';
import 'package:astro_journal/data/repositories/gallery_repository.dart';
import 'package:astro_journal/data/repositories/gallery_shooting_record_repository_adapter.dart';
import 'package:astro_journal/data/repositories/shooting_record_repository.dart';
import 'package:astro_journal/features/stats/viewmodel/stats_view_model.dart';
import 'package:astro_journal/services/catalog_search_service.dart';
import 'package:astro_journal/services/stats_analytics_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/source_text_helper.dart';

void main() {
  const catalog = [
    CatalogObject(
      id: 'M54',
      number: 54,
      catalog: CatalogType.messier,
      name: 'Sagittarius Cluster',
      type: 'Globular Cluster',
      constellation: 'Sagittarius',
      ra: '-',
      dec: '-',
      magnitude: '-',
    ),
    CatalogObject(
      id: 'NGC7293',
      number: 7293,
      catalog: CatalogType.ngc,
      name: 'Helix Nebula',
      type: 'Planetary Nebula',
      constellation: 'Aquarius',
      ra: '-',
      dec: '-',
      magnitude: '-',
    ),
  ];
  final capturedAt = DateTime(2026, 8, 20, 22);

  test('production StatsViewModel uses the canonical Gallery adapter', () {
    final providers = readSourceText('lib/core/di/app_providers.dart');
    expect(
      providers,
      contains(
        'final statsViewModel = StatsViewModel(\n'
        '      galleryShootingRecordRepository,',
      ),
    );
  });

  _Harness harness({
    List<ShootingRecord> local = const [],
    List<GalleryItem> remote = const [],
    Map<String, String> links = const {},
  }) {
    final localRepository = _LocalRecords(local);
    final gallery = _Gallery(
      GallerySnapshot(
        items: remote,
        source: remote.isEmpty
            ? GallerySnapshotSource.none
            : GallerySnapshotSource.remote,
        backendEnabled: true,
      ),
    );
    final catalogRepository = _Catalog(catalog);
    final canonical = GalleryShootingRecordRepositoryAdapter(
      galleryRepository: gallery,
      localRepository: localRepository,
      catalogRepository: catalogRepository,
      projectionMapper: GalleryObservationProjectionMapper(
        CatalogSearchService(),
      ),
      linkDataSource: _Links(links),
    );
    return _Harness(
      gallery,
      localRepository,
      canonical,
      StatsViewModel(canonical, catalogRepository, StatsAnalyticsService()),
    );
  }

  test('local-only pending record is included', () async {
    final result = harness(
      local: [_local('local-m54', 'M54', capturedAt, exposure: '10분')],
    );

    await result.stats.load();

    expect(result.stats.kpi?.totalShootCount, 1);
    expect(result.stats.kpi?.totalTargetCount, 1);
    expect(result.stats.kpi?.totalIntegrationSeconds, 600);
    expect(
      result.stats.categoryProgress
          .firstWhere((item) => item.type == CatalogType.messier)
          .captured,
      1,
    );
  });

  test('remote-only record is included without a local projection', () async {
    final result = harness(
      remote: [_remote('remote-m54', 'sha-m54', 'M54', capturedAt)],
    );

    await result.stats.load();

    expect(result.stats.kpi?.totalShootCount, 1);
    expect(result.stats.kpi?.totalTargetCount, 1);
    expect(result.stats.topTargets.single.objectId, 'M54');
    expect(
      result.stats.categoryProgress
          .firstWhere((item) => item.type == CatalogType.messier)
          .captured,
      1,
    );
  });

  test(
    'linked local and remote record is deduplicated beside pending local',
    () async {
      final result = harness(
        local: [
          _local('local-m54', 'M54', capturedAt, exposure: '10분'),
          _local(
            'local-ngc7293',
            'NGC7293',
            capturedAt.add(const Duration(days: 1)),
            exposure: '20분',
          ),
        ],
        remote: [_remote('remote-m54', 'sha-m54', 'M54', capturedAt)],
        links: const {'remote-m54': 'local-m54'},
      );

      final canonicalRecords = await result.canonical.getAll();
      await result.stats.load();

      expect(canonicalRecords, hasLength(2));
      expect(result.stats.kpi?.totalShootCount, canonicalRecords.length);
      expect(result.stats.kpi?.totalTargetCount, 2);
      expect(result.stats.kpi?.totalIntegrationSeconds, 1800);
      expect(result.stats.monthlyStats[7].shootCount, 2);
      expect(result.stats.monthlyStats[7].integrationSeconds, 1800);
      expect(result.stats.topTargets.first.objectId, 'NGC7293');
      expect(result.stats.topTargets.first.integrationSeconds, 1200);
      expect(
        result.stats.categoryProgress
            .firstWhere((item) => item.type == CatalogType.messier)
            .captured,
        1,
      );
      expect(
        result.stats.categoryProgress
            .firstWhere((item) => item.type == CatalogType.ngc)
            .captured,
        1,
      );
    },
  );

  test('reset source reloads the dashboard to zero', () async {
    final result = harness(
      local: [_local('local-m54', 'M54', capturedAt, exposure: '10분')],
      remote: [_remote('remote-m54', 'sha-m54', 'M54', capturedAt)],
      links: const {'remote-m54': 'local-m54'},
    );
    await result.stats.load();
    expect(result.stats.kpi?.totalShootCount, 1);

    result.local.records.clear();
    result.gallery.snapshot = const GallerySnapshot(
      items: [],
      source: GallerySnapshotSource.none,
      backendEnabled: true,
    );
    await result.stats.load();

    expect(result.stats.kpi?.totalShootCount, 0);
    expect(result.stats.kpi?.totalTargetCount, 0);
    expect(result.stats.kpi?.totalIntegrationSeconds, 0);
    expect(
      result.stats.categoryProgress.every((item) => item.captured == 0),
      isTrue,
    );
  });
}

GalleryItem _remote(
  String recordId,
  String fileId,
  String catalogId,
  DateTime capturedAt,
) => GalleryItem(
  backendRecordId: recordId,
  revision: 1,
  catalogObjectId: catalogId,
  capturedAt: capturedAt,
  favorite: false,
  representative: false,
  backendFileId: fileId,
  thumbnailUrl: '/thumbnail/$fileId',
  previewUrl: '/preview/$fileId',
  originalUrl: '/original/$fileId',
);

ShootingRecord _local(
  String id,
  String catalogId,
  DateTime capturedAt, {
  required String exposure,
}) => ShootingRecord(
  id: id,
  celestialObjectId: catalogId,
  capturedAt: capturedAt,
  createdAt: capturedAt,
  photoUri: '/local/$id.jpg',
  exif: ExifInfo(
    filename: '$id.jpg',
    size: '1MB',
    date: capturedAt.toIso8601String(),
    equipment: 'Seestar',
    focal: '150mm',
    fstop: 'f/5',
    exposure: exposure,
    iso: 'ISO 100',
    resolution: '1920x1080',
  ),
);

class _Harness {
  const _Harness(this.gallery, this.local, this.canonical, this.stats);

  final _Gallery gallery;
  final _LocalRecords local;
  final GalleryShootingRecordRepositoryAdapter canonical;
  final StatsViewModel stats;
}

class _Gallery implements GalleryRepository {
  _Gallery(this.snapshot);

  GallerySnapshot snapshot;

  @override
  Future<GallerySnapshot> getSnapshot({bool forceRefresh = false}) async =>
      snapshot;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LocalRecords implements ShootingRecordRepository {
  _LocalRecords(List<ShootingRecord> records)
    : records = List<ShootingRecord>.from(records);

  final List<ShootingRecord> records;

  @override
  Future<List<ShootingRecord>> getAll() async => records;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Catalog implements CatalogRepository {
  const _Catalog(this.objects);

  final List<CatalogObject> objects;

  @override
  Future<List<CatalogObject>> getAll({bool listOnly = true}) async => objects;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Links implements GalleryRecordLinkDataSource {
  const _Links(this.links);

  final Map<String, String> links;

  @override
  Future<Map<String, String>> localIdsByBackendRecordId() async => links;
}

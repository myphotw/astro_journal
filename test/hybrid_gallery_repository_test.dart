import 'dart:convert';

import 'package:astro_journal/data/datasources/gallery_cache_local_datasource.dart';
import 'package:astro_journal/data/datasources/remote_gallery_datasource.dart';
import 'package:astro_journal/data/models/gallery_item.dart';
import 'package:astro_journal/data/models/plate_solve_queue.dart';
import 'package:astro_journal/data/models/plate_solve_result.dart';
import 'package:astro_journal/data/repositories/hybrid_gallery_repository.dart';
import 'package:astro_journal/services/tc_backend_settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final now = DateTime.utc(2026, 8, 7, 12);
  late TcBackendSettingsService settings;
  late _FakeCache cache;
  late _FakeRemote remote;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = TcBackendSettingsService();
    await settings.save(
      const TcBackendSettings(baseUrl: 'https://backend.test', enabled: true),
    );
    cache = _FakeCache();
    remote = _FakeRemote();
  });

  HybridGalleryRepository repository() => HybridGalleryRepository(
    settingsService: settings,
    cache: cache,
    remoteFactory: (_) => remote,
    now: () => now,
  );

  test('remote result is returned and cached', () async {
    remote.items = [_item('remote')];

    final result = await repository().getAll();

    expect(result.single.backendFileId, 'remote');
    expect(result.single.syncedAt, now);
    expect(remote.galleryCalls, 1);
    expect(cache.entries['astro:gallery:list'], isNotNull);
  });

  test('fresh cache is returned without backend call', () async {
    cache.putItems('astro:gallery:list', [_item('cached')], now);

    final result = await repository().getAll();

    expect(result.single.backendFileId, 'cached');
    expect(remote.galleryCalls, 0);
  });

  test('backend failure falls back to expired SQLite cache', () async {
    cache.putItems('astro:gallery:list', [
      _item('fallback'),
    ], now.subtract(const Duration(hours: 2)));
    remote.failure = const RemoteGalleryException('offline');

    final result = await repository().getAll();

    expect(remote.galleryCalls, 1);
    expect(result.single.backendFileId, 'fallback');
  });

  test('backend off uses SQLite cache only', () async {
    await settings.save(
      const TcBackendSettings(baseUrl: 'https://backend.test', enabled: false),
    );
    cache.putItems('astro:gallery:list', [
      _item('offline'),
    ], now.subtract(const Duration(days: 5)));

    final result = await repository().getAll();

    expect(result.single.backendFileId, 'offline');
    expect(remote.galleryCalls, 0);
  });

  test('expired cache refreshes from backend', () async {
    cache.putItems('astro:gallery:list', [
      _item('expired'),
    ], now.subtract(const Duration(minutes: 31)));
    remote.items = [_item('fresh')];

    final result = await repository().getAll();

    expect(remote.galleryCalls, 1);
    expect(result.single.backendFileId, 'fresh');
  });

  test(
    'remote list refresh preserves queue status learned by pull sync',
    () async {
      cache.putItems('astro:gallery:list', [
        _item('same', plateSolveStatus: PlateSolveQueueStatus.processing),
      ], now.subtract(const Duration(minutes: 31)));
      remote.items = [_item('same')];

      final result = await repository().getAll();

      expect(result.single.plateSolveStatus, PlateSolveQueueStatus.processing);
    },
  );

  test('remote list refresh preserves a cached completed WCS result', () async {
    cache.putItems('astro:gallery:list', [
      _item(
        'same',
        commonFileId: 178,
        plateSolveStatus: PlateSolveQueueStatus.completed,
        plateSolveJobId: 'job-1',
        plateSolve: PlateSolveResult.success(centerRa: 83.8, centerDec: -5.4),
      ),
    ], now.subtract(const Duration(minutes: 31)));
    remote.items = [
      _item(
        'same',
        commonFileId: 178,
        plateSolveStatus: PlateSolveQueueStatus.completed,
        plateSolveJobId: 'job-1',
      ),
    ];

    final result = await repository().getAll();

    expect(result.single.plateSolve?.centerRa, 83.8);
    expect(result.single.plateSolve?.centerDec, -5.4);
  });

  test(
    'completed detail without result is rehydrated and replaces local WCS',
    () async {
      final cached = _item(
        'cached',
        commonFileId: 178,
        plateSolveStatus: PlateSolveQueueStatus.completed,
        plateSolveJobId: 'job-1',
        plateSolve: PlateSolveResult.success(centerRa: 1, centerDec: 2),
      );
      // Simulate an old/incomplete detail cache whose persistent result was not
      // yet supported by the app.
      final payload = cached.toJson()..remove('plate_solve_result');
      cache.entries['astro:gallery:detail:record-cached'] = GalleryCacheEntry(
        key: 'astro:gallery:detail:record-cached',
        payloadJson: jsonEncode(payload),
        cachedAt: now,
      );
      remote.detail = _item(
        'cached',
        commonFileId: 178,
        plateSolveStatus: PlateSolveQueueStatus.completed,
        plateSolveJobId: 'job-1',
        plateSolve: PlateSolveResult.success(centerRa: 83.8, centerDec: -5.4),
      );

      final result = await repository().getById('record-cached');

      expect(remote.detailCalls, 1);
      expect(result?.plateSolve?.centerRa, 83.8);
      expect(result?.plateSolve?.centerDec, -5.4);
    },
  );

  test(
    'fresh detail cache without common file identity is rehydrated',
    () async {
      cache.putItems('unused', const [], now);
      cache.entries['astro:gallery:detail:record-cached'] = GalleryCacheEntry(
        key: 'astro:gallery:detail:record-cached',
        payloadJson: jsonEncode(_item('cached').toJson()),
        cachedAt: now,
      );
      remote.detail = _item('cached', commonFileId: 178);

      final result = await repository().getById('record-cached');

      expect(remote.detailCalls, 1);
      expect(result?.backendRecordId, 'record-cached');
      expect(result?.backendFileId, 'cached');
      expect(result?.commonFileId, 178);
    },
  );

  test('legacy Common Gallery cache key is not reused', () async {
    await settings.save(
      const TcBackendSettings(baseUrl: 'https://backend.test', enabled: false),
    );
    cache.putItems('gallery:list', [_item('legacy')], now);

    final result = await repository().getAll();

    expect(result, isEmpty);
    expect(remote.galleryCalls, 0);
  });

  test(
    'local mutation updates and deletes the durable Gallery cache',
    () async {
      await settings.save(
        const TcBackendSettings(
          baseUrl: 'https://backend.test',
          enabled: false,
        ),
      );
      cache.putItems('astro:gallery:list', [_item('cached')], now);
      final subject = repository();

      await subject.applyLocalPatch('record-cached', const {
        'favorite': true,
        'memo': 'local memo',
        'location_name': 'New site',
        'latitude': 37.55,
        'longitude': 126.98,
      }, revision: 2);
      final updated = (await subject.getAll()).single;
      expect(updated.favorite, isTrue);
      expect(updated.memo, 'local memo');
      expect(updated.location, 'New site');
      expect(updated.latitude, 37.55);
      expect(updated.longitude, 126.98);
      expect(updated.revision, 2);

      await subject.applyLocalDelete('record-cached');
      expect(await subject.getAll(), isEmpty);
    },
  );

  test('pull projection is revision-aware and tombstone-safe', () async {
    await settings.save(
      const TcBackendSettings(baseUrl: 'https://backend.test', enabled: false),
    );
    final subject = repository();
    final revision1 = _item('pulled');
    final revision2 = GalleryItem(
      backendRecordId: revision1.backendRecordId,
      revision: 2,
      catalogObjectId: revision1.catalogObjectId,
      capturedAt: revision1.capturedAt,
      favorite: true,
      representative: revision1.representative,
      backendFileId: revision1.backendFileId,
      thumbnailUrl: revision1.thumbnailUrl,
      previewUrl: revision1.previewUrl,
      originalUrl: revision1.originalUrl,
    );

    expect(await subject.upsertPulledItem(revision1), isTrue);
    expect(await subject.upsertPulledItem(revision1), isFalse);
    expect(await subject.upsertPulledItem(revision2), isTrue);
    expect(await subject.getCachedRevision('record-pulled'), 2);
    expect(
      await subject.applyPulledDelete(
        'record-pulled',
        revision: 3,
        deletedAt: now,
      ),
      isTrue,
    );
    expect(await subject.upsertPulledItem(revision2), isFalse);
    expect(await subject.getAll(), isEmpty);
  });
}

GalleryItem _item(
  String id, {
  int? commonFileId,
  PlateSolveQueueStatus? plateSolveStatus,
  String? plateSolveJobId,
  PlateSolveResult? plateSolve,
}) => GalleryItem(
  backendRecordId: 'record-$id',
  revision: 1,
  catalogObjectId: 'M42',
  capturedAt: DateTime.utc(2026, 8, 7),
  favorite: false,
  representative: false,
  backendFileId: id,
  commonFileId: commonFileId,
  plateSolveStatus: plateSolveStatus,
  plateSolveJobId: plateSolveJobId,
  plateSolve: plateSolve,
  thumbnailUrl: 'https://backend.test/thumbnail/$id',
  previewUrl: 'https://backend.test/preview/$id',
  originalUrl: 'https://backend.test/original/$id',
);

class _FakeCache implements GalleryCacheDataSource {
  final Map<String, GalleryCacheEntry> entries = {};

  void putItems(String key, List<GalleryItem> items, DateTime cachedAt) {
    entries[key] = GalleryCacheEntry(
      key: key,
      payloadJson: jsonEncode(items.map((item) => item.toJson()).toList()),
      cachedAt: cachedAt,
    );
  }

  @override
  Future<GalleryCacheEntry?> read(String key) async => entries[key];

  @override
  Future<void> write(GalleryCacheEntry entry) async {
    entries[entry.key] = entry;
  }
}

class _FakeRemote implements GalleryRemoteDataSource {
  int galleryCalls = 0;
  int detailCalls = 0;
  List<GalleryItem> items = const [];
  GalleryItem? detail;
  RemoteGalleryException? failure;

  @override
  Future<List<GalleryItem>> getGallery({Map<String, String>? query}) async {
    galleryCalls++;
    if (failure case final error?) throw error;
    return items;
  }

  @override
  Future<GalleryItem> getDetail(String fileId) async {
    detailCalls++;
    if (failure case final error?) throw error;
    return detail ?? _item(fileId);
  }
}

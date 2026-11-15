import 'dart:async';
import 'dart:convert';

import 'package:astro_journal/data/datasources/gallery_cache_local_datasource.dart';
import 'package:astro_journal/data/datasources/remote_gallery_datasource.dart';
import 'package:astro_journal/data/models/gallery_item.dart';
import 'package:astro_journal/data/models/tc_backend_change.dart';
import 'package:astro_journal/data/repositories/hybrid_gallery_repository.dart';
import 'package:astro_journal/services/tc_backend_settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late _Cache cache;
  late TcBackendSettingsService settings;
  late HybridGalleryRepository repository;
  late List<Map<String, dynamic>> rows;
  late List<int> pages;
  var now = DateTime.utc(2026, 11, 15);
  int? failAt;
  var status = 503;
  var changeTotal = false;
  var duplicate = false;
  var timeout = false;
  var wrongPage = false;
  var omitMetadata = false;
  var shortPage = false;
  var badTotal = false;
  Completer<void>? finalPageStarted;
  Completer<void>? releaseFinalPage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = TcBackendSettingsService();
    await settings.save(
      const TcBackendSettings(baseUrl: 'https://backend.test', enabled: true),
    );
    cache = _Cache();
    now = DateTime.utc(2026, 11, 15);
    rows = [for (var i = 0; i < 51; i++) _json(i)];
    pages = [];
    failAt = null;
    status = 503;
    changeTotal = duplicate = timeout = wrongPage = omitMetadata = shortPage =
        badTotal = false;
    finalPageStarted = releaseFinalPage = null;
    final client = MockClient((request) async {
      expect(request.url.path, '/api/astro/gallery');
      final page = int.parse(request.url.queryParameters['page']!);
      pages.add(page);
      if (page > 1) expect(request.url.queryParameters['page_size'], '20');
      if (page == failAt) {
        if (timeout) throw TimeoutException('test timeout');
        return http.Response('{}', status);
      }
      if (page == 3 && finalPageStarted != null) {
        finalPageStarted!.complete();
        await releaseFinalPage!.future;
      }
      var items = rows.skip((page - 1) * 20).take(20).toList();
      if (shortPage && page == 2) items = items.take(19).toList();
      if (duplicate && page == 3) {
        items = [
          {...rows.first, 'revision': 2},
          ...items,
        ];
      }
      return http.Response(
        jsonEncode({
          'items': items,
          if (!omitMetadata) ...{
            'total': changeTotal && page == 2
                ? rows.length + 1
                : badTotal
                ? rows.length + 1
                : rows.length,
            'page': wrongPage && page == 2 ? 1 : page,
            'page_size': 20,
          },
        }),
        200,
      );
    });
    repository = HybridGalleryRepository(
      settingsService: settings,
      cache: cache,
      now: () => now,
      remoteFactory: (url) =>
          RemoteGalleryDataSource(baseUrl: url, client: client),
    );
  });

  test(
    '51 records require three real HTTP pages before committing snapshot',
    () async {
      finalPageStarted = Completer<void>();
      releaseFinalPage = Completer<void>();
      final pending = repository.getSnapshot();
      await finalPageStarted!.future;
      expect(pages, [1, 2, 3]);
      expect(cache.entries['astro:gallery:list'], isNull);
      expect(cache.entries['astro:gallery:full_snapshot'], isNull);
      releaseFinalPage!.complete();
      final snapshot = await pending;
      expect(snapshot.items, hasLength(51));
      expect(snapshot.items.map((i) => i.backendRecordId), [
        for (var i = 0; i < 51; i++) 'r$i',
      ]);
      expect(
        jsonDecode(cache.entries['astro:gallery:full_snapshot']!.payloadJson),
        {'completed': true},
      );
    },
  );

  for (final page in [2, 3]) {
    for (final error in [401, 403, 429, 500, 503, 0]) {
      test(
        'page $page error $error preserves expired snapshot plus incremental rows',
        () async {
          await repository.getSnapshot();
          await repository.upsertPulledItem(GalleryItem.fromJson(_json(99)));
          final listBefore = cache.entries['astro:gallery:list'];
          final markerBefore = cache.entries['astro:gallery:full_snapshot'];
          now = now.add(const Duration(minutes: 31));
          pages.clear();
          failAt = page;
          status = error;
          timeout = error == 0;
          final snapshot = await repository.getSnapshot();
          expect(snapshot.remoteFailed, isTrue);
          expect(snapshot.items, hasLength(52));
          expect(cache.entries['astro:gallery:list'], same(listBefore));
          expect(
            cache.entries['astro:gallery:full_snapshot'],
            same(markerBefore),
          );
          expect(pages, page == 2 ? [1, 2] : [1, 2, 3]);
        },
      );
    }
  }

  test(
    'failure without a snapshot marker preserves partial incremental cache',
    () async {
      await repository.upsertPulledItem(GalleryItem.fromJson(_json(99)));
      final before = cache.entries['astro:gallery:list'];
      failAt = 2;
      final snapshot = await repository.getSnapshot();
      expect(snapshot.remoteFailed, isTrue);
      expect(snapshot.items.single.backendRecordId, 'r99');
      expect(cache.entries['astro:gallery:list'], same(before));
      expect(cache.entries['astro:gallery:full_snapshot'], isNull);
    },
  );

  for (final error in [
    'total changed',
    'count mismatch',
    'wrong page',
    'missing metadata',
    'short page',
  ]) {
    test('$error cannot commit an incomplete snapshot', () async {
      changeTotal = error == 'total changed';
      badTotal = error == 'count mismatch';
      wrongPage = error == 'wrong page';
      omitMetadata = error == 'missing metadata';
      shortPage = error == 'short page';
      final snapshot = await repository.getSnapshot();
      expect(snapshot.remoteFailed, isTrue);
      expect(cache.entries['astro:gallery:full_snapshot'], isNull);
      expect(cache.entries['astro:gallery:list'], isNull);
    });
  }

  test(
    'duplicate IDs deduplicate with first-seen order and newer revision',
    () async {
      duplicate = true;
      final snapshot = await repository.getSnapshot();
      expect(snapshot.items, hasLength(51));
      expect(snapshot.items.first.backendRecordId, 'r0');
      expect(snapshot.items.first.revision, 2);
      expect(
        snapshot.items.map((i) => i.backendRecordId).toSet(),
        hasLength(51),
      );
    },
  );

  test(
    'duplicate replacing an expected unique item is rejected by total check',
    () async {
      rows[50] = rows.first;
      final snapshot = await repository.getSnapshot();
      expect(snapshot.remoteFailed, isTrue);
      expect(cache.entries['astro:gallery:full_snapshot'], isNull);
    },
  );

  test(
    'TTL expiration fetches all pages again without shrinking the list',
    () async {
      expect((await repository.getSnapshot()).items, hasLength(51));
      final marker = cache.entries['astro:gallery:full_snapshot'];
      expect((await repository.getSnapshot()).items, hasLength(51));
      expect(pages, [1, 2, 3]);
      now = now.add(const Duration(minutes: 31));
      expect((await repository.getSnapshot()).items, hasLength(51));
      expect(pages, [1, 2, 3, 1, 2, 3]);
      expect(cache.entries['astro:gallery:full_snapshot'], isNot(same(marker)));
    },
  );

  test('empty complete gallery is valid', () async {
    rows.clear();
    final snapshot = await repository.getSnapshot();
    expect(snapshot.remoteFailed, isFalse);
    expect(snapshot.items, isEmpty);
    expect(pages, [1]);
    expect(cache.entries['astro:gallery:full_snapshot'], isNotNull);
  });

  test(
    'pagination preserves cursor, hard tombstone and visibility markers',
    () async {
      await repository.applyPulledDelete('r0', revision: 1);
      await repository.applyPulledHidden(
        'r1',
        revision: 1,
        state: TcBackendResourceState.unavailable,
      );
      await repository.applyPulledHidden(
        'r2',
        revision: 1,
        state: TcBackendResourceState.missing,
      );
      final cursor = GalleryCacheEntry(
        key: 'sync:checkpoint:common_changes:AstroJournal',
        payloadJson: '{"cursor":"77"}',
        cachedAt: now,
      );
      await cache.write(cursor);
      final protected = Map.of(cache.entries);
      final snapshot = await repository.getSnapshot();
      expect(snapshot.items, hasLength(48));
      for (final entry in protected.entries) {
        if (entry.key == 'astro:gallery:list') continue;
        expect(cache.entries[entry.key], same(entry.value));
      }
      expect(
        await repository.upsertPulledItem(
          GalleryItem.fromJson(_json(0, revision: 2)),
        ),
        isFalse,
      );
      expect(
        await repository.upsertPulledItem(GalleryItem.fromJson(_json(1))),
        isTrue,
      );
      expect(
        await repository.upsertPulledItem(GalleryItem.fromJson(_json(2))),
        isTrue,
      );
      expect((await repository.getCachedSnapshot()).items, hasLength(50));
    },
  );
}

Map<String, dynamic> _json(int index, {int revision = 1}) => {
  'record_id': 'r$index',
  'revision': revision,
  'catalog_object_id': 'M42',
  'captured_at': '2026-11-15T00:00:00Z',
  'favorite': false,
  'representative': false,
  'file_id': 'sha$index',
  'thumbnail_url': '/thumbnail/$index',
  'preview_url': '/preview/$index',
  'original_url': '/original/$index',
};

class _Cache implements GalleryCacheDataSource {
  final Map<String, GalleryCacheEntry> entries = {};
  @override
  Future<GalleryCacheEntry?> read(String key) async => entries[key];
  @override
  Future<void> write(GalleryCacheEntry entry) async {
    entries[entry.key] = entry;
  }
}

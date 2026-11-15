import 'dart:convert';
import 'dart:io';

import 'package:astro_journal/data/datasources/gallery_cache_local_datasource.dart';
import 'package:astro_journal/data/datasources/gallery_record_link_datasource.dart';
import 'package:astro_journal/data/datasources/sync_checkpoint_datasource.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/gallery_item.dart';
import 'package:astro_journal/data/models/shooting_record.dart';
import 'package:astro_journal/data/models/tc_backend_change.dart';
import 'package:astro_journal/data/repositories/catalog_repository.dart';
import 'package:astro_journal/data/repositories/gallery_shooting_record_repository_adapter.dart';
import 'package:astro_journal/data/repositories/hybrid_gallery_repository.dart';
import 'package:astro_journal/data/repositories/shooting_record_repository.dart';
import 'package:astro_journal/features/gallery/viewmodel/gallery_view_model.dart';
import 'package:astro_journal/services/catalog_search_service.dart';
import 'package:astro_journal/services/catalog_capture_projection_service.dart';
import 'package:astro_journal/services/tc_backend_changes_service.dart';
import 'package:astro_journal/services/tc_backend_pull_sync_coordinator.dart';
import 'package:astro_journal/services/tc_backend_settings_service.dart';
import 'package:astro_journal/services/tc_backend_sync_gate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory directory;
  late Database db;
  late GalleryCacheLocalDataSource cache;
  late HybridGalleryRepository repository;
  late GalleryViewModel viewModel;
  late TcBackendSettingsService settings;
  late _Checkpoints checkpoints;
  late _Api api;
  var refreshes = 0;
  var remoteRequests = 0;
  var clock = DateTime.utc(2026, 11, 15);

  void buildRepositories() {
    cache = GalleryCacheLocalDataSource(database: db);
    repository = HybridGalleryRepository(
      settingsService: settings,
      cache: cache,
      now: () => clock,
      remoteFactory: (_) {
        remoteRequests++;
        throw StateError('Unexpected full snapshot request');
      },
    );
    checkpoints = _Checkpoints(GalleryCacheSyncCheckpointDataSource(cache));
    final search = CatalogSearchService();
    final catalog = _Catalog();
    viewModel = GalleryViewModel(
      GalleryShootingRecordRepositoryAdapter(
        galleryRepository: repository,
        localRepository: _Records(),
        catalogRepository: catalog,
        projectionMapper: GalleryObservationProjectionMapper(search),
      ),
      catalog,
      search,
    );
  }

  Future<void> restart() async {
    viewModel.dispose();
    await db.close();
    db = await databaseFactory.openDatabase('${directory.path}/gallery.db');
    buildRepositories();
  }

  Future<void> drain(List<TcBackendChange> changes) async {
    api.events = changes;
    await TcBackendPullSyncCoordinator(
      changesApi: api,
      checkpoints: checkpoints,
      galleryRepository: repository,
      shootingRecordRepository: _Records(),
      recordLinks: const EmptyGalleryRecordLinkDataSource(),
      settingsService: settings,
      syncGate: TcBackendSyncGate(),
      catalogCaptureProjection: CatalogCaptureProjectionService(
        catalogRepository: _Catalog(),
        localRecords: _Records(),
        galleryRepository: repository,
      ),
      onObservationRecordsChanged: () async {
        refreshes++;
        await viewModel.load(silent: true, afterPull: true);
      },
    ).drain();
  }

  Future<void> expectVisible(bool visible) async {
    expect(
      (await repository.getCachedSnapshot()).items,
      hasLength(visible ? 1 : 0),
    );
    expect(viewModel.filteredRecords, hasLength(visible ? 1 : 0));
  }

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    clock = DateTime.utc(2026, 11, 15);
    SharedPreferences.setMockInitialValues({});
    settings = TcBackendSettingsService();
    await settings.save(
      const TcBackendSettings(baseUrl: 'https://backend.test', enabled: true),
    );
    directory = await Directory.systemTemp.createTemp('astro-visibility-test-');
    db = await databaseFactory.openDatabase('${directory.path}/gallery.db');
    await db.execute(
      'CREATE TABLE gallery_cache (cache_key TEXT PRIMARY KEY, payload_json TEXT NOT NULL, cached_at TEXT NOT NULL)',
    );
    api = _Api();
    refreshes = 0;
    remoteRequests = 0;
    buildRepositories();
    // Existing snapshot, not a confirmed recovery response.
    await cache.write(
      GalleryCacheEntry(
        key: 'astro:gallery:list',
        payloadJson: jsonEncode([_item(5).toJson()]),
        cachedAt: DateTime.now(),
      ),
    );
    await viewModel.load(silent: true, afterPull: true);
  });

  tearDown(() async {
    viewModel.dispose();
    await db.close();
    await directory.delete(recursive: true);
  });

  test(
    'actual Backend SQLite recovery pages feed Android parser and coordinator',
    () async {
      final fixture =
          jsonDecode(
                await File(
                  Platform.environment['ASTRO_VISIBILITY_FIXTURE']!,
                ).readAsString(),
              )
              as Map;
      final id = fixture['record_id'] as String;
      final pages = fixture['pages'] as List;
      await repository.applyLocalDelete(
        'r',
      ); // Replace this fixture's seeded row.
      api.detailRecordId = id;
      await repository.applyPulledHidden(
        id,
        revision: 5,
        state: TcBackendResourceState.unavailable,
      );
      Future<List<TcBackendChange>> parse(int index) async {
        final parser = TcBackendChangesService(
          settingsService: settings,
          client: MockClient(
            (_) async => http.Response(jsonEncode(pages[index]), 200),
          ),
        );
        final page = await parser.getChanges();
        api.nextCursorOverride = page.nextCursor;
        return page.changes;
      }

      await drain(await parse(0)); // StoragePlugin file recovery, revision 5.
      expect(
        await checkpoints.readCursor(TcBackendPullSyncCoordinator.streamName),
        (pages[0] as Map)['next_cursor'].toString(),
      );
      expect(
        (await repository.getCachedSnapshot()).items.single.backendRecordId,
        id,
      );
      api.error = const TcBackendChangesException(
        'raced detail',
        statusCode: 404,
      );
      await drain(await parse(1)); // HashPlugin link recovery, detail race.
      expect(await repository.getHiddenRevision(id), 5);
      api.error = null;
      await drain(
        await parse(2),
      ); // Second real link recovery at higher cursor.
      expect(await repository.getHiddenRevision(id), isNull);
      expect((await repository.getCachedSnapshot()).items.single.revision, 5);
      await drain(
        await parse(0),
      ); // Duplicate old recovery cannot override newer state.
      await drain(await parse(3)); // Actual ObservationRecordService DELETE.
      expect(await repository.getAuthoritativeDeleteRevision(id), 6);
      await drain(await parse(2));
      expect((await repository.getCachedSnapshot()).items, isEmpty);
    },
    skip: Platform.environment['ASTRO_VISIBILITY_FIXTURE'] == null
        ? 'Run Backend test_export_actual_sqlite_recovery_pages_for_android_contract and provide ASTRO_VISIBILITY_FIXTURE'
        : false,
  );

  test(
    'visibility cursor orders same-revision transitions and survives restart',
    () async {
      await drain([_visibility(TcBackendResourceState.active, '100')]);
      await expectVisible(true);
      await drain([_visibility(TcBackendResourceState.unavailable, '101')]);
      await expectVisible(false);
      await restart();
      await viewModel.load(silent: true, afterPull: true);
      await drain([_visibility(TcBackendResourceState.active, '100')]);
      await expectVisible(false);
      await drain([_visibility(TcBackendResourceState.active, '102')]);
      await expectVisible(true);
      final calls = api.detailCalls;
      await drain([_visibility(TcBackendResourceState.active, '102')]);
      expect(api.detailCalls, calls);
      await drain([_visibility(TcBackendResourceState.unavailable, '101')]);
      await expectVisible(true);
    },
  );

  test('visibility never undoes authoritative delete', () async {
    await drain([_event(TcBackendResourceState.deleted, 5)]);
    await drain([_visibility(TcBackendResourceState.active, '200')]);
    expect(api.detailCalls, 0);
    await expectVisible(false);
  });

  test(
    'visibility DELETED creates hard tombstone; unknown resource is skipped',
    () async {
      await drain([_visibility(TcBackendResourceState.deleted, '210')]);
      expect(await repository.getAuthoritativeDeleteRevision('r'), 5);
      await drain([_visibility(TcBackendResourceState.active, '211')]);
      await drain([
        const TcBackendChange(
          resourceType: 'FutureResource',
          resourceId: 'r',
          operation: TcBackendChangeOperation.update,
          cursor: '212',
        ),
      ]);
      expect(api.detailCalls, 0);
      await expectVisible(false);
      expect(
        await checkpoints.readCursor(TcBackendPullSyncCoordinator.streamName),
        isNotNull,
      );
    },
  );

  test(
    'visibility detail 404 is soft, newer equal-revision recovery succeeds',
    () async {
      api.error = const TcBackendChangesException('missing', statusCode: 404);
      await drain([_visibility(TcBackendResourceState.active, '100')]);
      expect(await repository.getAuthoritativeDeleteRevision('r'), isNull);
      await expectVisible(false);
      api.error = null;
      await drain([_visibility(TcBackendResourceState.active, '101')]);
      await expectVisible(true);
    },
  );

  test(
    'visibility null state falls back to detail, non-UPDATE ignored',
    () async {
      await drain([
        const TcBackendChange(
          resourceType: 'AstroGalleryVisibility',
          resourceId: 'r',
          operation: TcBackendChangeOperation.update,
          cursor: '300',
        ),
      ]);
      expect(api.detailCalls, 1);
      await expectVisible(true);
      await drain([
        const TcBackendChange(
          resourceType: 'AstroGalleryVisibility',
          resourceId: 'r',
          operation: TcBackendChangeOperation.delete,
          cursor: '301',
        ),
      ]);
      await expectVisible(true);
    },
  );

  test(
    'visibility transient errors preserve checkpoint and partial UI success',
    () async {
      for (final status in [401, 403, 429, 500, null]) {
        final before = await checkpoints.readCursor(
          TcBackendPullSyncCoordinator.streamName,
        );
        api.error = TcBackendChangesException('transient', statusCode: status);
        await expectLater(
          drain([_visibility(TcBackendResourceState.active, '400')]),
          throwsA(isA<TcBackendChangesException>()),
        );
        expect(
          await checkpoints.readCursor(TcBackendPullSyncCoordinator.streamName),
          before,
        );
      }
      api.error = null;
      // A later malformed event fails the page after one successful mutation.
      await expectLater(
        drain([
          _visibility(TcBackendResourceState.unavailable, '401'),
          const TcBackendChange(
            resourceType: 'AstroGalleryVisibility',
            resourceId: 'r',
            operation: TcBackendChangeOperation.update,
          ),
        ]),
        throwsA(isA<TcBackendChangesException>()),
      );
      await expectVisible(false);
    },
  );

  test('legacy hidden rechecks are bounded, durable and backed off', () async {
    for (var i = 0; i < 7; i++) {
      await repository.applyPulledHidden(
        'hidden-$i',
        revision: 5,
        state: TcBackendResourceState.missing,
      );
    }
    await repository.applyPulledDelete('hidden-0', revision: 5);
    expect(await repository.takeHiddenRechecks(), isEmpty);
    clock = clock.add(const Duration(minutes: 1));
    final first = await repository.takeHiddenRechecks();
    expect(first, hasLength(5));
    expect(first, isNot(contains('hidden-0')));
    await restart();
    final remaining = await repository.takeHiddenRechecks();
    expect(remaining, hasLength(1));
    expect(first.toSet().intersection(remaining.toSet()), isEmpty);
    expect(await repository.takeHiddenRechecks(), isEmpty);
    clock = clock.add(const Duration(minutes: 1));
    expect(await repository.takeHiddenRechecks(), hasLength(5));
    expect(await repository.takeHiddenRechecks(), hasLength(1));
    clock = clock.add(const Duration(minutes: 1));
    expect(
      await repository.takeHiddenRechecks(),
      isEmpty,
    ); // Second retry waits 2m.
  });

  test(
    'legacy hidden recheck restores without a new event or snapshot',
    () async {
      await drain([_event(TcBackendResourceState.unavailable, 5)]);
      await expectVisible(false);
      clock = clock.add(const Duration(minutes: 1));
      await drain([]);
      expect(api.detailCalls, 1);
      expect(remoteRequests, 0);
      await expectVisible(true);
    },
  );

  test(
    'legacy hidden recheck 404 backs off; server failure preserves checkpoint',
    () async {
      await drain([_event(TcBackendResourceState.unavailable, 5)]);
      clock = clock.add(const Duration(minutes: 1));
      api.error = const TcBackendChangesException('missing', statusCode: 404);
      await drain([]);
      expect(api.detailCalls, 1);
      await drain([]);
      expect(api.detailCalls, 1);
      clock = clock.add(const Duration(minutes: 1));
      final checkpoint = await checkpoints.readCursor(
        TcBackendPullSyncCoordinator.streamName,
      );
      api.error = const TcBackendChangesException('failed', statusCode: 500);
      await expectLater(drain([]), throwsA(isA<TcBackendChangesException>()));
      expect(
        await checkpoints.readCursor(TcBackendPullSyncCoordinator.streamName),
        checkpoint,
      );
    },
  );

  for (final state in [
    TcBackendResourceState.unavailable,
    TcBackendResourceState.missing,
  ]) {
    test(
      '$state 5 -> ACTIVE 5 restores cache and ViewModel, stale absence stays ignored',
      () async {
        await drain([_event(state, 5)]);
        await expectVisible(false);
        expect(api.detailCalls, 0);
        expect(await repository.getAuthoritativeDeleteRevision('r'), isNull);
        expect(await repository.getHiddenRevision('r'), 5);
        await drain([_event(TcBackendResourceState.active, 5)]);
        await expectVisible(true);
        expect(api.detailCalls, 1);
        expect(refreshes, 2);
        expect(await repository.getHiddenRevision('r'), isNull);
        await restart();
        await viewModel.load(silent: true, afterPull: true);
        await drain([_event(state, 5)]);
        await expectVisible(true);
        expect(api.detailCalls, 1);
        expect(refreshes, 2);
      },
    );
  }

  test('UNAVAILABLE 5 -> ACTIVE 6 restores', () async {
    await drain([_event(TcBackendResourceState.unavailable, 5)]);
    api.detailRevision = 6;
    await drain([_event(TcBackendResourceState.active, 6)]);
    await expectVisible(true);
    expect((await repository.getCachedSnapshot()).items.single.revision, 6);
  });

  test(
    'pull and Catalog reconciliation keep 51 incremental photos without remote snapshot',
    () async {
      for (var i = 0; i < 50; i++) {
        await repository.upsertPulledItem(
          GalleryItem.fromJson({
            ..._item(5).toJson(),
            'record_id': 'extra-$i',
            'file_id': 'file-$i',
          }),
        );
      }
      api.detailRevision = 6;
      await drain([_event(TcBackendResourceState.active, 6)]);
      expect((await repository.getCachedSnapshot()).items, hasLength(51));
      expect(viewModel.filteredRecords, hasLength(51));
      expect(remoteRequests, 0);
      expect(await cache.read('astro:gallery:full_snapshot'), isNull);
      await drain([]);
      expect(remoteRequests, 0);
    },
  );

  test('UNAVAILABLE 5 -> ACTIVE 4 skips detail and cannot restore', () async {
    await drain([_event(TcBackendResourceState.unavailable, 5)]);
    await drain([_event(TcBackendResourceState.active, 4)]);
    expect(api.detailCalls, 0);
    await expectVisible(false);
  });

  for (final revision in [5, 6]) {
    test('DELETED 5 blocks ACTIVE $revision and direct upsert', () async {
      await drain([_event(TcBackendResourceState.deleted, 5)]);
      await drain([_event(TcBackendResourceState.active, revision)]);
      expect(api.detailCalls, 0);
      expect(await repository.upsertPulledItem(_item(revision)), isFalse);
      expect(await repository.getAuthoritativeDeleteRevision('r'), 5);
      await expectVisible(false);
    });
  }

  test(
    'SQLite close and reopen retains hidden marker and allows equal ACTIVE',
    () async {
      await drain([_event(TcBackendResourceState.unavailable, 5)]);
      await restart();
      expect(await repository.getHiddenRevision('r'), 5);
      await drain([_event(TcBackendResourceState.active, 5)]);
      await expectVisible(true);
      expect(api.detailCalls, 1);
    },
  );

  test(
    'crash before page checkpoint then replay recovers idempotently',
    () async {
      checkpoints.fail = true;
      await expectLater(
        drain([_event(TcBackendResourceState.unavailable, 5)]),
        throwsStateError,
      );
      expect(
        await checkpoints.readCursor(TcBackendPullSyncCoordinator.streamName),
        isNull,
      );
      await restart();
      await drain([
        _event(TcBackendResourceState.unavailable, 5),
        _event(TcBackendResourceState.active, 5),
      ]);
      await expectVisible(true);
      expect(api.detailCalls, 1);
      expect(
        await checkpoints.readCursor(TcBackendPullSyncCoordinator.streamName),
        isNotNull,
      );
      await drain([
        _event(TcBackendResourceState.unavailable, 5),
        _event(TcBackendResourceState.active, 5),
      ]);
      await expectVisible(true);
      expect(api.detailCalls, 1);
    },
  );

  test('ACTIVE detail revision 4 cannot restore hidden revision 5', () async {
    await drain([_event(TcBackendResourceState.unavailable, 5)]);
    api.detailRevision = 4;
    await drain([_event(TcBackendResourceState.active, 5)]);
    expect(api.detailCalls, 1);
    expect(await repository.getHiddenRevision('r'), 5);
    await expectVisible(false);
  });

  test(
    'replay after ACTIVE writes but before checkpoint cannot hide recovery',
    () async {
      checkpoints.fail = true;
      final events = [
        _event(TcBackendResourceState.unavailable, 5),
        _event(TcBackendResourceState.active, 5),
      ];
      await expectLater(drain(events), throwsStateError);
      await expectVisible(true);
      expect(api.detailCalls, 1);
      await restart();
      await drain(events);
      await viewModel.load(silent: true, afterPull: true);
      await expectVisible(true);
      expect(api.detailCalls, 1);
    },
  );

  test(
    'legacy hard tombstone wins over concurrent soft marker and higher live data',
    () async {
      await drain([_event(TcBackendResourceState.missing, 5)]);
      await cache.write(
        GalleryCacheEntry(
          key: 'astro:gallery:tombstone:r',
          payloadJson: jsonEncode({'record_id': 'r', 'revision': 5}),
          cachedAt: DateTime.now(),
        ),
      );
      // Simulate a stale/full snapshot writing a higher live row beside both
      // markers. Actual DELETE must still dominate every gallery read path.
      await cache.write(
        GalleryCacheEntry(
          key: 'astro:gallery:list',
          payloadJson: jsonEncode([_item(6).toJson()]),
          cachedAt: DateTime.now(),
        ),
      );
      await cache.write(
        GalleryCacheEntry(
          key: 'astro:gallery:detail:r',
          payloadJson: jsonEncode(_item(6).toJson()),
          cachedAt: DateTime.now(),
        ),
      );
      await restart();
      await drain([_event(TcBackendResourceState.active, 6)]);
      expect(api.detailCalls, 0);
      expect(await repository.upsertPulledItem(_item(6)), isFalse);
      expect(await repository.getAuthoritativeDeleteRevision('r'), 5);
      expect(await repository.getById('r', forceRefresh: true), isNull);
      await expectVisible(false);
    },
  );

  test(
    'restart repairs interrupted higher ACTIVE writes before watermark',
    () async {
      await drain([_event(TcBackendResourceState.unavailable, 5)]);
      // Simulate a process exit after list/detail writes but before the final
      // ACTIVE watermark write. The next pull must finish the recovery.
      await cache.write(
        GalleryCacheEntry(
          key: 'astro:gallery:list',
          payloadJson: jsonEncode([_item(6).toJson()]),
          cachedAt: DateTime.now(),
        ),
      );
      await cache.write(
        GalleryCacheEntry(
          key: 'astro:gallery:detail:r',
          payloadJson: jsonEncode(_item(6).toJson()),
          cachedAt: DateTime.now(),
        ),
      );
      await restart();
      api.detailRevision = 6;
      await drain([_event(TcBackendResourceState.active, 6)]);
      await expectVisible(true);
      expect(api.detailCalls, 1);
      expect(await repository.getHiddenRevision('r'), isNull);
    },
  );

  test('higher DELETE removes recovered ACTIVE', () async {
    await drain([
      _event(TcBackendResourceState.missing, 5),
      _event(TcBackendResourceState.active, 5),
    ]);
    await drain([_event(TcBackendResourceState.deleted, 6)]);
    await expectVisible(false);
    expect(await repository.getAuthoritativeDeleteRevision('r'), 6);
  });

  test('detail errors retain soft marker and checkpoint', () async {
    await drain([_event(TcBackendResourceState.unavailable, 5)]);
    final cursor = await checkpoints.readCursor(
      TcBackendPullSyncCoordinator.streamName,
    );
    for (final status in [401, 403, 429, 500, null]) {
      api.error = TcBackendChangesException('detail error', statusCode: status);
      await expectLater(
        drain([_event(TcBackendResourceState.active, 5)]),
        throwsA(isA<TcBackendChangesException>()),
      );
      expect(
        await checkpoints.readCursor(TcBackendPullSyncCoordinator.streamName),
        cursor,
      );
      expect(await repository.getHiddenRevision('r'), 5);
    }
  });
}

TcBackendChange _visibility(TcBackendResourceState state, String cursor) =>
    TcBackendChange(
      resourceType: 'AstroGalleryVisibility',
      resourceId: 'r',
      operation: TcBackendChangeOperation.update,
      currentRevision: 5,
      currentResourceState: state,
      cursor: cursor,
    );

TcBackendChange _event(TcBackendResourceState state, int revision) =>
    TcBackendChange(
      resourceType: 'ObservationRecord',
      resourceId: 'r',
      operation: TcBackendChangeOperation.update,
      revision: revision,
      currentRevision: revision,
      currentResourceState: state,
    );
GalleryItem _item(int revision, {String recordId = 'r'}) => GalleryItem(
  backendRecordId: recordId,
  revision: revision,
  catalogObjectId: 'M42',
  capturedAt: DateTime.utc(2026),
  favorite: false,
  representative: false,
  backendFileId: 'file',
  previewUrl: 'https://backend.test/preview',
  originalUrl: 'https://backend.test/original',
  thumbnailUrl: 'https://backend.test/thumb',
);

class _Api implements TcBackendChangesApi {
  List<TcBackendChange> events = [];
  int detailCalls = 0;
  int detailRevision = 5;
  String detailRecordId = 'r';
  int page = 0;
  String? nextCursorOverride;
  TcBackendChangesException? error;
  @override
  Future<TcBackendChangesPage> getChanges({String? cursor}) async =>
      TcBackendChangesPage(
        changes: events,
        nextCursor: nextCursorOverride ?? 'page-${++page}',
        hasMore: false,
      );
  @override
  Future<GalleryItem> getObservationRecord(String id) async {
    detailCalls++;
    if (error case final failure?) throw failure;
    return _item(detailRevision, recordId: detailRecordId);
  }
}

class _Checkpoints implements SyncCheckpointDataSource {
  _Checkpoints(this.delegate);
  final SyncCheckpointDataSource delegate;
  bool fail = false;
  @override
  Future<String?> readCursor(String stream) => delegate.readCursor(stream);
  @override
  Future<void> writeCursor(String stream, String cursor) async {
    if (fail) throw StateError('simulated interruption before checkpoint');
    await delegate.writeCursor(stream, cursor);
  }
}

class _Records extends Fake implements ShootingRecordRepository {
  @override
  Future<List<ShootingRecord>> getAll() async => [];
  @override
  Future<ShootingRecord?> getById(String id) async => null;
}

class _Catalog extends Fake implements CatalogRepository {
  @override
  Future<List<CatalogObject>> getAll({bool listOnly = true}) async => [];
}

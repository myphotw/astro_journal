import 'dart:async';

import 'package:astro_journal/data/datasources/gallery_record_link_datasource.dart';
import 'package:astro_journal/data/datasources/sync_checkpoint_datasource.dart';
import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/gallery_item.dart';
import 'package:astro_journal/data/models/plate_solve_queue.dart';
import 'package:astro_journal/data/models/tc_backend_change.dart';
import 'package:astro_journal/data/repositories/catalog_repository.dart';
import 'package:astro_journal/data/repositories/gallery_repository.dart';
import 'package:astro_journal/data/repositories/shooting_record_repository.dart';
import 'package:astro_journal/services/tc_backend_changes_service.dart';
import 'package:astro_journal/services/catalog_capture_projection_service.dart';
import 'package:astro_journal/services/tc_backend_pull_sync_coordinator.dart';
import 'package:astro_journal/services/tc_backend_settings_service.dart';
import 'package:astro_journal/services/tc_backend_sync_gate.dart';
import 'package:astro_journal/services/astrojournal_local_capture_reset_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late TcBackendSettingsService settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = TcBackendSettingsService();
    await settings.save(
      const TcBackendSettings(
        baseUrl: 'https://backend.example',
        enabled: true,
      ),
    );
  });

  TcBackendPullSyncCoordinator subject({
    required _FakeChangesApi api,
    required _FakeCheckpoints checkpoints,
    required _FakeGallery gallery,
    _FakeRecords? records,
    Map<String, String> links = const {},
    TcBackendSyncGate? gate,
    CatalogCaptureProjectionService? captureProjection,
    AstroJournalLocalCaptureReset? localCaptureReset,
    Future<void> Function()? onObservationRecordsChanged,
  }) => TcBackendPullSyncCoordinator(
    changesApi: api,
    checkpoints: checkpoints,
    galleryRepository: gallery,
    shootingRecordRepository: records ?? _FakeRecords(),
    recordLinks: _FakeLinks(links),
    settingsService: settings,
    syncGate: gate ?? TcBackendSyncGate(),
    catalogCaptureProjection: captureProjection,
    localCaptureReset: localCaptureReset,
    onObservationRecordsChanged: onObservationRecordsChanged,
  );

  test('CREATE pulls canonical record into local projection', () async {
    final api = _FakeChangesApi(
      {
        null: _page([
          _change('record-1', TcBackendChangeOperation.create, 1),
        ], 'cursor-1'),
      },
      details: {'record-1': _item('record-1', 1)},
    );
    final gallery = _FakeGallery();
    final records = _FakeRecords();
    final catalog = _FakeCatalog();
    final projection = CatalogCaptureProjectionService(
      catalogRepository: catalog,
      localRecords: records,
      galleryRepository: gallery,
    );

    await subject(
      api: api,
      checkpoints: _FakeCheckpoints(),
      gallery: gallery,
      records: records,
      captureProjection: projection,
    ).drain();

    expect(gallery.items['record-1']?.revision, 1);
    expect(api.detailCalls, ['record-1']);
    expect(catalog.captured, isTrue);
  });

  test('UPDATE applies only a newer revision', () async {
    final api = _FakeChangesApi(
      {
        null: _page([
          _change('record-1', TcBackendChangeOperation.update, 2),
        ], 'cursor-1'),
      },
      details: {'record-1': _item('record-1', 2)},
    );
    final gallery = _FakeGallery()..items['record-1'] = _item('record-1', 1);

    await subject(
      api: api,
      checkpoints: _FakeCheckpoints(),
      gallery: gallery,
    ).drain();

    expect(gallery.items['record-1']?.revision, 2);
  });

  test(
    'Plate Solve status UPDATE is cached and refreshes observers once',
    () async {
      var refreshCalls = 0;
      final api = _FakeChangesApi(
        {
          null: _page([
            _change('record-1', TcBackendChangeOperation.update, 2),
          ], 'cursor-1'),
        },
        details: {
          'record-1': _item(
            'record-1',
            2,
            plateSolveStatus: PlateSolveQueueStatus.processing,
          ),
        },
      );
      final gallery = _FakeGallery()..items['record-1'] = _item('record-1', 1);

      await subject(
        api: api,
        checkpoints: _FakeCheckpoints(),
        gallery: gallery,
        onObservationRecordsChanged: () async {
          refreshCalls++;
        },
      ).drain();

      expect(
        gallery.items['record-1']?.plateSolveStatus,
        PlateSolveQueueStatus.processing,
      );
      expect(refreshCalls, 1);
    },
  );

  test('DELETE stores tombstone and removes linked local record', () async {
    final api = _FakeChangesApi({
      null: _page([
        TcBackendChange(
          resourceType: 'ObservationRecord',
          resourceId: 'record-1',
          operation: TcBackendChangeOperation.delete,
          revision: 3,
          deletedAt: DateTime.utc(2026, 8, 7),
        ),
      ], 'cursor-1'),
    });
    final gallery = _FakeGallery()..items['record-1'] = _item('record-1', 2);
    final records = _FakeRecords();
    final catalog = _FakeCatalog()..captured = true;
    final projection = CatalogCaptureProjectionService(
      catalogRepository: catalog,
      localRecords: records,
      galleryRepository: gallery,
    );

    await subject(
      api: api,
      checkpoints: _FakeCheckpoints(),
      gallery: gallery,
      records: records,
      links: const {'record-1': 'local-1'},
      captureProjection: projection,
    ).drain();

    expect(gallery.items, isEmpty);
    expect(gallery.tombstones['record-1'], 3);
    expect(records.deleted, ['local-1']);
    expect(catalog.captured, isFalse);
  });

  test('cursor pagination advances after every completed page', () async {
    final api = _FakeChangesApi(
      {
        null: _page(
          [_change('record-1', TcBackendChangeOperation.create, 1)],
          'cursor-1',
          hasMore: true,
        ),
        'cursor-1': _page([
          _change('record-2', TcBackendChangeOperation.create, 1),
        ], 'cursor-2'),
      },
      details: {
        'record-1': _item('record-1', 1),
        'record-2': _item('record-2', 1),
      },
    );
    final checkpoints = _FakeCheckpoints();

    await subject(
      api: api,
      checkpoints: checkpoints,
      gallery: _FakeGallery(),
    ).drain();

    expect(api.requestedCursors, [null, 'cursor-1']);
    expect(checkpoints.writes, ['cursor-1', 'cursor-2']);
  });

  test('network failure resumes from last completed page cursor', () async {
    final api = _FakeChangesApi({
      null: _page(const [], 'cursor-1', hasMore: true),
      'cursor-1': _page(const [], 'cursor-2'),
    })..failOnceAt = 'cursor-1';
    final checkpoints = _FakeCheckpoints();
    final coordinator = subject(
      api: api,
      checkpoints: checkpoints,
      gallery: _FakeGallery(),
    );

    await expectLater(
      coordinator.drain(),
      throwsA(isA<TcBackendChangesException>()),
    );
    expect(checkpoints.cursor, 'cursor-1');
    await coordinator.drain();

    expect(api.requestedCursors, [null, 'cursor-1', 'cursor-1']);
    expect(checkpoints.cursor, 'cursor-2');
  });

  test('duplicate revision is ignored without another detail fetch', () async {
    final api = _FakeChangesApi(
      {
        null: _page([
          _change('record-1', TcBackendChangeOperation.update, 2),
          _change('record-1', TcBackendChangeOperation.update, 2),
        ], 'cursor-1'),
      },
      details: {'record-1': _item('record-1', 2)},
    );
    final gallery = _FakeGallery();

    await subject(
      api: api,
      checkpoints: _FakeCheckpoints(),
      gallery: gallery,
    ).drain();

    expect(api.detailCalls, ['record-1']);
    expect(gallery.upserts, 1);
  });

  test('shared gate serializes pull behind active push work', () async {
    final gate = TcBackendSyncGate();
    final release = Completer<void>();
    final push = gate.runExclusive(() => release.future);
    final api = _FakeChangesApi({null: _page(const [], null)});
    final pull = subject(
      api: api,
      checkpoints: _FakeCheckpoints(),
      gallery: _FakeGallery(),
      gate: gate,
    ).drain();
    await Future<void>.delayed(Duration.zero);
    expect(api.requestedCursors, isEmpty);

    release.complete();
    await Future.wait([push, pull]);
    expect(api.requestedCursors, [null]);
  });

  test(
    'AstroJournalReset event invalidates capture data and advances cursor',
    () async {
      final api = _FakeChangesApi({
        null: _page([
          const TcBackendChange(
            resourceType: 'AstroJournalReset',
            resourceId: 'AstroJournal',
            operation: TcBackendChangeOperation.update,
          ),
        ], 'cursor-after-reset'),
      });
      final checkpoints = _FakeCheckpoints();
      final localReset = _FakeLocalCaptureReset();

      await subject(
        api: api,
        checkpoints: checkpoints,
        gallery: _FakeGallery(),
        localCaptureReset: localReset,
      ).drain();

      expect(localReset.calls, 1);
      expect(checkpoints.cursor, 'cursor-after-reset');
    },
  );
}

TcBackendChange _change(
  String id,
  TcBackendChangeOperation operation,
  int revision,
) => TcBackendChange(
  resourceType: 'ObservationRecord',
  resourceId: id,
  operation: operation,
  revision: revision,
);

TcBackendChangesPage _page(
  List<TcBackendChange> changes,
  String? cursor, {
  bool hasMore = false,
}) => TcBackendChangesPage(
  changes: changes,
  nextCursor: cursor,
  hasMore: hasMore,
);

GalleryItem _item(
  String id,
  int revision, {
  PlateSolveQueueStatus? plateSolveStatus,
}) => GalleryItem(
  backendRecordId: id,
  revision: revision,
  catalogObjectId: 'M42',
  capturedAt: DateTime.utc(2026),
  favorite: false,
  representative: false,
  backendFileId: 'file-$id',
  plateSolveStatus: plateSolveStatus,
  thumbnailUrl: '/thumbnail/$id',
  previewUrl: '/preview/$id',
  originalUrl: '/original/$id',
);

class _FakeChangesApi implements TcBackendChangesApi {
  _FakeChangesApi(this.pages, {this.details = const {}});

  final Map<String?, TcBackendChangesPage> pages;
  final Map<String, GalleryItem> details;
  final List<String?> requestedCursors = [];
  final List<String> detailCalls = [];
  String? failOnceAt;

  @override
  Future<TcBackendChangesPage> getChanges({String? cursor}) async {
    requestedCursors.add(cursor);
    if (failOnceAt != null && failOnceAt == cursor) {
      failOnceAt = null;
      throw const TcBackendChangesException('offline');
    }
    return pages[cursor]!;
  }

  @override
  Future<GalleryItem> getObservationRecord(String recordId) async {
    detailCalls.add(recordId);
    return details[recordId]!;
  }
}

class _FakeCheckpoints implements SyncCheckpointDataSource {
  String? cursor;
  final List<String> writes = [];

  @override
  Future<String?> readCursor(String streamName) async => cursor;

  @override
  Future<void> writeCursor(String streamName, String cursor) async {
    this.cursor = cursor;
    writes.add(cursor);
  }
}

class _FakeGallery implements GalleryRepository {
  final Map<String, GalleryItem> items = {};
  final Map<String, int> tombstones = {};
  int upserts = 0;

  @override
  Future<GallerySnapshot> getSnapshot({bool forceRefresh = false}) async =>
      GallerySnapshot(
        items: items.values.toList(),
        source: GallerySnapshotSource.cache,
        backendEnabled: true,
      );

  @override
  Future<int?> getCachedRevision(String backendRecordId) async =>
      tombstones[backendRecordId] ?? items[backendRecordId]?.revision;

  @override
  Future<bool> upsertPulledItem(GalleryItem item) async {
    final revision = await getCachedRevision(item.backendRecordId);
    if (revision != null && revision >= item.revision) return false;
    items[item.backendRecordId] = item;
    upserts++;
    return true;
  }

  @override
  Future<bool> applyPulledDelete(
    String backendRecordId, {
    required int revision,
    DateTime? deletedAt,
  }) async {
    final current = await getCachedRevision(backendRecordId);
    if (current != null && current > revision) return false;
    if (tombstones[backendRecordId] case final tombstone?
        when tombstone >= revision) {
      return false;
    }
    items.remove(backendRecordId);
    tombstones[backendRecordId] = revision;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRecords implements ShootingRecordRepository {
  final List<String> deleted = [];

  @override
  Future<List<Never>> getAll() async => const [];

  @override
  Future<void> delete(String id) async {
    deleted.add(id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCatalog
    implements CatalogRepository, CatalogCaptureProjectionWriter {
  bool captured = false;
  String? capturedDate;

  CatalogObject get object => CatalogObject(
    id: 'M42',
    number: 42,
    catalog: CatalogType.messier,
    name: 'Orion Nebula',
    type: 'Nebula',
    constellation: 'Orion',
    ra: '-',
    dec: '-',
    magnitude: '-',
    captured: captured,
    capturedDate: capturedDate,
  );

  @override
  Future<List<CatalogObject>> getAll({bool listOnly = true}) async => [object];

  @override
  Future<CatalogObject?> getById(String id) async =>
      id == 'M42' ? object : null;

  @override
  Future<int> updateCaptureProjection(
    String id, {
    required bool captured,
    String? capturedDate,
  }) async {
    if (id != 'M42') return 0;
    this.captured = captured;
    this.capturedDate = capturedDate;
    return 1;
  }

  @override
  Future<void> updateCaptured(
    String id, {
    required bool captured,
    String? capturedDate,
  }) async {
    await updateCaptureProjection(
      id,
      captured: captured,
      capturedDate: capturedDate,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLinks implements GalleryRecordLinkDataSource {
  const _FakeLinks(this.links);
  final Map<String, String> links;

  @override
  Future<Map<String, String>> localIdsByBackendRecordId() async => links;
}

class _FakeLocalCaptureReset implements AstroJournalLocalCaptureReset {
  int calls = 0;

  @override
  Future<void> clearCaptureData({String? resetEventCursor}) async {
    calls++;
  }
}

import 'dart:async';

import 'package:astro_journal/data/datasources/gallery_record_link_datasource.dart';
import 'package:astro_journal/data/datasources/sync_checkpoint_datasource.dart';
import 'package:astro_journal/data/models/gallery_item.dart';
import 'package:astro_journal/data/models/tc_backend_change.dart';
import 'package:astro_journal/data/repositories/gallery_repository.dart';
import 'package:astro_journal/data/repositories/shooting_record_repository.dart';
import 'package:astro_journal/services/tc_backend_changes_service.dart';
import 'package:astro_journal/services/tc_backend_pull_sync_coordinator.dart';
import 'package:astro_journal/services/tc_backend_settings_service.dart';
import 'package:astro_journal/services/tc_backend_sync_gate.dart';
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
  }) => TcBackendPullSyncCoordinator(
    changesApi: api,
    checkpoints: checkpoints,
    galleryRepository: gallery,
    shootingRecordRepository: records ?? _FakeRecords(),
    recordLinks: _FakeLinks(links),
    settingsService: settings,
    syncGate: gate ?? TcBackendSyncGate(),
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

    await subject(
      api: api,
      checkpoints: _FakeCheckpoints(),
      gallery: gallery,
    ).drain();

    expect(gallery.items['record-1']?.revision, 1);
    expect(api.detailCalls, ['record-1']);
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

    await subject(
      api: api,
      checkpoints: _FakeCheckpoints(),
      gallery: gallery,
      records: records,
      links: const {'record-1': 'local-1'},
    ).drain();

    expect(gallery.items, isEmpty);
    expect(gallery.tombstones['record-1'], 3);
    expect(records.deleted, ['local-1']);
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

GalleryItem _item(String id, int revision) => GalleryItem(
  backendRecordId: id,
  revision: revision,
  catalogObjectId: 'M42',
  capturedAt: DateTime.utc(2026),
  favorite: false,
  representative: false,
  backendFileId: 'file-$id',
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
  Future<void> delete(String id) async {
    deleted.add(id);
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

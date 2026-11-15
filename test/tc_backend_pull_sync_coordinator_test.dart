import 'dart:async';

import 'package:astro_journal/data/datasources/gallery_record_link_datasource.dart';
import 'package:astro_journal/data/datasources/sync_checkpoint_datasource.dart';
import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/gallery_item.dart';
import 'package:astro_journal/data/models/plate_solve_queue.dart';
import 'package:astro_journal/data/models/shooting_record.dart';
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
    Future<bool> Function(TcBackendChange)? observationSiteChangeApplier,
    Future<bool> Function(TcBackendChange)? equipmentChangeApplier,
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
    observationSiteChangeApplier: observationSiteChangeApplier,
    equipmentChangeApplier: equipmentChangeApplier,
  );

  for (final operation in [
    TcBackendChangeOperation.create,
    TcBackendChangeOperation.update,
  ]) {
    test('ACTIVE $operation fetches canonical detail', () async {
      final api = _FakeChangesApi(
        {
          null: _page([
            _change(
              'active',
              operation,
              1,
              state: TcBackendResourceState.active,
              currentRevision: 3,
            ),
          ], 'done'),
        },
        details: {'active': _item('active', 3)},
      );
      final gallery = _FakeGallery()..items['active'] = _item('active', 1);
      final checkpoint = _FakeCheckpoints();
      await subject(
        api: api,
        checkpoints: checkpoint,
        gallery: gallery,
      ).drain();
      expect(api.detailCalls, ['active']);
      expect(gallery.items['active']?.revision, 3);
      expect(checkpoint.cursor, 'done');
    });
    for (final state in [
      TcBackendResourceState.deleted,
      TcBackendResourceState.missing,
      TcBackendResourceState.unavailable,
    ]) {
      test(
        '$state $operation removes projections without detail fetch',
        () async {
          final api = _FakeChangesApi({
            null: _page([
              _change('gone', operation, 1, state: state, currentRevision: 4),
            ], 'done'),
          });
          final gallery = _FakeGallery()..items['gone'] = _item('gone', 2);
          final records = _FakeRecords([
            _record('remote:gone'),
            _record('linked'),
            _record('local-only'),
          ]);
          final checkpoint = _FakeCheckpoints();
          await subject(
            api: api,
            checkpoints: checkpoint,
            gallery: gallery,
            records: records,
            links: {'gone': 'linked'},
          ).drain();
          expect(api.detailCalls, isEmpty);
          expect(gallery.items, isEmpty);
          expect(
            state == TcBackendResourceState.deleted
                ? gallery.tombstones['gone']
                : gallery.hidden['gone'],
            4,
          );
          expect(records.records.map((r) => r.id), ['local-only']);
          expect(checkpoint.cursor, 'done');
        },
      );
    }
  }

  for (final state in [null, TcBackendResourceState.active]) {
    test('$state detail 404 removes item and commits page', () async {
      final api =
          _FakeChangesApi({
              null: _page([
                _change(
                  'gone',
                  TcBackendChangeOperation.create,
                  2,
                  state: state,
                ),
              ], 'done'),
            })
            ..detailErrors['gone'] = const TcBackendChangesException(
              'not found',
              statusCode: 404,
            );
      final gallery = _FakeGallery()..items['gone'] = _item('gone', 1);
      final checkpoint = _FakeCheckpoints();
      var refreshes = 0;
      await subject(
        api: api,
        checkpoints: checkpoint,
        gallery: gallery,
        onObservationRecordsChanged: () async {
          refreshes++;
        },
      ).drain();
      expect(api.detailCalls, ['gone']);
      expect(gallery.items, isEmpty);
      expect(gallery.hidden['gone'], 2);
      expect(gallery.tombstones, isEmpty);
      expect(checkpoint.cursor, 'done');
      expect(refreshes, 1);
    });
  }

  for (final status in [401, 403, 429, 500, 503, null]) {
    test(
      'detail error $status does not commit cursor or remove data',
      () async {
        final api =
            _FakeChangesApi({
                null: _page([
                  _change('record', TcBackendChangeOperation.update, 2),
                ], 'done'),
              })
              ..detailErrors['record'] = TcBackendChangesException(
                status == null ? 'timed out' : 'HTTP failure',
                statusCode: status,
              );
        final gallery = _FakeGallery()..items['record'] = _item('record', 1);
        final checkpoint = _FakeCheckpoints();
        await expectLater(
          subject(api: api, checkpoints: checkpoint, gallery: gallery).drain(),
          throwsA(isA<TcBackendChangesException>()),
        );
        expect(checkpoint.writes, isEmpty);
        expect(gallery.items['record']?.revision, 1);
        expect(gallery.tombstones, isEmpty);
      },
    );
  }

  test(
    'unavailable fallback revision protects deletion and higher ACTIVE restores',
    () async {
      final gallery = _FakeGallery()..items['record'] = _item('record', 1);
      Future<void> apply(TcBackendChange change, {int detailRevision = 1}) =>
          subject(
            api: _FakeChangesApi(
              {
                null: _page([change], 'done'),
              },
              details: {'record': _item('record', detailRevision)},
            ),
            checkpoints: _FakeCheckpoints(),
            gallery: gallery,
          ).drain();
      await apply(
        _change(
          'record',
          TcBackendChangeOperation.update,
          3,
          state: TcBackendResourceState.unavailable,
        ),
      );
      expect(gallery.hidden['record'], 3);
      expect(gallery.tombstones, isEmpty);
      await apply(_change('record', TcBackendChangeOperation.create, 1));
      await apply(_change('record', TcBackendChangeOperation.update, 2));
      expect(gallery.items, isEmpty);
      await apply(
        _change(
          'record',
          TcBackendChangeOperation.update,
          4,
          state: TcBackendResourceState.active,
        ),
        detailRevision: 4,
      );
      expect(gallery.items['record']?.revision, 4);
      expect(await gallery.getAuthoritativeDeleteRevision('record'), isNull);
    },
  );

  test(
    'stale detail and absent-state events cannot overwrite a higher revision',
    () async {
      final gallery = _FakeGallery()..items['record'] = _item('record', 5);
      final api = _FakeChangesApi(
        {
          null: _page([
            _change(
              'record',
              TcBackendChangeOperation.update,
              6,
              state: TcBackendResourceState.active,
            ),
            _change(
              'record',
              TcBackendChangeOperation.update,
              1,
              state: TcBackendResourceState.deleted,
              currentRevision: 4,
            ),
          ], 'done'),
        },
        details: {'record': _item('record', 4)},
      );
      await subject(
        api: api,
        checkpoints: _FakeCheckpoints(),
        gallery: gallery,
      ).drain();
      expect(gallery.items['record']?.revision, 5);
      expect(gallery.tombstones, isEmpty);
    },
  );

  test(
    '72 historical events and 20 absent resources drain across pages',
    () async {
      final events = [
        for (var i = 0; i < 72; i++)
          _change(
            'r$i',
            i.isEven
                ? TcBackendChangeOperation.create
                : TcBackendChangeOperation.update,
            1,
            state: i < 20
                ? TcBackendResourceState.deleted
                : TcBackendResourceState.active,
            currentRevision: i < 20 ? 2 : 1,
          ),
      ];
      final api = _FakeChangesApi(
        {
          null: _page(events.take(50).toList(), 'page1', hasMore: true),
          'page1': _page(events.skip(50).toList(), 'page2'),
        },
        details: {for (var i = 20; i < 72; i++) 'r$i': _item('r$i', 1)},
      );
      final gallery = _FakeGallery();
      final checkpoint = _FakeCheckpoints();
      var refreshes = 0;
      await subject(
        api: api,
        checkpoints: checkpoint,
        gallery: gallery,
        onObservationRecordsChanged: () async {
          refreshes++;
        },
      ).drain();
      expect(gallery.items, hasLength(52));
      expect(gallery.tombstones, hasLength(20));
      expect(api.detailCalls, hasLength(52));
      expect(api.requestedCursors, [null, 'page1']);
      expect(checkpoint.writes, ['page1', 'page2']);
      expect(refreshes, 1);
    },
  );

  test(
    'partial page failure refreshes successes and restart replays idempotently',
    () async {
      final api = _FakeChangesApi(
        {
          null: _page(
            [_change('first', TcBackendChangeOperation.create, 1)],
            'page1',
            hasMore: true,
          ),
          'page1': _page([
            _change('second', TcBackendChangeOperation.create, 1),
            _change('failed', TcBackendChangeOperation.create, 1),
          ], 'page2'),
        },
        details: {
          for (final id in ['first', 'second', 'failed']) id: _item(id, 1),
        },
      )..detailErrors['failed'] = const TcBackendChangesException('timeout');
      final gallery = _FakeGallery();
      final checkpoint = _FakeCheckpoints();
      final visible = <List<String>>[];
      TcBackendPullSyncCoordinator restart() => subject(
        api: api,
        checkpoints: checkpoint,
        gallery: gallery,
        onObservationRecordsChanged: () async {
          visible.add(gallery.items.keys.toList());
        },
      );
      await expectLater(
        restart().drain(),
        throwsA(isA<TcBackendChangesException>()),
      );
      expect(checkpoint.writes, ['page1']);
      expect(visible.single, ['first', 'second']);
      api.detailErrors.clear();
      await restart().drain();
      expect(checkpoint.writes, ['page1', 'page2']);
      expect(api.detailCalls, ['first', 'second', 'failed', 'failed']);
      expect(gallery.upserts, 3);
      expect(visible.last, ['first', 'second', 'failed']);
    },
  );

  test('next page request failure still refreshes completed page', () async {
    final api = _FakeChangesApi(
      {
        null: _page(
          [_change('first', TcBackendChangeOperation.create, 1)],
          'page1',
          hasMore: true,
        ),
      },
      details: {'first': _item('first', 1)},
    )..failOnceAt = 'page1';
    final gallery = _FakeGallery();
    final checkpoint = _FakeCheckpoints();
    var refreshes = 0;
    await expectLater(
      subject(
        api: api,
        checkpoints: checkpoint,
        gallery: gallery,
        onObservationRecordsChanged: () async {
          refreshes++;
        },
      ).drain(),
      throwsA(isA<TcBackendChangesException>()),
    );
    expect(refreshes, 1);
    expect(checkpoint.cursor, 'page1');
  });

  test('DELETE blocks historical CREATE UPDATE and newer ACTIVE', () async {
    final gallery = _FakeGallery()..items['record'] = _item('record', 1);
    final api = _FakeChangesApi(
      {
        null: _page([
          _change('record', TcBackendChangeOperation.delete, 3),
          _change('record', TcBackendChangeOperation.create, 1),
          _change('record', TcBackendChangeOperation.update, 2),
        ], 'deleted'),
        'deleted': _page([
          _change(
            'record',
            TcBackendChangeOperation.update,
            4,
            state: TcBackendResourceState.active,
          ),
        ], 'restored'),
      },
      details: {'record': _item('record', 4)},
    );
    final checkpoint = _FakeCheckpoints();
    await subject(api: api, checkpoints: checkpoint, gallery: gallery).drain();
    expect(gallery.items, isEmpty);
    expect(api.detailCalls, isEmpty);
    await subject(api: api, checkpoints: checkpoint, gallery: gallery).drain();
    expect(gallery.items, isEmpty);
    expect(gallery.tombstones['record'], 3);
    expect(api.detailCalls, isEmpty);
  });

  test('ObservationSite changes use the shared cursor consumer', () async {
    final change = TcBackendChange(
      resourceType: 'ObservationSite',
      resourceId: 'site-1',
      operation: TcBackendChangeOperation.update,
      revision: 7,
    );
    final api = _FakeChangesApi({
      null: _page([change], 'cursor-1'),
    });
    final checkpoints = _FakeCheckpoints();
    final applied = <TcBackendChange>[];

    await subject(
      api: api,
      checkpoints: checkpoints,
      gallery: _FakeGallery(),
      observationSiteChangeApplier: (event) async {
        applied.add(event);
        return true;
      },
    ).drain();

    expect(applied, [change]);
    expect(checkpoints.cursor, 'cursor-1');
  });

  test('Equipment changes use the shared cursor consumer', () async {
    final change = TcBackendChange(
      resourceType: 'Equipment',
      resourceId: 'equipment-1',
      operation: TcBackendChangeOperation.update,
      revision: 7,
    );
    final api = _FakeChangesApi({
      null: _page([change], 'cursor-1'),
    });
    final checkpoints = _FakeCheckpoints();
    final applied = <TcBackendChange>[];

    await subject(
      api: api,
      checkpoints: checkpoints,
      gallery: _FakeGallery(),
      equipmentChangeApplier: (event) async {
        applied.add(event);
        return true;
      },
    ).drain();

    expect(applied, [change]);
    expect(checkpoints.cursor, 'cursor-1');
  });

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

  test(
    'empty pull does not repeat Catalog reconciliation after successful projection',
    () async {
      final api = _FakeChangesApi(
        {
          null: _page([
            _change('r', TcBackendChangeOperation.create, 1),
          ], 'done'),
          'done': _page([], 'done'),
        },
        details: {'r': _item('r', 1)},
      );
      final gallery = _FakeGallery();
      final catalog = _FakeCatalog();
      final records = _FakeRecords();
      final coordinator = subject(
        api: api,
        checkpoints: _FakeCheckpoints(),
        gallery: gallery,
        records: records,
        captureProjection: CatalogCaptureProjectionService(
          catalogRepository: catalog,
          localRecords: records,
          galleryRepository: gallery,
        ),
      );
      await coordinator.drain();
      expect(catalog.captured, isTrue);
      expect(gallery.cachedReads, 1);
      await coordinator.drain();
      expect(gallery.cachedReads, 1);
      expect(catalog.captured, isTrue);
    },
  );

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
    final records = _FakeRecords([_record('local-1')]);
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
    expect(records.deleted, contains('local-1'));
    expect(records.records, isEmpty);
    expect(catalog.captured, isFalse);
  });

  test('DELETE without outbox link removes remote local projection', () async {
    final api = _FakeChangesApi({
      null: _page([
        _change('record-1', TcBackendChangeOperation.delete, 3),
      ], 'cursor-1'),
    });
    final gallery = _FakeGallery()..items['record-1'] = _item('record-1', 2);
    final records = _FakeRecords([_record('remote:record-1')]);

    await subject(
      api: api,
      checkpoints: _FakeCheckpoints(),
      gallery: gallery,
      records: records,
    ).drain();

    expect(records.records, isEmpty);
    expect(records.deleted, ['remote:record-1']);
  });

  test('DELETE removes a modified durable remote projection', () async {
    final api = _FakeChangesApi({
      null: _page([
        _change('record-1', TcBackendChangeOperation.delete, 3),
      ], 'cursor-1'),
    });
    final gallery = _FakeGallery()..items['record-1'] = _item('record-1', 2);
    final records = _FakeRecords([
      _record(
        'remote:record-1',
      ).copyWith(isFavorite: true, memo: 'edited on this device'),
    ]);

    await subject(
      api: api,
      checkpoints: _FakeCheckpoints(),
      gallery: gallery,
      records: records,
    ).drain();

    expect(records.records, isEmpty);
  });

  test('duplicate DELETE remains idempotent', () async {
    final delete = _change('record-1', TcBackendChangeOperation.delete, 3);
    final api = _FakeChangesApi({
      null: _page([delete, delete], 'cursor-1'),
    });
    final gallery = _FakeGallery()..items['record-1'] = _item('record-1', 2);
    final records = _FakeRecords([_record('remote:record-1')]);

    await subject(
      api: api,
      checkpoints: _FakeCheckpoints(),
      gallery: gallery,
      records: records,
    ).drain();

    expect(records.records, isEmpty);
    expect(records.deleted, ['remote:record-1']);
    expect(gallery.tombstones['record-1'], 3);
  });

  test('linked and remote identity paths delete the same row once', () async {
    final api = _FakeChangesApi({
      null: _page([
        _change('record-1', TcBackendChangeOperation.delete, 3),
      ], 'cursor-1'),
    });
    final gallery = _FakeGallery()..items['record-1'] = _item('record-1', 2);
    final records = _FakeRecords([_record('remote:record-1')]);

    await subject(
      api: api,
      checkpoints: _FakeCheckpoints(),
      gallery: gallery,
      records: records,
      links: const {'record-1': 'remote:record-1'},
    ).drain();

    expect(records.deleted, ['remote:record-1']);
  });

  test(
    'unrelated DELETE preserves local-only pending and V1 records',
    () async {
      final api = _FakeChangesApi({
        null: _page([
          _change('deleted-record', TcBackendChangeOperation.delete, 1),
        ], 'cursor-1'),
      });
      final records = _FakeRecords([
        _record('local-only'),
        _record('pending-upload'),
        _record('legacy-v1'),
      ]);

      await subject(
        api: api,
        checkpoints: _FakeCheckpoints(),
        gallery: _FakeGallery(),
        records: records,
      ).drain();

      expect(records.records.map((record) => record.id), [
        'local-only',
        'pending-upload',
        'legacy-v1',
      ]);
    },
  );

  test(
    'startup reconciliation removes stale shell after DELETE checkpoint',
    () async {
      final checkpoints = _FakeCheckpoints()..cursor = 'cursor-after-delete';
      final api = _FakeChangesApi({
        'cursor-after-delete': _page(const [], 'cursor-after-delete'),
      });
      final gallery = _FakeGallery()..tombstones['record-1'] = 3;
      final records = _FakeRecords([
        _record('remote:record-1'),
        _record('local-only'),
      ]);

      await subject(
        api: api,
        checkpoints: checkpoints,
        gallery: gallery,
        records: records,
      ).drain();

      expect(records.records.map((record) => record.id), ['local-only']);
      expect(records.deleted, ['remote:record-1']);
    },
  );

  test('startup reconciliation also removes a tombstoned linked row', () async {
    final checkpoints = _FakeCheckpoints()..cursor = 'cursor-after-delete';
    final api = _FakeChangesApi({
      'cursor-after-delete': _page(const [], 'cursor-after-delete'),
    });
    final gallery = _FakeGallery()..tombstones['record-1'] = 3;
    final records = _FakeRecords([_record('local-1')]);

    await subject(
      api: api,
      checkpoints: checkpoints,
      gallery: gallery,
      records: records,
      links: const {'record-1': 'local-1'},
    ).drain();

    expect(records.records, isEmpty);
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
  int revision, {
  TcBackendResourceState? state,
  int? currentRevision,
}) => TcBackendChange(
  resourceType: 'ObservationRecord',
  resourceId: id,
  operation: operation,
  revision: revision,
  currentResourceState: state,
  currentRevision: currentRevision,
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

ShootingRecord _record(String id) => ShootingRecord(
  id: id,
  celestialObjectId: 'M42',
  capturedAt: DateTime.utc(2026),
  photoUri: '/local/$id.jpg',
  createdAt: DateTime.utc(2026),
);

class _FakeChangesApi implements TcBackendChangesApi {
  _FakeChangesApi(this.pages, {this.details = const {}});

  final Map<String?, TcBackendChangesPage> pages;
  final Map<String, GalleryItem> details;
  final List<String?> requestedCursors = [];
  final List<String> detailCalls = [];
  String? failOnceAt;
  final Map<String, TcBackendChangesException> detailErrors = {};

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
    if (detailErrors[recordId] case final error?) throw error;
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

class _FakeGallery
    implements
        GalleryRepository,
        GalleryResourceStateRepository,
        CachedGallerySnapshotReader {
  final Map<String, GalleryItem> items = {};
  final Map<String, int> tombstones = {};
  final Map<String, int> hidden = {};
  final Map<String, int> active = {};
  int upserts = 0;
  int cachedReads = 0;

  @override
  Future<GallerySnapshot> getCachedSnapshot() {
    cachedReads++;
    return getSnapshot();
  }

  @override
  Future<GallerySnapshot> getSnapshot({bool forceRefresh = false}) async =>
      GallerySnapshot(
        items: items.values.toList(),
        source: GallerySnapshotSource.cache,
        backendEnabled: true,
      );

  @override
  Future<int?> getCachedRevision(String backendRecordId) async =>
      tombstones[backendRecordId] ??
      hidden[backendRecordId] ??
      items[backendRecordId]?.revision;

  @override
  Future<int?> getAuthoritativeDeleteRevision(String backendRecordId) async {
    final tombstone = tombstones[backendRecordId];
    if (tombstone == null) return null;
    return tombstone;
  }

  @override
  Future<int?> getHiddenRevision(String id) async => hidden[id];

  @override
  Future<bool> shouldFetchPulledItem(String id, int? revision) async {
    if (tombstones.containsKey(id)) return false;
    final cached = await getCachedRevision(id);
    return revision == null ||
        cached == null ||
        revision > cached ||
        (revision == cached && hidden[id] == revision);
  }

  @override
  Future<bool> applyPulledHidden(
    String id, {
    required int revision,
    required TcBackendResourceState state,
  }) async {
    if (tombstones.containsKey(id) ||
        (active[id] != null && active[id]! >= revision)) {
      return false;
    }
    final cached = await getCachedRevision(id);
    if (cached != null && cached > revision) return false;
    final changed = hidden[id] != revision || items.containsKey(id);
    hidden[id] = revision;
    items.remove(id);
    return changed;
  }

  @override
  Future<bool> upsertPulledItem(GalleryItem item) async {
    if (tombstones.containsKey(item.backendRecordId)) return false;
    final revision = await getCachedRevision(item.backendRecordId);
    if (revision != null &&
        (revision > item.revision ||
            (revision == item.revision &&
                hidden[item.backendRecordId] != revision))) {
      return false;
    }
    items[item.backendRecordId] = item;
    hidden.remove(item.backendRecordId);
    active[item.backendRecordId] = item.revision;
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
  _FakeRecords([List<ShootingRecord> records = const []])
    : records = List<ShootingRecord>.from(records);

  final List<ShootingRecord> records;
  final List<String> deleted = [];

  @override
  Future<List<ShootingRecord>> getAll() async => List.of(records);

  @override
  Future<ShootingRecord?> getById(String id) async {
    for (final record in records) {
      if (record.id == id) return record;
    }
    return null;
  }

  @override
  Future<void> delete(String id) async {
    final existed = records.any((record) => record.id == id);
    records.removeWhere((record) => record.id == id);
    if (existed) deleted.add(id);
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

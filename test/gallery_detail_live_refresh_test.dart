import 'dart:async';
import 'dart:io';

import 'package:astro_journal/data/models/plate_solve_queue.dart';
import 'package:astro_journal/data/models/plate_solve_result.dart';
import 'package:astro_journal/data/models/shooting_record.dart';
import 'package:astro_journal/data/repositories/catalog_repository.dart';
import 'package:astro_journal/features/gallery/view/gallery_detail_screen.dart';
import 'package:astro_journal/features/gallery/viewmodel/gallery_detail_view_model.dart';
import 'package:astro_journal/services/photo_overlay_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Gallery detail live refresh', () {
    test('navigation uses the local snapshot before post-frame refresh', () {
      expect(GalleryDetailScreen.open, isNotNull);
      final source = File(
        'lib/features/gallery/view/gallery_detail_screen.dart',
      ).readAsStringSync().replaceAll('\r\n', '\n');
      final openStart = source.indexOf('static Future<void> open(');
      final pushStart = source.indexOf('await Navigator.of(context).push<void>(', openStart);
      final beforePush = source.substring(openStart, pushStart);

      expect(beforePush, contains('photoRecordsFrom(\n      records,'));
      expect(beforePush, isNot(contains('await syncCoordinator')));
      expect(beforePush, isNot(contains('await pullSyncCoordinator')));
      expect(beforePush, isNot(contains('loadDetailRecord')));
      expect(beforePush, isNot(contains('findPhotoUpload')));
      expect(source, contains('addPostFrameCallback'));
      expect(source, contains('refreshNow(force: true)'));
    });

    test('initial snapshot can refresh after entry even when terminal', () async {
      var calls = 0;
      final controller = GalleryDetailLiveRefreshController(
        interval: const Duration(days: 1),
        shouldRefresh: () => false,
        refresh: () async => calls++,
      );

      expect(calls, 0);
      await controller.refreshNow(force: true);
      expect(calls, 1);
      controller.dispose();
    });

    test('WAITING changes to PROCESSING and COMPLETED without re-entry', () async {
      final responses = <ShootingRecord>[
        _record(PlateSolveQueueStatus.processing),
        _record(
          PlateSolveQueueStatus.completed,
          plateSolve: _wcs(),
        ),
      ];
      final detail = GalleryDetailViewModel(
        records: [_record(PlateSolveQueueStatus.waiting)],
        initialIndex: 0,
        recordRefresher: (record) async => GalleryDetailRefreshResult(
          record: responses.removeAt(0),
          hasPendingNasSync: false,
        ),
      );

      expect(detail.currentRecord.plateSolveQueueStatus,
          PlateSolveQueueStatus.waiting);
      await detail.refreshCurrentRecord();
      expect(detail.currentRecord.plateSolveQueueStatus,
          PlateSolveQueueStatus.processing);
      expect(detail.needsLiveRefresh, isTrue);
      await detail.refreshCurrentRecord();
      expect(detail.currentRecord.plateSolveQueueStatus,
          PlateSolveQueueStatus.completed);
      expect(detail.currentRecord.plateSolve?.centerRa, 10.6847);
      expect(detail.needsLiveRefresh, isFalse);
    });

    test('COMPLETED hydrates WCS and rebuilds an enabled overlay', () async {
      final overlays = _FakeOverlayService();
      final detail = GalleryDetailViewModel(
        records: [_record(PlateSolveQueueStatus.processing)],
        initialIndex: 0,
        overlayService: overlays,
        recordRefresher: (record) async => GalleryDetailRefreshResult(
          record: _record(
            PlateSolveQueueStatus.completed,
            plateSolve: _wcs(),
          ),
          hasPendingNasSync: false,
        ),
      );

      detail.toggleOverlayEnabled();
      await _flushOverlay();
      final before = overlays.calls;
      await detail.refreshCurrentRecord();
      await _flushOverlay();

      expect(detail.currentRecord.plateSolve?.success, isTrue);
      expect(overlays.calls, greaterThan(before));
      expect(detail.overlayFor('photo-1')?.isAvailable, isTrue);
    });

    test('PROCESSING changes to FAILED and stops scheduling', () async {
      final detail = GalleryDetailViewModel(
        records: [_record(PlateSolveQueueStatus.processing)],
        initialIndex: 0,
        recordRefresher: (record) async => GalleryDetailRefreshResult(
          record: _record(PlateSolveQueueStatus.failed),
          hasPendingNasSync: false,
        ),
      );
      final controller = _controller(detail);
      controller.start();
      expect(controller.hasScheduledRefresh, isTrue);

      await controller.refreshNow();

      expect(detail.currentRecord.plateSolveQueueStatus,
          PlateSolveQueueStatus.failed);
      expect(controller.hasScheduledRefresh, isFalse);
      controller.dispose();
    });

    test('FAILED retry progression WAITING to COMPLETED stays refreshable', () async {
      final responses = <ShootingRecord>[
        _record(PlateSolveQueueStatus.waiting),
        _record(PlateSolveQueueStatus.processing),
        _record(PlateSolveQueueStatus.completed, plateSolve: _wcs()),
      ];
      final detail = GalleryDetailViewModel(
        records: [_record(PlateSolveQueueStatus.failed)],
        initialIndex: 0,
        recordRefresher: (record) async => GalleryDetailRefreshResult(
          record: responses.removeAt(0),
          hasPendingNasSync: false,
        ),
      );

      // Retry updates the shared Gallery model to WAITING; detail mirrors it.
      detail.updateRecord(_record(PlateSolveQueueStatus.waiting));
      final controller = _controller(detail)..start();
      await controller.refreshNow();
      expect(detail.currentRecord.plateSolveQueueStatus,
          PlateSolveQueueStatus.waiting);
      await controller.refreshNow();
      expect(detail.currentRecord.plateSolveQueueStatus,
          PlateSolveQueueStatus.processing);
      await controller.refreshNow();
      expect(detail.currentRecord.plateSolveQueueStatus,
          PlateSolveQueueStatus.completed);
      expect(controller.hasScheduledRefresh, isFalse);
      controller.dispose();
    });

    test('dispose prevents timer and manual refresh callbacks', () async {
      var calls = 0;
      final controller = GalleryDetailLiveRefreshController(
        interval: const Duration(days: 1),
        shouldRefresh: () => true,
        refresh: () async => calls++,
      )..start();

      controller.dispose();
      await controller.refreshNow();

      expect(controller.hasScheduledRefresh, isFalse);
      expect(calls, 0);
    });

    test('foreground resume performs one immediate refresh', () async {
      var calls = 0;
      final called = Completer<void>();
      final controller = GalleryDetailLiveRefreshController(
        interval: const Duration(days: 1),
        shouldRefresh: () => true,
        refresh: () async {
          calls++;
          if (!called.isCompleted) called.complete();
        },
      )..start();

      controller.pause();
      controller.resume();
      await called.future;

      expect(calls, 1);
      controller.dispose();
    });

    test('a stale refresh from another photo is ignored', () async {
      final response = Completer<GalleryDetailRefreshResult>();
      final detail = GalleryDetailViewModel(
        records: [
          _record(PlateSolveQueueStatus.waiting),
          _record(PlateSolveQueueStatus.waiting, id: 'photo-2'),
        ],
        initialIndex: 0,
        recordRefresher: (_) => response.future,
      );

      final refresh = detail.refreshCurrentRecord();
      detail.onPageChanged(1);
      response.complete(
        GalleryDetailRefreshResult(
          record: _record(PlateSolveQueueStatus.completed, plateSolve: _wcs()),
          hasPendingNasSync: false,
        ),
      );
      await refresh;

      expect(detail.currentRecord.id, 'photo-2');
      expect(detail.currentRecord.plateSolveQueueStatus,
          PlateSolveQueueStatus.waiting);
    });

    test('pending NAS state keeps refresh active until it becomes terminal', () async {
      var pending = true;
      final detail = GalleryDetailViewModel(
        records: [_record(null)],
        initialIndex: 0,
        initialHasPendingNasSync: true,
        recordRefresher: (record) async => GalleryDetailRefreshResult(
          record: record,
          hasPendingNasSync: pending = false,
        ),
      );
      final controller = _controller(detail)..start();

      expect(detail.needsLiveRefresh, isTrue);
      await controller.refreshNow();

      expect(pending, isFalse);
      expect(detail.needsLiveRefresh, isFalse);
      expect(controller.hasScheduledRefresh, isFalse);
      controller.dispose();
    });
  });
}

GalleryDetailLiveRefreshController _controller(GalleryDetailViewModel detail) =>
    GalleryDetailLiveRefreshController(
      interval: const Duration(days: 1),
      shouldRefresh: () => detail.needsLiveRefresh,
      refresh: detail.refreshCurrentRecord,
    );

ShootingRecord _record(
  PlateSolveQueueStatus? status, {
  String id = 'photo-1',
  PlateSolveResult? plateSolve,
}) => ShootingRecord(
  id: id,
  celestialObjectId: 'M31',
  capturedAt: DateTime.utc(2026, 8, 29),
  createdAt: DateTime.utc(2026, 8, 29),
  photoUri: 'https://backend.test/m31.jpg',
  plateSolveQueueStatus: status,
  plateSolveJobId: status == null ? null : 'job-1',
  plateSolve: plateSolve,
);

PlateSolveResult _wcs() => PlateSolveResult.success(
  centerRa: 10.6847,
  centerDec: 41.2688,
  rotation: 32,
  parity: 1,
  pixelScale: 2.4,
  fovWidth: 2,
  fovHeight: 1.5,
);

Future<void> _flushOverlay() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _FakeOverlayService extends PhotoOverlayService {
  _FakeOverlayService() : super(_UnusedCatalogRepository());

  int calls = 0;

  @override
  Future<PhotoOverlayResult> buildOverlay(ShootingRecord record) async {
    calls++;
    if (record.plateSolve?.success != true) {
      return const PhotoOverlayResult.unavailable(
        PhotoOverlayUnavailableReason.noPlateSolve,
      );
    }
    return const PhotoOverlayResult(
      imageWidth: 3000,
      imageHeight: 2250,
      objects: [],
    );
  }
}

class _UnusedCatalogRepository extends Fake implements CatalogRepository {}

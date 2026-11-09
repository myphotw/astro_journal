import 'dart:async';

import 'package:astro_journal/data/models/tc_backend_models.dart';
import 'package:astro_journal/services/gallery_incremental_refresh_service.dart';
import 'package:astro_journal/services/tc_backend_connection_manager.dart';
import 'package:astro_journal/services/tc_backend_sync_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

class _Connection extends Fake implements TcBackendConnectionManager {
  _Connection(this.currentStatus);

  TcBackendConnectionStatus currentStatus;

  @override
  TcBackendConnectionStatus get status => currentStatus;
}

class _Pull implements TcBackendDrainRunner {
  int calls = 0;
  Completer<void>? pending;

  @override
  Future<void> drain() async {
    calls++;
    final waitFor = pending;
    if (waitFor != null) await waitFor.future;
  }
}

void main() {
  test('foreground and gallery entry share one incremental pull', () async {
    final pull = _Pull()..pending = Completer<void>();
    final service = GalleryIncrementalRefreshService(
      pull: pull,
      connection: _Connection(TcBackendConnectionStatus.connected),
    );

    final foreground = service.refresh();
    final entry = service.refresh();
    expect(pull.calls, 1);
    pull.pending!.complete();
    expect(await foreground, GalleryRefreshResult.updated);
    expect(await entry, GalleryRefreshResult.updated);
  });

  test('recent entry is skipped, while manual refresh pulls again', () async {
    final pull = _Pull();
    var now = DateTime(2026, 11, 9, 12);
    final service = GalleryIncrementalRefreshService(
      pull: pull,
      connection: _Connection(TcBackendConnectionStatus.connected),
      now: () => now,
    );

    expect(await service.refresh(), GalleryRefreshResult.updated);
    expect(await service.refresh(), GalleryRefreshResult.recent);
    expect(pull.calls, 1);
    expect(await service.refresh(force: true), GalleryRefreshResult.recent);
    now = now.add(const Duration(seconds: 6));
    expect(await service.refresh(force: true), GalleryRefreshResult.updated);
    expect(pull.calls, 2);
    now = now.add(const Duration(seconds: 31));
    expect(await service.refresh(), GalleryRefreshResult.updated);
    expect(pull.calls, 3);
  });

  test('offline keeps local data and a failed pull can be retried', () async {
    final connection = _Connection(TcBackendConnectionStatus.notConfigured);
    final pull = _Pull();
    final service = GalleryIncrementalRefreshService(
      pull: pull,
      connection: connection,
    );

    expect(await service.refresh(), GalleryRefreshResult.offline);
    expect(pull.calls, 0);
    connection.currentStatus = TcBackendConnectionStatus.connected;
    pull.pending = Completer<void>();
    final failed = service.refresh();
    pull.pending!.completeError(StateError('network'));
    await expectLater(failed, throwsStateError);
    pull.pending = null;
    expect(await service.refresh(), GalleryRefreshResult.updated);
    expect(pull.calls, 2);
  });

  test(
    'startup drain keeps the existing pull while endpoint is probing',
    () async {
      final pull = _Pull();
      final service = GalleryIncrementalRefreshService(
        pull: pull,
        connection: _Connection(TcBackendConnectionStatus.checking),
      );

      await service.drain();
      expect(pull.calls, 1);
      expect(await service.refresh(), GalleryRefreshResult.offline);
    },
  );
}

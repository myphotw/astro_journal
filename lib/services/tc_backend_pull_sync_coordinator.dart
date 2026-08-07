import '../data/datasources/gallery_record_link_datasource.dart';
import '../data/datasources/sync_checkpoint_datasource.dart';
import '../data/models/tc_backend_change.dart';
import '../data/repositories/gallery_repository.dart';
import '../data/repositories/shooting_record_repository.dart';
import 'tc_backend_changes_service.dart';
import 'tc_backend_settings_service.dart';
import 'tc_backend_sync_coordinator.dart';
import 'tc_backend_sync_gate.dart';

class TcBackendPullSyncCoordinator implements TcBackendDrainRunner {
  factory TcBackendPullSyncCoordinator({
    required TcBackendChangesApi changesApi,
    required SyncCheckpointDataSource checkpoints,
    required GalleryRepository galleryRepository,
    required ShootingRecordRepository shootingRecordRepository,
    required GalleryRecordLinkDataSource recordLinks,
    required TcBackendSettingsService settingsService,
    required TcBackendSyncGate syncGate,
    int maxPagesPerDrain = 100,
  }) => TcBackendPullSyncCoordinator._(
    changesApi,
    checkpoints,
    galleryRepository,
    shootingRecordRepository,
    recordLinks,
    settingsService,
    syncGate,
    maxPagesPerDrain,
  );

  TcBackendPullSyncCoordinator._(
    this._changesApi,
    this._checkpoints,
    this._galleryRepository,
    this._shootingRecordRepository,
    this._recordLinks,
    this._settingsService,
    this._syncGate,
    this.maxPagesPerDrain,
  );

  static const streamName = 'common_changes:AstroJournal';

  final TcBackendChangesApi _changesApi;
  final SyncCheckpointDataSource _checkpoints;
  final GalleryRepository _galleryRepository;
  final ShootingRecordRepository _shootingRecordRepository;
  final GalleryRecordLinkDataSource _recordLinks;
  final TcBackendSettingsService _settingsService;
  final TcBackendSyncGate _syncGate;
  final int maxPagesPerDrain;
  bool _draining = false;

  @override
  Future<void> drain() async {
    if (_draining) return;
    _draining = true;
    try {
      final settings = await _settingsService.load();
      if (!settings.enabled || !settings.isConfigured) return;
      await _syncGate.runExclusive(_drainExclusive);
    } finally {
      _draining = false;
    }
  }

  Future<void> _drainExclusive() async {
    var cursor = await _checkpoints.readCursor(streamName);
    for (var pageIndex = 0; pageIndex < maxPagesPerDrain; pageIndex++) {
      final page = await _changesApi.getChanges(cursor: cursor);
      for (final change in page.changes) {
        if (!change.isObservationRecord) continue;
        await _apply(change);
      }

      final nextCursor = page.nextCursor;
      if (page.changes.isNotEmpty && nextCursor == null) {
        throw const TcBackendChangesException(
          'A non-empty changes page has no next cursor.',
        );
      }
      if (nextCursor != null && nextCursor != cursor) {
        await _checkpoints.writeCursor(streamName, nextCursor);
        cursor = nextCursor;
      }
      if (!page.hasMore) return;
    }
    throw const TcBackendChangesException(
      'Changes pagination exceeded the per-drain page limit.',
    );
  }

  Future<void> _apply(TcBackendChange change) async {
    switch (change.operation) {
      case TcBackendChangeOperation.create:
      case TcBackendChangeOperation.update:
        final cachedRevision = await _galleryRepository.getCachedRevision(
          change.resourceId,
        );
        if (change.revision != null &&
            cachedRevision != null &&
            cachedRevision >= change.revision!) {
          return;
        }
        final item = await _changesApi.getObservationRecord(change.resourceId);
        await _galleryRepository.upsertPulledItem(item);
      case TcBackendChangeOperation.delete:
        final revision = change.revision;
        if (revision == null) {
          throw const TcBackendChangesException(
            'ObservationRecord tombstone has no revision.',
          );
        }
        final applied = await _galleryRepository.applyPulledDelete(
          change.resourceId,
          revision: revision,
          deletedAt: change.deletedAt,
        );
        if (!applied) return;
        final localId = (await _recordLinks
            .localIdsByBackendRecordId())[change.resourceId];
        if (localId != null) {
          await _shootingRecordRepository.delete(localId);
        }
    }
  }
}

class TcBackendCompositeSyncRunner implements TcBackendDrainRunner {
  const TcBackendCompositeSyncRunner(this._runners);

  final List<TcBackendDrainRunner> _runners;

  @override
  Future<void> drain() async {
    for (final runner in _runners) {
      await runner.drain();
    }
  }
}

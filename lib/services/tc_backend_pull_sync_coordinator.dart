import '../data/datasources/gallery_record_link_datasource.dart';
import '../data/datasources/sync_checkpoint_datasource.dart';
import '../data/models/tc_backend_change.dart';
import '../data/repositories/gallery_repository.dart';
import '../data/repositories/shooting_record_repository.dart';
import 'tc_backend_changes_service.dart';
import 'catalog_capture_projection_service.dart';
import 'tc_backend_settings_service.dart';
import 'tc_backend_sync_coordinator.dart';
import 'tc_backend_sync_gate.dart';
import 'astrojournal_local_capture_reset_service.dart';

class TcBackendPullSyncCoordinator implements TcBackendDrainRunner {
  factory TcBackendPullSyncCoordinator({
    required TcBackendChangesApi changesApi,
    required SyncCheckpointDataSource checkpoints,
    required GalleryRepository galleryRepository,
    required ShootingRecordRepository shootingRecordRepository,
    required GalleryRecordLinkDataSource recordLinks,
    required TcBackendSettingsService settingsService,
    required TcBackendSyncGate syncGate,
    CatalogCaptureProjectionService? catalogCaptureProjection,
    AstroJournalLocalCaptureReset? localCaptureReset,
    Future<void> Function()? onObservationRecordsChanged,
    int maxPagesPerDrain = 100,
  }) => TcBackendPullSyncCoordinator._(
    changesApi,
    checkpoints,
    galleryRepository,
    shootingRecordRepository,
    recordLinks,
    settingsService,
    syncGate,
    catalogCaptureProjection,
    localCaptureReset,
    onObservationRecordsChanged,
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
    this._catalogCaptureProjection,
    this._localCaptureReset,
    this._onObservationRecordsChanged,
    this.maxPagesPerDrain,
  );

  static const streamName = SyncCheckpointStreams.astroJournalChanges;

  final TcBackendChangesApi _changesApi;
  final SyncCheckpointDataSource _checkpoints;
  final GalleryRepository _galleryRepository;
  final ShootingRecordRepository _shootingRecordRepository;
  final GalleryRecordLinkDataSource _recordLinks;
  final TcBackendSettingsService _settingsService;
  final TcBackendSyncGate _syncGate;
  final CatalogCaptureProjectionService? _catalogCaptureProjection;
  final AstroJournalLocalCaptureReset? _localCaptureReset;
  final Future<void> Function()? _onObservationRecordsChanged;
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
    var observationRecordsChanged = false;
    for (var pageIndex = 0; pageIndex < maxPagesPerDrain; pageIndex++) {
      final page = await _changesApi.getChanges(cursor: cursor);
      for (final change in page.changes) {
        if (change.isAstroJournalReset) {
          await _localCaptureReset?.clearCaptureData();
          continue;
        }
        if (!change.isObservationRecord) continue;
        observationRecordsChanged =
            await _apply(change) || observationRecordsChanged;
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
      if (!page.hasMore) {
        await _reconcileCatalog();
        if (observationRecordsChanged) {
          try {
            await _onObservationRecordsChanged?.call();
          } catch (_) {
            // The change and cursor are already durable. A UI refresh failure
            // must not replay the same remote mutation page.
          }
        }
        return;
      }
    }
    throw const TcBackendChangesException(
      'Changes pagination exceeded the per-drain page limit.',
    );
  }

  Future<void> _reconcileCatalog() async {
    final projection = _catalogCaptureProjection;
    if (projection == null) return;
    try {
      await projection.reconcileAll();
    } catch (_) {
      // Changes and cursor remain durable. Startup reconciliation retries the
      // rebuild without replaying remote mutations.
    }
  }

  Future<bool> _apply(TcBackendChange change) async {
    switch (change.operation) {
      case TcBackendChangeOperation.create:
      case TcBackendChangeOperation.update:
        final cachedRevision = await _galleryRepository.getCachedRevision(
          change.resourceId,
        );
        if (change.revision != null &&
            cachedRevision != null &&
            cachedRevision >= change.revision!) {
          return false;
        }
        final item = await _changesApi.getObservationRecord(change.resourceId);
        return _galleryRepository.upsertPulledItem(item);
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
        if (!applied) return false;
        final localId = (await _recordLinks
            .localIdsByBackendRecordId())[change.resourceId];
        if (localId != null) {
          await _shootingRecordRepository.delete(localId);
        }
        return true;
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

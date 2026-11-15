import '../data/datasources/gallery_record_link_datasource.dart';
import '../data/datasources/sync_checkpoint_datasource.dart';
import '../data/models/tc_backend_change.dart';
import '../data/models/gallery_item.dart';
import '../data/models/gallery_observation_projection.dart';
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
    Future<bool> Function(TcBackendChange change)? observationSiteChangeApplier,
    Future<bool> Function(TcBackendChange change)? equipmentChangeApplier,
    Future<bool> Function(TcBackendChange change)?
    multiNightFramingChangeApplier,
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
    observationSiteChangeApplier,
    equipmentChangeApplier,
    multiNightFramingChangeApplier,
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
    this._observationSiteChangeApplier,
    this._equipmentChangeApplier,
    this._multiNightFramingChangeApplier,
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
  final Future<bool> Function(TcBackendChange change)?
  _observationSiteChangeApplier;
  final Future<bool> Function(TcBackendChange change)? _equipmentChangeApplier;
  final Future<bool> Function(TcBackendChange change)?
  _multiNightFramingChangeApplier;
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
    try {
      for (var pageIndex = 0; pageIndex < maxPagesPerDrain; pageIndex++) {
        final page = await _changesApi.getChanges(cursor: cursor);
        for (final change in page.changes) {
          if (change.isAstroJournalReset) {
            await _localCaptureReset?.clearCaptureData();
            continue;
          }
          if (change.isObservationSite) {
            await _observationSiteChangeApplier?.call(change);
            continue;
          }
          if (change.isEquipment) {
            await _equipmentChangeApplier?.call(change);
            continue;
          }
          if (change.isMultiNightFramingReference) {
            await _multiNightFramingChangeApplier?.call(change);
            continue;
          }
          if (change.isGalleryVisibility) {
            observationRecordsChanged =
                await _applyVisibility(change) || observationRecordsChanged;
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
        // Finish bounded legacy-hidden rechecks before committing this page.
        // Transient detail errors preserve its checkpoint, but finally still
        // refreshes any successful mutations earlier in the page/recheck list.
        final gallery = _galleryRepository;
        if (!page.hasMore && gallery is GalleryVisibilityRepository) {
          final visibility = gallery as GalleryVisibilityRepository;
          for (final id in await visibility.takeHiddenRechecks()) {
            try {
              final item = await _changesApi.getObservationRecord(id);
              observationRecordsChanged =
                  await gallery.upsertPulledItem(item) ||
                  observationRecordsChanged;
            } on TcBackendChangesException catch (error) {
              if (error.statusCode != 404) rethrow;
            }
          }
        }
        if (nextCursor != null && nextCursor != cursor) {
          await _checkpoints.writeCursor(streamName, nextCursor);
          cursor = nextCursor;
        }
        if (!page.hasMore) {
          observationRecordsChanged =
              await _reconcileTombstonedRecordProjections() ||
              observationRecordsChanged;
          return;
        }
      }
      throw const TcBackendChangesException(
        'Changes pagination exceeded the per-drain page limit.',
      );
    } finally {
      // Include successful mutations in an unfinished page. Refresh failures
      // must neither hide the original error nor advance the page checkpoint.
      if (observationRecordsChanged) {
        await _reconcileCatalog();
        try {
          await _onObservationRecordsChanged?.call();
        } catch (_) {}
      }
    }
  }

  Future<bool> _reconcileTombstonedRecordProjections() async {
    final links = await _recordLinks.localIdsByBackendRecordId();
    final backendRecordIdByLocalId = {
      for (final entry in links.entries) entry.value: entry.key,
    };
    var changed = false;
    for (final record in List.of(await _shootingRecordRepository.getAll())) {
      final backendRecordId =
          GalleryObservationProjection.backendRecordIdFromRemoteLocalId(
            record.id,
          ) ??
          backendRecordIdByLocalId[record.id];
      if (backendRecordId == null ||
          await _galleryRepository.getAuthoritativeDeleteRevision(
                backendRecordId,
              ) ==
              null) {
        continue;
      }
      await _shootingRecordRepository.delete(record.id);
      changed = true;
    }
    return changed;
  }

  Future<void> _reconcileCatalog() async {
    final projection = _catalogCaptureProjection;
    if (projection == null) return;
    try {
      await projection.reconcileAll(cacheOnly: true);
    } catch (_) {
      // Changes and cursor remain durable. Startup reconciliation retries the
      // rebuild without replaying remote mutations.
    }
  }

  Future<bool> _apply(TcBackendChange change) async {
    switch (change.operation) {
      case TcBackendChangeOperation.create:
      case TcBackendChangeOperation.update:
        if (change.currentResourceState == TcBackendResourceState.deleted ||
            change.currentResourceState == TcBackendResourceState.missing ||
            change.currentResourceState == TcBackendResourceState.unavailable) {
          return _removeProjection(change);
        }
        final cachedRevision = await _galleryRepository.getCachedRevision(
          change.resourceId,
        );
        final effectiveRevision = change.currentRevision ?? change.revision;
        final gallery = _galleryRepository;
        if (gallery is GalleryResourceStateRepository) {
          if (!await (gallery as GalleryResourceStateRepository)
              .shouldFetchPulledItem(change.resourceId, effectiveRevision)) {
            return false;
          }
        } else if (await gallery.getAuthoritativeDeleteRevision(
                  change.resourceId,
                ) !=
                null ||
            (effectiveRevision != null &&
                cachedRevision != null &&
                cachedRevision >= effectiveRevision)) {
          return false;
        }
        final GalleryItem item;
        try {
          item = await _changesApi.getObservationRecord(change.resourceId);
        } on TcBackendChangesException catch (error) {
          // Only a canonical ObservationRecord detail 404 is absence evidence.
          // Authentication, transport, parsing and all other HTTP errors retry.
          if (error.statusCode != 404) rethrow;
          return _removeProjection(
            change,
            hiddenState: TcBackendResourceState.missing,
          );
        }
        return _galleryRepository.upsertPulledItem(item);
      case TcBackendChangeOperation.delete:
        final revision = change.revision;
        if (revision == null) {
          throw const TcBackendChangesException(
            'ObservationRecord tombstone has no revision.',
          );
        }
        return _removeProjection(change, revision: revision);
    }
  }

  Future<bool> _applyVisibility(TcBackendChange change) async {
    if (change.operation != TcBackendChangeOperation.update) return false;
    final gallery = _galleryRepository;
    if (await gallery.getAuthoritativeDeleteRevision(change.resourceId) !=
        null) {
      return false;
    }
    if (gallery is! GalleryVisibilityRepository) {
      // Older repository implementations still get safe detail/404 handling.
      return _apply(change);
    }
    final visibility = gallery as GalleryVisibilityRepository;
    final cursor = change.cursor;
    if (cursor == null || BigInt.tryParse(cursor) == null) {
      throw const TcBackendChangesException(
        'Visibility event has no valid cursor.',
      );
    }
    if (!await visibility.shouldApplyVisibilityEvent(
      change.resourceId,
      cursor,
    )) {
      return false;
    }
    final state = change.currentResourceState;
    if (state == TcBackendResourceState.deleted ||
        state == TcBackendResourceState.missing ||
        state == TcBackendResourceState.unavailable) {
      return _removeProjection(change, visibilityCursor: cursor);
    }
    // Null/unknown state is not deletion evidence: confirm via canonical detail.
    final GalleryItem item;
    try {
      item = await _changesApi.getObservationRecord(change.resourceId);
    } on TcBackendChangesException catch (error) {
      if (error.statusCode != 404) rethrow;
      return _removeProjection(
        change,
        hiddenState: TcBackendResourceState.missing,
        visibilityCursor: cursor,
      );
    }
    return visibility.upsertVisibilityItem(item, cursor);
  }

  Future<bool> _removeProjection(
    TcBackendChange change, {
    int? revision,
    TcBackendResourceState? hiddenState,
    String? visibilityCursor,
  }) async {
    final cachedRevision = await _galleryRepository.getCachedRevision(
      change.resourceId,
    );
    final removalRevision =
        revision ??
        change.currentRevision ??
        change.revision ??
        cachedRevision ??
        0;
    final state = hiddenState ?? change.currentResourceState;
    final gallery = _galleryRepository;
    final soft =
        revision == null &&
        (state == TcBackendResourceState.missing ||
            state == TcBackendResourceState.unavailable) &&
        gallery is GalleryResourceStateRepository;
    final applied =
        soft &&
            visibilityCursor != null &&
            gallery is GalleryVisibilityRepository
        ? await (gallery as GalleryVisibilityRepository).applyVisibilityHidden(
            change.resourceId,
            revision: removalRevision,
            state: state!,
            cursor: visibilityCursor,
          )
        : soft
        ? await (gallery as GalleryResourceStateRepository).applyPulledHidden(
            change.resourceId,
            revision: removalRevision,
            state: state!,
          )
        : await gallery.applyPulledDelete(
            change.resourceId,
            revision: removalRevision,
            deletedAt: change.deletedAt,
          );
    // A crash can leave local rows behind an already durable tombstone.
    // Never remove rows if a newer live revision supersedes that tombstone.
    final removal =
        await gallery.getAuthoritativeDeleteRevision(change.resourceId) ??
        (gallery is GalleryResourceStateRepository
            ? await (gallery as GalleryResourceStateRepository)
                  .getHiddenRevision(change.resourceId)
            : null);
    if (removal == null) {
      return false;
    }
    final linkedLocalId = (await _recordLinks
        .localIdsByBackendRecordId())[change.resourceId];
    final localIds = <String>{
      ?linkedLocalId,
      GalleryObservationProjection.remoteLocalId(change.resourceId),
    };
    var changed = applied;
    for (final localId in localIds) {
      if (await _shootingRecordRepository.getById(localId) != null) {
        await _shootingRecordRepository.delete(localId);
        changed = true;
      }
    }
    return changed;
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

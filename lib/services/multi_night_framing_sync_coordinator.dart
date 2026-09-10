import '../data/datasources/multi_night_framing_local_datasource.dart';
import '../data/models/multi_night_framing_reference.dart';
import '../data/models/multi_night_framing_sync_item.dart';
import '../data/models/tc_backend_change.dart';
import 'tc_backend_multi_night_framing_service.dart';
import 'tc_backend_settings_service.dart';
import 'tc_backend_sync_coordinator.dart';
import 'tc_backend_sync_gate.dart';

class MultiNightFramingSyncCoordinator implements TcBackendDrainRunner {
  MultiNightFramingSyncCoordinator({
    required MultiNightFramingRemoteApi remoteApi,
    required MultiNightFramingLocalDataSource localDataSource,
    required TcBackendSettingsService settingsService,
    required TcBackendSyncGate syncGate,
    this.scheduleDrain,
    this.onCollectionChanged,
  }) : _remoteApi = remoteApi,
       _local = localDataSource,
       _settings = settingsService,
       _syncGate = syncGate;

  final MultiNightFramingRemoteApi _remoteApi;
  final MultiNightFramingLocalDataSource _local;
  final TcBackendSettingsService _settings;
  final TcBackendSyncGate _syncGate;
  final TcBackendDrainScheduler? scheduleDrain;
  final Future<void> Function()? onCollectionChanged;
  bool _draining = false;
  bool _retryScheduled = false;

  @override
  Future<void> drain() async {
    if (_draining) return;
    _draining = true;
    try {
      final settings = await _settings.load();
      if (!settings.enabled || !settings.isConfigured) return;
      await _syncGate.runExclusive(_drainExclusive);
    } finally {
      _draining = false;
    }
  }

  Future<void> _drainExclusive() async {
    late final List<MultiNightFramingReference> remoteReferences;
    try {
      remoteReferences = await _remoteApi.list();
    } on MultiNightFramingRemoteException catch (error) {
      if (_isOfflineOrUnavailable(error)) return;
      rethrow;
    }

    var changed = false;
    final remoteById = {for (final value in remoteReferences) value.id: value};
    final localBefore = await _local.list(includeDeleted: true);
    for (final reference in remoteReferences) {
      final sameIdentity = await _local.findIdentity(
        catalogObjectId: reference.catalogObjectId,
        equipmentId: reference.equipmentId,
      );
      if (sameIdentity != null &&
          sameIdentity.id != reference.id &&
          await _local.hasPendingSync(sameIdentity.id)) {
        changed =
            await _local.preserveIdentityConflict(sameIdentity, reference) ||
            changed;
        continue;
      }
      if (await _local.hasPendingSync(reference.id)) {
        await _local.saveRemoteSnapshotOnly(reference);
        continue;
      }
      changed = await _local.applyRemote(reference) || changed;
    }
    for (final reference in localBefore) {
      final metadata = await _local.getSyncMetadata(reference.id);
      if (metadata?.serverRevision == null) continue;
      if (!remoteById.containsKey(reference.id)) {
        changed = await _local.applyRemoteMissing(reference.id) || changed;
      }
    }
    for (final item in await _local.listPendingSync()) {
      changed = await _process(item) || changed;
    }
    if (changed) await _notifyChanged();
  }

  Future<bool> _process(MultiNightFramingSyncItem item) async {
    await _local.markProcessing(item.operationId);
    late final MultiNightFramingReference snapshot;
    try {
      snapshot = MultiNightFramingReference.fromJson(item.payload);
      switch (item.operation) {
        case MultiNightFramingSyncOperation.create:
          final canonical = await _remoteApi.create(snapshot);
          final changed = await _local.applyRemote(canonical, force: true);
          await _local.markSucceeded(item.operationId);
          await _local.rebaseQueued(item.referenceId, canonical.revision);
          return changed;
        case MultiNightFramingSyncOperation.update:
          final revision =
              item.baseRevision ??
              (await _local.getSyncMetadata(item.referenceId))?.serverRevision;
          if (revision == null) {
            final canonical = await _remoteApi.create(snapshot);
            final changed = await _local.applyRemote(canonical, force: true);
            await _local.markSucceeded(item.operationId);
            await _local.rebaseQueued(item.referenceId, canonical.revision);
            return changed;
          }
          final canonical = await _remoteApi.update(
            snapshot,
            expectedRevision: revision,
          );
          final changed = await _local.applyRemote(canonical, force: true);
          await _local.markSucceeded(item.operationId);
          await _local.rebaseQueued(item.referenceId, canonical.revision);
          return changed;
        case MultiNightFramingSyncOperation.delete:
          final revision =
              item.baseRevision ??
              (await _local.getSyncMetadata(item.referenceId))?.serverRevision;
          if (revision == null) {
            await _local.markConflict(
              item,
              'Reference delete has no server revision.',
            );
            return true;
          }
          final deleted = await _remoteApi.delete(
            item.referenceId,
            expectedRevision: revision,
          );
          final changed = await _local.applyRemoteDelete(
            referenceId: deleted.referenceId,
            revision: deleted.revision,
            deletedAt: deleted.deletedAt,
            force: true,
          );
          await _local.markSucceeded(item.operationId);
          return changed;
      }
    } on FormatException catch (error) {
      await _local.markConflict(item, 'Malformed local snapshot: $error');
      return true;
    } on MultiNightFramingRemoteException catch (error) {
      if (item.operation == MultiNightFramingSyncOperation.delete &&
          error.type == MultiNightFramingRemoteErrorType.notFound) {
        await _local.markSucceeded(item.operationId);
        return false;
      }
      if (error.type == MultiNightFramingRemoteErrorType.revisionConflict ||
          error.type ==
              MultiNightFramingRemoteErrorType.referenceAlreadyExists ||
          error.type == MultiNightFramingRemoteErrorType.conflict) {
        MultiNightFramingReference? server;
        try {
          if (error.type ==
              MultiNightFramingRemoteErrorType.referenceAlreadyExists) {
            final matches = await _remoteApi.list(
              catalogObjectId: snapshot.catalogObjectId,
              equipmentId: snapshot.equipmentId,
            );
            server = matches.isEmpty ? null : matches.first;
          } else {
            server = await _remoteApi.get(item.referenceId);
          }
        } on MultiNightFramingRemoteException {
          // The user's optimistic value remains local and conflict is durable.
        }
        final message =
            error.type ==
                MultiNightFramingRemoteErrorType.referenceAlreadyExists
            ? 'REFERENCE_ALREADY_EXISTS'
            : 'REVISION_CONFLICT current_revision=${error.currentRevision}';
        await _local.markConflict(item, message, serverReference: server);
        return true;
      }
      if (error.isRetryable) {
        await _local.markFailed(item, error.message);
        final retry = item.retryCount + 1;
        if (retry <= 3) {
          _scheduleRetry(switch (retry) {
            1 => const Duration(seconds: 5),
            2 => const Duration(seconds: 15),
            _ => const Duration(seconds: 60),
          });
        }
      } else {
        await _local.markConflict(item, error.message);
        return true;
      }
      return false;
    }
  }

  /// The common changes pull coordinator already owns the shared sync gate.
  Future<bool> applyChange(TcBackendChange change) async {
    if (!change.isMultiNightFramingReference) return false;
    if (change.operation == TcBackendChangeOperation.delete) {
      final revision = change.revision;
      if (revision == null) {
        throw const MultiNightFramingRemoteException(
          type: MultiNightFramingRemoteErrorType.malformedResponse,
          message: 'Reference tombstone has no revision.',
        );
      }
      final changed = await _local.applyRemoteDelete(
        referenceId: change.resourceId,
        revision: revision,
        deletedAt: change.deletedAt ?? DateTime.now().toUtc(),
      );
      if (changed) await _notifyChanged();
      return changed;
    }

    final metadata = await _local.getSyncMetadata(change.resourceId);
    if (change.revision != null &&
        metadata?.serverRevision != null &&
        metadata!.serverRevision! >= change.revision!) {
      return false;
    }
    final canonical = await _remoteApi.get(change.resourceId);
    final sameIdentity = await _local.findIdentity(
      catalogObjectId: canonical.catalogObjectId,
      equipmentId: canonical.equipmentId,
    );
    if (sameIdentity != null &&
        sameIdentity.id != canonical.id &&
        await _local.hasPendingSync(sameIdentity.id)) {
      await _local.preserveIdentityConflict(sameIdentity, canonical);
      await _notifyChanged();
      return false;
    }
    if (await _local.hasPendingSync(change.resourceId)) {
      await _local.saveRemoteSnapshotOnly(canonical);
      return false;
    }
    final changed = await _local.applyRemote(canonical);
    if (changed) await _notifyChanged();
    return changed;
  }

  bool _isOfflineOrUnavailable(MultiNightFramingRemoteException error) =>
      error.type == MultiNightFramingRemoteErrorType.notConfigured ||
      error.type == MultiNightFramingRemoteErrorType.network ||
      error.type == MultiNightFramingRemoteErrorType.timeout ||
      error.type == MultiNightFramingRemoteErrorType.server ||
      error.type == MultiNightFramingRemoteErrorType.notFound;

  Future<void> _notifyChanged() async {
    try {
      await onCollectionChanged?.call();
    } catch (_) {
      // The canonical projection is already durable; UI refresh can retry.
    }
  }

  void _scheduleRetry(Duration delay) {
    final scheduler = scheduleDrain;
    if (scheduler == null || _retryScheduled) return;
    _retryScheduled = true;
    scheduler(delay, () async {
      _retryScheduled = false;
      await drain();
    });
  }
}

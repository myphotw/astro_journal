import 'dart:convert';

import '../data/datasources/equipment_local_datasource.dart';
import '../data/models/equipment.dart';
import '../data/models/equipment_remote.dart';
import '../data/models/equipment_sync_item.dart';
import '../data/models/tc_backend_change.dart';
import 'tc_backend_equipment_service.dart';
import 'tc_backend_settings_service.dart';
import 'tc_backend_sync_coordinator.dart';
import 'tc_backend_sync_gate.dart';

class EquipmentSyncCoordinator implements TcBackendDrainRunner {
  EquipmentSyncCoordinator({
    required EquipmentRemoteApi remoteApi,
    required EquipmentLocalDataSource localDataSource,
    required TcBackendSettingsService settingsService,
    required TcBackendSyncGate syncGate,
    this.scheduleDrain,
    this.onCollectionChanged,
    this.onEquipmentConditionsChanged,
    this.onServerReferencesReady,
  }) : _remoteApi = remoteApi,
       _local = localDataSource,
       _settings = settingsService,
       _syncGate = syncGate;

  final EquipmentRemoteApi _remoteApi;
  final EquipmentLocalDataSource _local;
  final TcBackendSettingsService _settings;
  final TcBackendSyncGate _syncGate;
  final TcBackendDrainScheduler? scheduleDrain;
  final Future<void> Function()? onCollectionChanged;
  final Future<void> Function()? onEquipmentConditionsChanged;
  final Future<void> Function()? onServerReferencesReady;
  bool _draining = false;
  bool _retryScheduled = false;

  @override
  Future<void> drain() async {
    if (_draining) return;
    _draining = true;
    var serverListSucceeded = false;
    try {
      final settings = await _settings.load();
      if (!settings.enabled || !settings.isConfigured) return;
      await _syncGate.runExclusive(() async {
        serverListSucceeded = await _drainExclusive();
      });
      if (serverListSucceeded) {
        try {
          await onServerReferencesReady?.call();
        } catch (_) {
          // Equipment is already durable. A dependent site drain can retry.
        }
      }
    } finally {
      _draining = false;
    }
  }

  Future<bool> _drainExclusive() async {
    late final List<EquipmentRemoteAggregate> remoteEquipment;
    try {
      remoteEquipment = await _remoteApi.list();
    } on EquipmentRemoteException catch (error) {
      if (_isOfflineOrUnavailable(error)) return false;
      rethrow;
    }

    var impact = _SyncImpact.none;
    final remoteById = {
      for (final aggregate in remoteEquipment)
        aggregate.equipment.id: aggregate,
    };
    final localBefore = await _local.getAll();

    for (final aggregate in remoteEquipment) {
      if (await _local.hasPendingSync(aggregate.equipment.id)) {
        await _local.saveRemoteSnapshotOnly(aggregate);
        continue;
      }
      final before = await _local.getById(aggregate.equipment.id);
      final changed = await _local.applyRemoteAggregate(aggregate);
      if (!changed) continue;
      final after = await _local.getById(aggregate.equipment.id);
      impact = impact.merge(
        _SyncImpact(
          collection: true,
          observing: _equipmentConditionsDiffer(before, after),
        ),
      );
    }

    for (final equipment in localBefore) {
      final metadata = await _local.getSyncMetadata(equipment.id);
      if (metadata?.serverRevision == null) {
        await _local.ensureBootstrapQueued(equipment);
        continue;
      }
      if (!remoteById.containsKey(equipment.id) &&
          !await _local.hasPendingSync(equipment.id)) {
        final removed = await _local.applyRemoteMissing(equipment.id);
        if (removed) {
          impact = impact.merge(
            const _SyncImpact(collection: true, observing: true),
          );
        }
      }
    }

    for (final item in await _local.listPendingSync()) {
      impact = impact.merge(await _process(item));
    }
    await _notify(impact);
    return true;
  }

  Future<_SyncImpact> _process(EquipmentSyncItem item) async {
    await _local.markSyncProcessing(item.operationId);
    try {
      final snapshot = EquipmentRemoteAggregate.fromJson(item.payload);
      final before = await _local.getById(item.equipmentId);
      switch (item.operation) {
        case EquipmentSyncOperation.create:
          final canonical = await _remoteApi.create(snapshot.equipment);
          final changed = await _local.applyRemoteAggregate(
            canonical,
            force: true,
          );
          await _local.markSyncSucceeded(item.operationId);
          await _local.rebaseQueuedSync(item.equipmentId, canonical.revision);
          final after = await _local.getById(item.equipmentId);
          return _SyncImpact(
            collection: changed,
            observing: changed && _equipmentConditionsDiffer(before, after),
          );
        case EquipmentSyncOperation.update:
          final revision =
              item.baseRevision ??
              (await _local.getSyncMetadata(item.equipmentId))?.serverRevision;
          if (revision == null) {
            final canonical = await _remoteApi.create(snapshot.equipment);
            final changed = await _local.applyRemoteAggregate(
              canonical,
              force: true,
            );
            await _local.markSyncSucceeded(item.operationId);
            await _local.rebaseQueuedSync(item.equipmentId, canonical.revision);
            final after = await _local.getById(item.equipmentId);
            return _SyncImpact(
              collection: changed,
              observing: changed && _equipmentConditionsDiffer(before, after),
            );
          }
          final canonical = await _remoteApi.update(
            snapshot.equipment,
            expectedRevision: revision,
          );
          final changed = await _local.applyRemoteAggregate(
            canonical,
            force: true,
          );
          await _local.markSyncSucceeded(item.operationId);
          await _local.rebaseQueuedSync(item.equipmentId, canonical.revision);
          final after = await _local.getById(item.equipmentId);
          return _SyncImpact(
            collection: changed,
            observing: changed && _equipmentConditionsDiffer(before, after),
          );
        case EquipmentSyncOperation.delete:
          final revision =
              item.baseRevision ??
              (await _local.getSyncMetadata(item.equipmentId))?.serverRevision;
          if (revision == null) {
            await _local.markSyncConflict(
              item,
              'Equipment delete has no server revision.',
            );
            return _SyncImpact.none;
          }
          final deleted = await _remoteApi.delete(
            item.equipmentId,
            expectedRevision: revision,
          );
          final changed = await _local.applyRemoteDelete(
            equipmentId: deleted.equipmentId,
            revision: deleted.revision,
            deletedAt: deleted.deletedAt,
            force: true,
          );
          await _local.markSyncSucceeded(item.operationId);
          return _SyncImpact(collection: changed, observing: changed);
      }
    } on FormatException catch (error) {
      await _local.markSyncConflict(item, 'Malformed local snapshot: $error');
      return _SyncImpact.none;
    } on EquipmentRemoteException catch (error) {
      if (item.operation == EquipmentSyncOperation.delete &&
          error.type == EquipmentRemoteErrorType.notFound) {
        await _local.markSyncSucceeded(item.operationId);
        return _SyncImpact.none;
      }
      if (error.type == EquipmentRemoteErrorType.conflict) {
        EquipmentRemoteAggregate? server;
        try {
          server = await _remoteApi.get(item.equipmentId);
        } on EquipmentRemoteException {
          // Keep the original conflict durable if detail recovery is offline.
        }
        await _local.markSyncConflict(
          item,
          'REVISION_CONFLICT current_revision=${error.currentRevision}',
          serverAggregate: server,
        );
        return _SyncImpact.none;
      }
      if (error.isRetryable) {
        await _local.markSyncFailed(item, error.message);
        final retry = item.retryCount + 1;
        if (retry <= 3) {
          _scheduleRetry(switch (retry) {
            1 => const Duration(seconds: 5),
            2 => const Duration(seconds: 15),
            _ => const Duration(seconds: 60),
          });
        }
      } else {
        await _local.markSyncConflict(item, error.message);
      }
      return _SyncImpact.none;
    }
  }

  /// The common changes coordinator already owns the shared sync gate.
  Future<bool> applyChange(TcBackendChange change) async {
    if (!change.isEquipment) return false;
    if (change.operation == TcBackendChangeOperation.delete) {
      final revision = change.revision;
      if (revision == null) {
        throw const EquipmentRemoteException(
          type: EquipmentRemoteErrorType.malformedResponse,
          message: 'Equipment tombstone has no revision.',
        );
      }
      final changed = await _local.applyRemoteDelete(
        equipmentId: change.resourceId,
        revision: revision,
        deletedAt: change.deletedAt ?? DateTime.now().toUtc(),
      );
      if (changed) {
        await _notify(const _SyncImpact(collection: true, observing: true));
      }
      return changed;
    }

    final metadata = await _local.getSyncMetadata(change.resourceId);
    if (change.revision != null &&
        metadata?.serverRevision != null &&
        metadata!.serverRevision! >= change.revision!) {
      return false;
    }
    final aggregate = await _remoteApi.get(change.resourceId);
    if (await _local.hasPendingSync(change.resourceId)) {
      await _local.saveRemoteSnapshotOnly(aggregate);
      return false;
    }
    final before = await _local.getById(change.resourceId);
    final changed = await _local.applyRemoteAggregate(aggregate);
    if (!changed) return false;
    final after = await _local.getById(change.resourceId);
    await _notify(
      _SyncImpact(
        collection: true,
        observing: _equipmentConditionsDiffer(before, after),
      ),
    );
    return true;
  }

  bool _isOfflineOrUnavailable(EquipmentRemoteException error) =>
      error.type == EquipmentRemoteErrorType.notConfigured ||
      error.type == EquipmentRemoteErrorType.network ||
      error.type == EquipmentRemoteErrorType.timeout ||
      error.type == EquipmentRemoteErrorType.server ||
      error.type == EquipmentRemoteErrorType.notFound;

  Future<void> _notify(_SyncImpact impact) async {
    if (impact.collection) {
      try {
        await onCollectionChanged?.call();
      } catch (_) {
        // The canonical cache is already durable; UI refresh can retry.
      }
    }
    if (impact.observing) {
      try {
        await onEquipmentConditionsChanged?.call();
      } catch (_) {
        // Recommendation refresh must not replay a remote mutation.
      }
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

class _SyncImpact {
  const _SyncImpact({required this.collection, required this.observing});

  static const none = _SyncImpact(collection: false, observing: false);

  final bool collection;
  final bool observing;

  _SyncImpact merge(_SyncImpact other) => _SyncImpact(
    collection: collection || other.collection,
    observing: observing || other.observing,
  );
}

bool _equipmentConditionsDiffer(Equipment? before, Equipment? after) {
  if (before == null || after == null) return before != after;
  Object signature(Equipment value) => {
    'kind': value.kind.name,
    'purpose': value.purpose.name,
    'active': value.isActive,
    'focal': value.focalLengthMm,
    'aperture': value.apertureMm,
    'fov_width': value.fovWidthDegrees,
    'fov_height': value.fovHeightDegrees,
    'eyepieces': value.eyepieces.map((item) => item.toMap()).toList(),
  };
  return jsonEncode(signature(before)) != jsonEncode(signature(after));
}

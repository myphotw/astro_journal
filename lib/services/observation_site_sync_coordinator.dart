import 'dart:convert';

import '../data/datasources/observation_site_local_datasource.dart';
import '../data/models/observation_site.dart';
import '../data/models/observation_site_remote.dart';
import '../data/models/observation_site_sync_item.dart';
import '../data/models/tc_backend_change.dart';
import 'tc_backend_observation_site_service.dart';
import 'tc_backend_settings_service.dart';
import 'tc_backend_sync_coordinator.dart';
import 'tc_backend_sync_gate.dart';

class ObservationSiteSyncCoordinator implements TcBackendDrainRunner {
  ObservationSiteSyncCoordinator({
    required ObservationSiteRemoteApi remoteApi,
    required ObservationSiteLocalDataSource localDataSource,
    required TcBackendSettingsService settingsService,
    required TcBackendSyncGate syncGate,
    this.scheduleDrain,
    this.onCollectionChanged,
    this.onObservingConditionsChanged,
    this.canReferenceDefaultEquipment,
    this.hasLocalDefaultEquipment,
  }) : _remoteApi = remoteApi,
       _local = localDataSource,
       _settings = settingsService,
       _syncGate = syncGate;

  final ObservationSiteRemoteApi _remoteApi;
  final ObservationSiteLocalDataSource _local;
  final TcBackendSettingsService _settings;
  final TcBackendSyncGate _syncGate;
  final TcBackendDrainScheduler? scheduleDrain;
  final Future<void> Function()? onCollectionChanged;
  final Future<void> Function()? onObservingConditionsChanged;
  final Future<bool> Function(String equipmentId)? canReferenceDefaultEquipment;
  final Future<bool> Function(String equipmentId)? hasLocalDefaultEquipment;
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
    late final List<ObservationSiteRemoteAggregate> remoteSites;
    try {
      remoteSites = await _remoteApi.list();
    } on ObservationSiteRemoteException catch (error) {
      if (_isOfflineOrUnavailable(error)) return;
      rethrow;
    }

    var impact = _SyncImpact.none;
    final remoteById = {
      for (final aggregate in remoteSites) aggregate.site.id: aggregate,
    };
    final localBefore = await _local.list();

    for (final aggregate in remoteSites) {
      if (await _local.hasPendingSync(aggregate.site.id)) {
        await _local.saveRemoteSnapshotOnly(aggregate);
        continue;
      }
      final before = await _local.get(aggregate.site.id, includeDeleted: true);
      if (before?.defaultEquipmentId != null &&
          aggregate.site.defaultEquipmentId == null &&
          await _canReference(before!.defaultEquipmentId!)) {
        await _local.saveRemoteSnapshotOnly(aggregate);
        await _local.enqueueCurrentUpdate(before);
        continue;
      }
      final changed = await _local.applyRemoteAggregate(
        aggregate,
        preserveLocalDefaultEquipment: await _shouldPreserveLocalDefault(
          before,
        ),
      );
      if (!changed) continue;
      final after = await _local.get(aggregate.site.id, includeDeleted: true);
      impact = impact.merge(
        _SyncImpact(
          collection: true,
          observing: _observingConditionsDiffer(before, after),
        ),
      );
    }

    for (final site in localBefore) {
      final metadata = await _local.getSyncMetadata(site.id);
      if (metadata?.serverRevision == null) {
        await _local.ensureBootstrapQueued(site);
        continue;
      }
      if (!remoteById.containsKey(site.id) &&
          !await _local.hasPendingSync(site.id)) {
        final removed = await _local.applyRemoteMissing(site.id);
        if (removed) {
          impact = impact.merge(
            const _SyncImpact(collection: true, observing: true),
          );
        }
      }
    }

    final pending = await _local.listPendingSync();
    for (final item in pending) {
      impact = impact.merge(await _process(item));
    }
    await _notify(impact);
  }

  Future<_SyncImpact> _process(ObservationSiteSyncItem item) async {
    await _local.markSyncProcessing(item.operationId);
    try {
      final snapshot = ObservationSiteRemoteAggregate.fromJson(item.payload);
      final before = await _local.get(item.siteId, includeDeleted: true);
      switch (item.operation) {
        case ObservationSiteSyncOperation.create:
          final canonical = await _remoteApi.create(snapshot.site);
          final changed = await _local.applyRemoteAggregate(
            canonical,
            force: true,
          );
          await _local.markSyncSucceeded(item.operationId);
          await _local.rebaseQueuedSync(item.siteId, canonical.revision);
          final after = await _local.get(item.siteId, includeDeleted: true);
          return _SyncImpact(
            collection: changed,
            observing: changed && _observingConditionsDiffer(before, after),
          );
        case ObservationSiteSyncOperation.update:
          final revision =
              item.baseRevision ??
              (await _local.getSyncMetadata(item.siteId))?.serverRevision;
          if (revision == null) {
            final canonical = await _remoteApi.create(snapshot.site);
            final changed = await _local.applyRemoteAggregate(
              canonical,
              force: true,
            );
            await _local.markSyncSucceeded(item.operationId);
            await _local.rebaseQueuedSync(item.siteId, canonical.revision);
            final after = await _local.get(item.siteId, includeDeleted: true);
            return _SyncImpact(
              collection: changed,
              observing: changed && _observingConditionsDiffer(before, after),
            );
          }
          final canonical = await _remoteApi.update(
            snapshot.site,
            expectedRevision: revision,
          );
          final changed = await _local.applyRemoteAggregate(
            canonical,
            force: true,
          );
          await _local.markSyncSucceeded(item.operationId);
          await _local.rebaseQueuedSync(item.siteId, canonical.revision);
          final after = await _local.get(item.siteId, includeDeleted: true);
          return _SyncImpact(
            collection: changed,
            observing: changed && _observingConditionsDiffer(before, after),
          );
        case ObservationSiteSyncOperation.delete:
          final revision =
              item.baseRevision ??
              (await _local.getSyncMetadata(item.siteId))?.serverRevision;
          if (revision == null) {
            await _local.markSyncConflict(
              item,
              'ObservationSite delete has no server revision.',
            );
            return _SyncImpact.none;
          }
          final deleted = await _remoteApi.delete(
            item.siteId,
            expectedRevision: revision,
          );
          final changed = await _local.applyRemoteDelete(
            siteId: deleted.siteId,
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
    } on ObservationSiteRemoteException catch (error) {
      if (item.operation == ObservationSiteSyncOperation.delete &&
          error.type == ObservationSiteRemoteErrorType.notFound) {
        await _local.markSyncSucceeded(item.operationId);
        return _SyncImpact.none;
      }
      if (error.type == ObservationSiteRemoteErrorType.conflict) {
        ObservationSiteRemoteAggregate? server;
        try {
          server = await _remoteApi.get(item.siteId);
        } on ObservationSiteRemoteException {
          // The original conflict remains durable even if detail recovery is
          // temporarily unavailable.
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
        final nextRetry = item.retryCount + 1;
        if (nextRetry <= 3) {
          _scheduleRetry(switch (nextRetry) {
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

  /// Called by the shared common-changes consumer. It deliberately does not
  /// acquire [_syncGate], because that consumer already owns the shared gate.
  Future<bool> applyChange(TcBackendChange change) async {
    if (!change.isObservationSite) return false;
    if (change.operation == TcBackendChangeOperation.delete) {
      final revision = change.revision;
      if (revision == null) {
        throw const ObservationSiteRemoteException(
          type: ObservationSiteRemoteErrorType.malformedResponse,
          message: 'ObservationSite tombstone has no revision.',
        );
      }
      final changed = await _local.applyRemoteDelete(
        siteId: change.resourceId,
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
    final before = await _local.get(change.resourceId, includeDeleted: true);
    final changed = await _local.applyRemoteAggregate(
      aggregate,
      // A change-feed UPDATE is explicit canonical state. In particular,
      // Equipment deletion emits the Site UPDATE before its Equipment
      // tombstone, so a null default must not be preserved here.
      preserveLocalDefaultEquipment: false,
    );
    if (!changed) return false;
    final after = await _local.get(change.resourceId, includeDeleted: true);
    await _notify(
      _SyncImpact(
        collection: true,
        observing: _observingConditionsDiffer(before, after),
      ),
    );
    return true;
  }

  Future<bool> _canReference(String equipmentId) async {
    final predicate = canReferenceDefaultEquipment;
    return predicate != null && await predicate(equipmentId);
  }

  Future<bool> _shouldPreserveLocalDefault(ObservationSite? site) async {
    if (canReferenceDefaultEquipment == null) return true;
    final equipmentId = site?.defaultEquipmentId;
    if (equipmentId == null) return false;
    final predicate = hasLocalDefaultEquipment;
    return predicate != null && await predicate(equipmentId);
  }

  bool _isOfflineOrUnavailable(ObservationSiteRemoteException error) =>
      error.type == ObservationSiteRemoteErrorType.notConfigured ||
      error.type == ObservationSiteRemoteErrorType.network ||
      error.type == ObservationSiteRemoteErrorType.timeout ||
      error.type == ObservationSiteRemoteErrorType.server ||
      error.type == ObservationSiteRemoteErrorType.notFound;

  Future<void> _notify(_SyncImpact impact) async {
    if (impact.collection) {
      try {
        await onCollectionChanged?.call();
      } catch (_) {
        // Cache and sync state are already durable; UI refresh can retry.
      }
    }
    if (impact.observing) {
      try {
        await onObservingConditionsChanged?.call();
      } catch (_) {
        // A calculation refresh must not replay a remote mutation.
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

bool _observingConditionsDiffer(
  ObservationSite? before,
  ObservationSite? after,
) {
  if (before == null || after == null) return before != after;
  Object signature(ObservationSite site) => {
    'latitude': site.latitude,
    'longitude': site.longitude,
    'bortle': site.bortle,
    'sqm': site.sqm,
    'brightness_grade': site.brightnessGrade,
    'tracking_mode': site.trackingMode.name,
    'default_equipment_id': site.defaultEquipmentId,
    'default_min_altitude': site.defaultMinAltitude,
    'default_max_altitude': site.defaultMaxAltitude,
    'preferred_start': site.preferredStart,
    'preferred_end': site.preferredEnd,
    'deleted': site.deletedAt != null,
    'horizon': site.horizonPoints.map((item) => item.toMap()).toList(),
    'blocked': site.blockedAzimuthRanges.map((item) => item.toMap()).toList(),
  };
  return jsonEncode(signature(before)) != jsonEncode(signature(after));
}

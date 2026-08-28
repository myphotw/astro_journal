import 'dart:async';
import 'dart:convert';

import '../data/models/backend_upload_result.dart';
import '../data/models/sync_outbox_item.dart';
import '../data/repositories/gallery_repository.dart';
import '../data/repositories/shooting_record_repository.dart';
import '../data/repositories/sync_outbox_repository.dart';
import 'tc_backend_record_service.dart';
import 'tc_backend_settings_service.dart';
import 'tc_backend_sync_gate.dart';
import 'tc_backend_upload_service.dart';

abstract class TcBackendDrainRunner {
  Future<void> drain();
}

typedef TcBackendDrainScheduler =
    void Function(Duration delay, Future<void> Function() callback);

void scheduleTcBackendDrainWithTimer(
  Duration delay,
  Future<void> Function() callback,
) {
  Timer(delay, () => unawaited(callback()));
}

class TcBackendSyncCoordinator implements TcBackendDrainRunner {
  TcBackendSyncCoordinator(
    this._outbox,
    this._records,
    this._settings,
    this._upload, {
    DateTime Function()? now,
    this.recordService,
    this.galleryRepository,
    this.catalogCaptureReconciler,
    TcBackendSyncGate? syncGate,
    this.scheduleDrain,
    this.waitingRecheckDelay = const Duration(seconds: 15),
    this.processingRecheckDelay = const Duration(seconds: 5),
  }) : _now = now ?? DateTime.now,
       _syncGate = syncGate ?? TcBackendSyncGate();

  final SyncOutboxRepository _outbox;
  final ShootingRecordRepository _records;
  final TcBackendSettingsService _settings;
  final TcBackendUploadStages _upload;
  final DateTime Function() _now;
  final TcBackendRecordMutations? recordService;
  final GalleryRepository? galleryRepository;
  final Future<void> Function(String catalogObjectId)? catalogCaptureReconciler;
  final TcBackendSyncGate _syncGate;
  final TcBackendDrainScheduler? scheduleDrain;
  final Duration waitingRecheckDelay;
  final Duration processingRecheckDelay;
  bool _draining = false;
  DateTime? _scheduledDrainAt;
  int _scheduleGeneration = 0;

  @override
  Future<void> drain() async {
    if (_draining) return;
    _draining = true;
    try {
      await _syncGate.runExclusive(_drainExclusive);
    } finally {
      _draining = false;
    }
  }

  Future<void> _drainExclusive() async {
    final settings = await _settings.load();
    if (!settings.enabled || !settings.isConfigured) return;
    for (final item in await _outbox.listPending()) {
      if (_canProcess(item)) {
        await _process(item);
      } else {
        final retryAt = item.nextRetryAt;
        if (retryAt != null) _scheduleAt(retryAt);
      }
    }
  }

  Future<void> retryFailed() async {
    await _outbox.retryAllFailed();
    await drain();
  }

  Future<void> retryFailedItem(String operationId) async {
    final photoOutbox = _photoOutbox();
    final item = await photoOutbox.retryFailedItem(operationId);
    await _processSingle(item);
  }

  Future<void> refreshPhoto(String localRecordId) async {
    final item = await _photoOutbox().findPhotoUpload(localRecordId);
    await _processSingle(item, force: true);
  }

  PhotoSyncOutboxRepository _photoOutbox() {
    if (_outbox is! PhotoSyncOutboxRepository) {
      throw StateError('Per-photo synchronization is unavailable.');
    }
    return _outbox as PhotoSyncOutboxRepository;
  }

  Future<void> _processSingle(
    SyncOutboxItem? item, {
    bool force = false,
  }) async {
    if (item == null || _draining) return;
    _draining = true;
    try {
      final settings = await _settings.load();
      if (!settings.enabled || !settings.isConfigured) return;
      await _syncGate.runExclusive(() async {
        if (force || _canProcess(item)) await _process(item);
      });
    } finally {
      _draining = false;
    }
  }

  bool _canProcess(SyncOutboxItem item) {
    if (item.state == SyncOutboxState.synced) return false;
    final due =
        item.nextRetryAt == null || !item.nextRetryAt!.isAfter(_now().toUtc());
    if (item.state != SyncOutboxState.failed) return due;
    final type = _errorType(item.lastError);
    if (type == BackendUploadErrorType.jobTimeout && item.uploadJobId != null) {
      return true;
    }
    return item.retryCount <= 3 && due && type?.isRetryable == true;
  }

  Future<void> _process(SyncOutboxItem item) async {
    switch (item.operationType) {
      case SyncOperationType.photoUploadAndRecord:
        await _processUpload(item);
      case SyncOperationType.recordPatch:
        await _processRecordPatch(item);
      case SyncOperationType.recordDelete:
        await _processRecordDelete(item);
    }
  }

  Future<void> _processUpload(SyncOutboxItem item) async {
    if (item.backendRecordId != null) {
      await _outbox.markSynced(
        item.operationId,
        backendRecordId: item.backendRecordId,
        backendFileId: item.backendFileId,
        uploadJobId: item.uploadJobId,
      );
      await _reconcileCatalogCaptureFromItem(item);
      return;
    }
    var jobId = item.uploadJobId;
    var fileId = item.backendFileId;
    var commonFileId = _commonFileId(item.payload);
    final durablePayload = <String, Object?>{...item.payload};
    try {
      final localRecordId = item.localRecordId;
      final clientFileId = item.clientFileId;
      final clientRecordId = item.clientRecordId;
      if (localRecordId == null ||
          clientFileId == null ||
          clientRecordId == null) {
        throw const TcBackendUploadException(
          BackendUploadErrorType.malformedResponse,
          'Upload outbox identifiers are incomplete.',
        );
      }
      final record = await _records.getById(localRecordId);
      if (record == null) {
        throw const TcBackendUploadException(
          BackendUploadErrorType.http400,
          'Local ShootingRecord is unavailable.',
        );
      }
      if (fileId == null && jobId == null) {
        await _outbox.updateState(item.operationId, SyncOutboxState.uploading);
        final started = await _upload.startUpload(
          record,
          clientFileId: clientFileId,
          metadata: TcBackendUploadMetadata.fromPayload(item.payload),
        );
        jobId = started.uploadJobId;
        fileId = started.backendFileId;
        commonFileId = started.commonFileId;
        if (commonFileId != null) {
          durablePayload['common_file_id'] = commonFileId;
        }
        await _outbox.patch(item.operationId, {
          'upload_job_id': jobId,
          'backend_file_id': fileId,
          if (commonFileId != null) 'payload_json': jsonEncode(durablePayload),
        });
      }

      if (fileId == null || commonFileId == null) {
        if (jobId == null) {
          throw const TcBackendUploadException(
            BackendUploadErrorType.malformedResponse,
            'Upload state has no job ID for common_file_id recovery.',
          );
        }
        final job = await _upload.getUploadJobStatus(jobId);
        switch (job.status) {
          case TcBackendUploadJobStatus.waiting:
            await _deferUploadStatus(
              item.operationId,
              SyncOutboxState.queued,
              waitingRecheckDelay,
            );
            return;
          case TcBackendUploadJobStatus.processing:
            await _deferUploadStatus(
              item.operationId,
              SyncOutboxState.processing,
              processingRecheckDelay,
            );
            return;
          case TcBackendUploadJobStatus.failed:
            throw TcBackendUploadException(
              BackendUploadErrorType.jobFailed,
              job.errorMessage ?? 'Upload job failed.',
            );
          case TcBackendUploadJobStatus.completed:
            break;
        }
        fileId ??= job.backendFileId;
        commonFileId ??= job.commonFileId;
        if (commonFileId == null) {
          throw const TcBackendUploadException(
            BackendUploadErrorType.malformedResponse,
            'Completed upload has no valid common_file_id.',
          );
        }
        durablePayload['common_file_id'] = commonFileId;
        await _outbox.patch(item.operationId, {
          'backend_file_id': fileId,
          'payload_json': jsonEncode(durablePayload),
        });
      }

      await _outbox.updateState(
        item.operationId,
        SyncOutboxState.recordCreating,
      );
      final created = await _upload.createObservationRecord(
        record,
        commonFileId,
        clientRecordId: clientRecordId,
      );
      await _outbox.patch(item.operationId, {
        'backend_record_id': created.backendRecordId,
        'payload_json': jsonEncode(<String, Object?>{
          ...durablePayload,
          if (created.revision != null) 'revision': created.revision,
        }),
      });
      await _outbox.markSynced(
        item.operationId,
        backendFileId: fileId,
        backendRecordId: created.backendRecordId,
        uploadJobId: jobId,
      );
      await _reconcileCatalogCapture(record.celestialObjectId);
    } on TcBackendUploadException catch (error) {
      await _fail(item, error);
    }
  }

  Future<void> _reconcileCatalogCapture(String catalogObjectId) async {
    try {
      await catalogCaptureReconciler?.call(catalogObjectId);
    } catch (_) {
      // Upload durability is authoritative here. Startup reconciliation repairs
      // the derived Catalog projection without replaying the upload.
    }
  }

  Future<void> _deferUploadStatus(
    String operationId,
    SyncOutboxState state,
    Duration delay,
  ) async {
    final retryAt = _now().toUtc().add(delay);
    await _outbox.updateState(operationId, state, nextRetryAt: retryAt);
    _scheduleAt(retryAt);
  }

  void _scheduleAt(DateTime retryAt) {
    final scheduler = scheduleDrain;
    if (scheduler == null) return;
    final utcRetryAt = retryAt.toUtc();
    final current = _scheduledDrainAt;
    if (current != null && !current.isAfter(utcRetryAt)) return;
    _scheduledDrainAt = utcRetryAt;
    final generation = ++_scheduleGeneration;
    final delay = utcRetryAt.difference(_now().toUtc());
    scheduler(delay.isNegative ? Duration.zero : delay, () async {
      if (generation != _scheduleGeneration) return;
      _scheduledDrainAt = null;
      if (_draining) {
        _scheduleAt(_now().toUtc().add(const Duration(seconds: 1)));
        return;
      }
      await drain();
    });
  }

  Future<void> _reconcileCatalogCaptureFromItem(SyncOutboxItem item) async {
    try {
      final localRecordId = item.localRecordId;
      if (localRecordId == null) return;
      final record = await _records.getById(localRecordId);
      if (record != null) {
        await _reconcileCatalogCapture(record.celestialObjectId);
      }
    } catch (_) {
      // The item is already durable and SYNCED. Startup rebuild is the retry.
    }
  }

  int? _commonFileId(Map<String, dynamic> payload) {
    final value = payload['common_file_id'];
    return value is int ? value : null;
  }

  Future<void> _processRecordPatch(SyncOutboxItem item) async {
    final service = recordService;
    try {
      if (service == null) {
        throw const TcBackendRecordException(
          BackendUploadErrorType.incompatible,
          'ObservationRecord mutation service is unavailable.',
        );
      }
      final recordId = item.backendRecordId;
      final revisionValue = item.payload['revision'];
      if (recordId == null || revisionValue is! num) {
        throw const TcBackendRecordException(
          BackendUploadErrorType.malformedResponse,
          'PATCH outbox payload is missing record ID or revision.',
        );
      }
      final fields = <String, Object?>{...item.payload}
        ..remove('revision')
        ..remove('current_revision');
      if (fields.isEmpty) {
        throw const TcBackendRecordException(
          BackendUploadErrorType.malformedResponse,
          'PATCH outbox payload contains no changed fields.',
        );
      }
      await _outbox.updateState(item.operationId, SyncOutboxState.processing);
      final result = await service.patchRecord(
        recordId,
        revisionValue.toInt(),
        fields,
      );
      final canonical = <String, Object?>{...fields, ...result.canonicalFields};
      await galleryRepository?.applyLocalPatch(
        recordId,
        canonical,
        revision: result.revision,
      );
      await _outbox.patch(item.operationId, {
        'payload_json': jsonEncode(<String, Object?>{
          'revision': result.revision,
          ...canonical,
        }),
      });
      await _outbox.rebaseQueuedRecordPatches(recordId, result.revision);
      await _outbox.markSynced(item.operationId, backendRecordId: recordId);
    } on TcBackendRecordException catch (error) {
      if (error.currentRevision != null) {
        await _outbox.patch(item.operationId, {
          'payload_json': jsonEncode(<String, Object?>{
            ...item.payload,
            'current_revision': error.currentRevision,
          }),
        });
      }
      await _failType(
        item,
        error.type,
        error.message,
        currentRevision: error.currentRevision,
      );
    }
  }

  Future<void> _processRecordDelete(SyncOutboxItem item) async {
    final service = recordService;
    try {
      if (service == null) {
        throw const TcBackendRecordException(
          BackendUploadErrorType.incompatible,
          'ObservationRecord mutation service is unavailable.',
        );
      }
      final recordId = item.backendRecordId;
      if (recordId == null) {
        throw const TcBackendRecordException(
          BackendUploadErrorType.malformedResponse,
          'DELETE outbox payload is missing record ID.',
        );
      }
      await _outbox.updateState(item.operationId, SyncOutboxState.processing);
      await service.deleteRecord(recordId);
      await galleryRepository?.applyLocalDelete(recordId);
      await _outbox.markSynced(item.operationId, backendRecordId: recordId);
    } on TcBackendRecordException catch (error) {
      await _failType(item, error.type, error.message);
    }
  }

  Future<void> _fail(
    SyncOutboxItem item,
    TcBackendUploadException error,
  ) async {
    await _failType(item, error.type, error.message);
  }

  Future<void> _failType(
    SyncOutboxItem item,
    BackendUploadErrorType type,
    String message, {
    int? currentRevision,
  }) async {
    final retryCount = item.retryCount + 1;
    final delay = switch (retryCount) {
      1 => const Duration(seconds: 5),
      2 => const Duration(seconds: 15),
      _ => const Duration(seconds: 60),
    };
    final retryable = type.isRetryable && retryCount <= 3;
    final retryAt = retryable ? _now().toUtc().add(delay) : null;
    await _outbox.patch(item.operationId, {'retry_count': retryCount});
    await _outbox.updateState(
      item.operationId,
      retryable ? SyncOutboxState.queued : SyncOutboxState.failed,
      error:
          '${type.name}|$message${currentRevision == null ? '' : '|current_revision=$currentRevision'}',
      nextRetryAt: retryAt,
    );
    if (retryAt != null) _scheduleAt(retryAt);
  }

  BackendUploadErrorType? _errorType(String? stored) {
    if (stored == null) return null;
    final name = stored.split('|').first;
    for (final value in BackendUploadErrorType.values) {
      if (value.name == name) return value;
    }
    return null;
  }
}

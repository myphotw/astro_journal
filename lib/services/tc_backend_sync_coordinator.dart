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

class TcBackendSyncCoordinator implements TcBackendDrainRunner {
  TcBackendSyncCoordinator(
    this._outbox,
    this._records,
    this._settings,
    this._upload, {
    DateTime Function()? now,
    this.recordService,
    this.galleryRepository,
    TcBackendSyncGate? syncGate,
  }) : _now = now ?? DateTime.now,
       _syncGate = syncGate ?? TcBackendSyncGate();

  final SyncOutboxRepository _outbox;
  final ShootingRecordRepository _records;
  final TcBackendSettingsService _settings;
  final TcBackendUploadStages _upload;
  final DateTime Function() _now;
  final TcBackendRecordMutations? recordService;
  final GalleryRepository? galleryRepository;
  final TcBackendSyncGate _syncGate;
  bool _draining = false;

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
      if (_canProcess(item)) await _process(item);
    }
  }

  Future<void> retryFailed() async {
    await _outbox.retryAllFailed();
    await drain();
  }

  bool _canProcess(SyncOutboxItem item) {
    if (item.state == SyncOutboxState.synced) return false;
    if (item.state != SyncOutboxState.failed) return true;
    final type = _errorType(item.lastError);
    final due =
        item.nextRetryAt == null || !item.nextRetryAt!.isAfter(_now().toUtc());
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
      return;
    }
    var jobId = item.uploadJobId;
    var fileId = item.backendFileId;
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
        await _outbox.patch(item.operationId, {
          'upload_job_id': jobId,
          'backend_file_id': fileId,
        });
      }

      if (fileId == null) {
        await _outbox.updateState(item.operationId, SyncOutboxState.processing);
        final job = await _upload.pollUploadJob(jobId!);
        fileId = job.backendFileId;
        await _outbox.patch(item.operationId, {'backend_file_id': fileId});
      }

      await _outbox.updateState(
        item.operationId,
        SyncOutboxState.recordCreating,
      );
      final created = await _upload.createObservationRecord(
        record,
        fileId!,
        clientRecordId: clientRecordId,
      );
      await _outbox.patch(item.operationId, {
        'backend_record_id': created.backendRecordId,
        'payload_json': jsonEncode(<String, Object?>{
          ...item.payload,
          if (created.revision != null) 'revision': created.revision,
        }),
      });
      await _outbox.markSynced(
        item.operationId,
        backendFileId: fileId,
        backendRecordId: created.backendRecordId,
        uploadJobId: jobId,
      );
    } on TcBackendUploadException catch (error) {
      await _fail(item, error);
    }
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
    final retryAt = type.isRetryable && retryCount <= 3
        ? _now().toUtc().add(delay)
        : null;
    await _outbox.patch(item.operationId, {'retry_count': retryCount});
    await _outbox.updateState(
      item.operationId,
      SyncOutboxState.failed,
      error:
          '${type.name}|$message${currentRevision == null ? '' : '|current_revision=$currentRevision'}',
      nextRetryAt: retryAt,
    );
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

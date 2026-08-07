import '../data/models/backend_upload_result.dart';
import '../data/models/sync_outbox_item.dart';
import '../data/repositories/shooting_record_repository.dart';
import '../data/repositories/sync_outbox_repository.dart';
import 'tc_backend_settings_service.dart';
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
  }) : _now = now ?? DateTime.now;

  final SyncOutboxRepository _outbox;
  final ShootingRecordRepository _records;
  final TcBackendSettingsService _settings;
  final TcBackendUploadStages _upload;
  final DateTime Function() _now;
  bool _draining = false;

  @override
  Future<void> drain() async {
    if (_draining) return;
    _draining = true;
    try {
      final settings = await _settings.load();
      if (!settings.enabled || !settings.isConfigured) return;
      for (final item in await _outbox.listPending()) {
        if (_canProcess(item)) await _process(item);
      }
    } finally {
      _draining = false;
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
    if (item.backendRecordId != null) {
      await _outbox.markSynced(
        item.operationId,
        backendRecordId: item.backendRecordId,
        backendFileId: item.backendFileId,
        uploadJobId: item.uploadJobId,
      );
      return;
    }
    final record = await _records.getById(item.localRecordId);
    if (record == null) {
      await _fail(
        item,
        const TcBackendUploadException(
          BackendUploadErrorType.http400,
          'Local ShootingRecord is unavailable.',
        ),
      );
      return;
    }

    var jobId = item.uploadJobId;
    var fileId = item.backendFileId;
    try {
      if (fileId == null && jobId == null) {
        await _outbox.updateState(item.operationId, SyncOutboxState.uploading);
        final started = await _upload.startUpload(
          record,
          clientFileId: item.clientFileId,
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
      final created = await _upload.createObservationRecord(record, fileId!);
      await _outbox.patch(item.operationId, {
        'backend_record_id': created.backendRecordId,
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

  Future<void> _fail(
    SyncOutboxItem item,
    TcBackendUploadException error,
  ) async {
    final retryCount = item.retryCount + 1;
    final delay = switch (retryCount) {
      1 => const Duration(seconds: 5),
      2 => const Duration(seconds: 15),
      _ => const Duration(seconds: 60),
    };
    final retryAt = error.type.isRetryable && retryCount <= 3
        ? _now().toUtc().add(delay)
        : null;
    await _outbox.patch(item.operationId, {'retry_count': retryCount});
    await _outbox.updateState(
      item.operationId,
      SyncOutboxState.failed,
      error: '${error.type.name}|${error.message}',
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

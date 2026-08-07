import 'dart:convert';

enum SyncOutboxState {
  queued,
  uploading,
  processing,
  recordCreating,
  synced,
  failed,
}

enum SyncOperationType { photoUploadAndRecord }

class SyncOutboxItem {
  const SyncOutboxItem({
    required this.operationId,
    required this.localRecordId,
    required this.clientFileId,
    required this.clientRecordId,
    required this.payload,
    this.id,
    this.state = SyncOutboxState.queued,
    this.retryCount = 0,
    this.nextRetryAt,
    this.lastError,
    this.backendFileId,
    this.backendRecordId,
    this.uploadJobId,
  });
  final int? id;
  final String operationId;
  final String localRecordId;
  final String clientFileId;
  final String clientRecordId;
  final Map<String, dynamic> payload;
  final SyncOutboxState state;
  final int retryCount;
  final DateTime? nextRetryAt;
  final String? lastError;
  final String? backendFileId;
  final String? backendRecordId;
  final String? uploadJobId;
  Map<String, dynamic> toMap() {
    final now = DateTime.now().toUtc().toIso8601String();
    return {
      'operation_id': operationId,
      'operation_type': 'PHOTO_UPLOAD_AND_RECORD',
      'local_record_id': localRecordId,
      'client_file_id': clientFileId,
      'client_record_id': clientRecordId,
      'backend_file_id': backendFileId,
      'backend_record_id': backendRecordId,
      'upload_job_id': uploadJobId,
      'state': state.name.toUpperCase(),
      'retry_count': retryCount,
      'next_retry_at': nextRetryAt?.toUtc().toIso8601String(),
      'last_error': lastError,
      'created_at': now,
      'updated_at': now,
      'payload_json': jsonEncode(payload),
    };
  }

  factory SyncOutboxItem.fromMap(Map<String, dynamic> map) => SyncOutboxItem(
    id: map['id'] as int?,
    operationId: map['operation_id'] as String,
    localRecordId: map['local_record_id'] as String,
    clientFileId: map['client_file_id'] as String,
    clientRecordId: map['client_record_id'] as String,
    payload:
        jsonDecode(map['payload_json'] as String? ?? '{}')
            as Map<String, dynamic>,
    state: SyncOutboxState.values.firstWhere(
      (v) => v.name.toUpperCase() == map['state'],
      orElse: () => SyncOutboxState.queued,
    ),
    retryCount: map['retry_count'] as int? ?? 0,
    nextRetryAt: map['next_retry_at'] == null
        ? null
        : DateTime.parse(map['next_retry_at'] as String),
    lastError: map['last_error'] as String?,
    backendFileId: map['backend_file_id'] as String?,
    backendRecordId: map['backend_record_id'] as String?,
    uploadJobId: map['upload_job_id'] as String?,
  );
}

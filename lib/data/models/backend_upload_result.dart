class BackendUploadResult {
  const BackendUploadResult({
    required this.attempted,
    required this.success,
    this.clientFileId,
    this.contentSha256,
    this.uploadJobId,
    this.backendFileId,
    this.commonFileId,
    this.backendRecordId,
    this.recordRevision,
    this.errorType,
    this.errorMessage,
  });

  const BackendUploadResult.notAttempted()
    : attempted = false,
      success = false,
      clientFileId = null,
      contentSha256 = null,
      uploadJobId = null,
      backendFileId = null,
      commonFileId = null,
      backendRecordId = null,
      recordRevision = null,
      errorType = null,
      errorMessage = null;

  final bool attempted;
  final bool success;
  final String? clientFileId;
  final String? contentSha256;
  final String? uploadJobId;
  final String? backendFileId;
  final int? commonFileId;
  final String? backendRecordId;
  final int? recordRevision;
  final BackendUploadErrorType? errorType;
  final String? errorMessage;
}

enum BackendUploadErrorType {
  notConfigured,
  unreachable,
  uploadRejected,
  idempotencyConflict,
  jobFailed,
  jobTimeout,
  recordCreateFailed,
  malformedResponse,
  http400,
  http409,
  http422,
  http5xx,
  timeout,
  incompatible,
  network,
  unauthorized,
}

extension BackendUploadErrorRetryPolicy on BackendUploadErrorType {
  bool get isRetryable => switch (this) {
    BackendUploadErrorType.network ||
    BackendUploadErrorType.timeout ||
    BackendUploadErrorType.http5xx ||
    BackendUploadErrorType.jobFailed => true,
    _ => false,
  };
}

class UploadStartResult {
  const UploadStartResult({
    required this.uploadJobId,
    this.backendFileId,
    this.commonFileId,
    this.idempotentReplay = false,
  });

  final String uploadJobId;
  final String? backendFileId;
  final int? commonFileId;
  final bool idempotentReplay;
}

enum TcBackendUploadJobStatus { waiting, processing, completed, failed }

class UploadJobResult {
  const UploadJobResult({
    required this.uploadJobId,
    required this.status,
    this.backendFileId,
    this.commonFileId,
    this.errorMessage,
  });

  final String uploadJobId;
  final TcBackendUploadJobStatus status;
  final String? backendFileId;
  final int? commonFileId;
  final String? errorMessage;
}

class ObservationRecordResult {
  const ObservationRecordResult({required this.backendRecordId, this.revision});
  final String backendRecordId;
  final int? revision;
}

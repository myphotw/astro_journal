class BackendUploadResult {
  const BackendUploadResult({
    required this.attempted,
    required this.success,
    this.clientFileId,
    this.contentSha256,
    this.uploadJobId,
    this.backendFileId,
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
}

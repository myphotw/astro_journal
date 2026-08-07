import '../models/sync_outbox_item.dart';

abstract class SyncOutboxRepository {
  Future<void> create(SyncOutboxItem item);
  Future<List<SyncOutboxItem>> listPending();
  Future<int> countQueued();
  Future<int> countProcessing();
  Future<int> countFailed();
  Future<void> updateState(
    String operationId,
    SyncOutboxState state, {
    String? error,
    DateTime? nextRetryAt,
  });
  Future<void> markSynced(
    String operationId, {
    String? backendFileId,
    String? backendRecordId,
    String? uploadJobId,
  });
  Future<void> patch(String operationId, Map<String, Object?> values);
  Future<void> retryAllFailed();
  Future<void> enqueueRecordPatch({
    required String backendRecordId,
    required int expectedRevision,
    required Map<String, Object?> fields,
    String? localRecordId,
  });
  Future<void> enqueueRecordDelete({
    required String backendRecordId,
    String? localRecordId,
  });
  Future<void> cancelPendingUpload(String localRecordId);
  Future<void> rebaseQueuedRecordPatches(String backendRecordId, int revision);
}

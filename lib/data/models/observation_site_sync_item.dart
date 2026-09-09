import 'dart:convert';

enum ObservationSiteSyncOperation { create, update, delete }

extension ObservationSiteSyncOperationStorage on ObservationSiteSyncOperation {
  String get databaseValue => name.toUpperCase();

  static ObservationSiteSyncOperation fromDatabase(Object? value) =>
      ObservationSiteSyncOperation.values.firstWhere(
        (operation) => operation.databaseValue == value,
      );
}

enum ObservationSiteSyncState {
  queued,
  processing,
  failed,
  conflict,
  synced,
  cancelled,
}

class ObservationSiteSyncItem {
  const ObservationSiteSyncItem({
    required this.operationId,
    required this.siteId,
    required this.operation,
    required this.payload,
    required this.state,
    required this.retryCount,
    this.baseRevision,
    this.nextRetryAt,
    this.lastError,
    this.serverPayload,
  });

  final String operationId;
  final String siteId;
  final ObservationSiteSyncOperation operation;
  final int? baseRevision;
  final Map<String, dynamic> payload;
  final ObservationSiteSyncState state;
  final int retryCount;
  final DateTime? nextRetryAt;
  final String? lastError;
  final Map<String, dynamic>? serverPayload;

  factory ObservationSiteSyncItem.fromMap(Map<String, Object?> map) {
    final payload = jsonDecode(map['payload_json'] as String);
    final serverPayload = map['server_payload_json'] == null
        ? null
        : jsonDecode(map['server_payload_json'] as String);
    if (payload is! Map || (serverPayload != null && serverPayload is! Map)) {
      throw const FormatException('ObservationSite outbox payload is invalid.');
    }
    return ObservationSiteSyncItem(
      operationId: map['operation_id'] as String,
      siteId: map['site_id'] as String,
      operation: ObservationSiteSyncOperationStorage.fromDatabase(
        map['operation_type'],
      ),
      baseRevision: (map['base_revision'] as num?)?.toInt(),
      payload: Map<String, dynamic>.from(payload),
      state: ObservationSiteSyncState.values.firstWhere(
        (state) => state.name.toUpperCase() == map['state'],
      ),
      retryCount: (map['retry_count'] as num?)?.toInt() ?? 0,
      nextRetryAt: _date(map['next_retry_at']),
      lastError: map['last_error'] as String?,
      serverPayload: serverPayload == null
          ? null
          : Map<String, dynamic>.from(serverPayload),
    );
  }

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;
}

class ObservationSiteSyncMetadata {
  const ObservationSiteSyncMetadata({
    required this.siteId,
    this.serverRevision,
    this.serverUpdatedAt,
    this.serverDeletedAt,
    this.lastSyncedAt,
    this.serverPayload,
  });

  final String siteId;
  final int? serverRevision;
  final DateTime? serverUpdatedAt;
  final DateTime? serverDeletedAt;
  final DateTime? lastSyncedAt;
  final Map<String, dynamic>? serverPayload;

  factory ObservationSiteSyncMetadata.fromMap(Map<String, Object?> map) {
    final rawPayload = map['server_payload_json'];
    final decoded = rawPayload is String ? jsonDecode(rawPayload) : null;
    return ObservationSiteSyncMetadata(
      siteId: map['site_id'] as String,
      serverRevision: (map['server_revision'] as num?)?.toInt(),
      serverUpdatedAt: _date(map['server_updated_at']),
      serverDeletedAt: _date(map['server_deleted_at']),
      lastSyncedAt: _date(map['last_synced_at']),
      serverPayload: decoded is Map ? Map<String, dynamic>.from(decoded) : null,
    );
  }

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;
}

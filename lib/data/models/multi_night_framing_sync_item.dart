import 'dart:convert';

enum MultiNightFramingSyncOperation { create, update, delete }

extension MultiNightFramingSyncOperationStorage
    on MultiNightFramingSyncOperation {
  String get databaseValue => name.toUpperCase();

  static MultiNightFramingSyncOperation fromDatabase(Object? value) =>
      MultiNightFramingSyncOperation.values.firstWhere(
        (operation) => operation.databaseValue == value,
      );
}

enum MultiNightFramingSyncState {
  queued,
  processing,
  failed,
  conflict,
  synced,
  cancelled,
}

class MultiNightFramingSyncItem {
  const MultiNightFramingSyncItem({
    required this.operationId,
    required this.referenceId,
    required this.operation,
    required this.payload,
    required this.state,
    required this.retryCount,
    this.baseRevision,
    this.nextRetryAt,
    this.lastError,
    this.conflictSnapshot,
  });

  final String operationId;
  final String referenceId;
  final MultiNightFramingSyncOperation operation;
  final int? baseRevision;
  final Map<String, dynamic> payload;
  final MultiNightFramingSyncState state;
  final int retryCount;
  final DateTime? nextRetryAt;
  final String? lastError;
  final Map<String, dynamic>? conflictSnapshot;

  factory MultiNightFramingSyncItem.fromMap(Map<String, Object?> map) {
    final payload = jsonDecode(map['payload_json']! as String);
    final conflict = map['conflict_snapshot_json'] == null
        ? null
        : jsonDecode(map['conflict_snapshot_json']! as String);
    if (payload is! Map || (conflict != null && conflict is! Map)) {
      throw const FormatException('Reference outbox payload is invalid.');
    }
    return MultiNightFramingSyncItem(
      operationId: map['operation_id']! as String,
      referenceId: map['reference_id']! as String,
      operation: MultiNightFramingSyncOperationStorage.fromDatabase(
        map['operation_type'],
      ),
      baseRevision: (map['base_revision'] as num?)?.toInt(),
      payload: Map<String, dynamic>.from(payload),
      state: MultiNightFramingSyncState.values.firstWhere(
        (state) => state.name.toUpperCase() == map['state'],
      ),
      retryCount: (map['retry_count'] as num?)?.toInt() ?? 0,
      nextRetryAt: _date(map['next_retry_at']),
      lastError: map['last_error'] as String?,
      conflictSnapshot: conflict == null
          ? null
          : Map<String, dynamic>.from(conflict),
    );
  }

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;
}

class MultiNightFramingSyncMetadata {
  const MultiNightFramingSyncMetadata({
    required this.referenceId,
    this.serverRevision,
    this.serverUpdatedAt,
    this.serverDeletedAt,
    this.canonicalSnapshot,
  });

  final String referenceId;
  final int? serverRevision;
  final DateTime? serverUpdatedAt;
  final DateTime? serverDeletedAt;
  final Map<String, dynamic>? canonicalSnapshot;

  factory MultiNightFramingSyncMetadata.fromMap(Map<String, Object?> map) {
    final raw = map['canonical_snapshot_json'];
    final decoded = raw is String ? jsonDecode(raw) : null;
    return MultiNightFramingSyncMetadata(
      referenceId: map['reference_id']! as String,
      serverRevision: (map['server_revision'] as num?)?.toInt(),
      serverUpdatedAt: _date(map['server_updated_at']),
      serverDeletedAt: _date(map['server_deleted_at']),
      canonicalSnapshot: decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : null,
    );
  }

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;
}

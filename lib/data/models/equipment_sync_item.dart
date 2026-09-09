import 'dart:convert';

enum EquipmentSyncOperation { create, update, delete }

extension EquipmentSyncOperationStorage on EquipmentSyncOperation {
  String get databaseValue => name.toUpperCase();

  static EquipmentSyncOperation fromDatabase(Object? value) =>
      EquipmentSyncOperation.values.firstWhere(
        (operation) => operation.databaseValue == value,
      );
}

enum EquipmentSyncState {
  queued,
  processing,
  failed,
  conflict,
  synced,
  cancelled,
}

class EquipmentSyncItem {
  const EquipmentSyncItem({
    required this.operationId,
    required this.equipmentId,
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
  final String equipmentId;
  final EquipmentSyncOperation operation;
  final int? baseRevision;
  final Map<String, dynamic> payload;
  final EquipmentSyncState state;
  final int retryCount;
  final DateTime? nextRetryAt;
  final String? lastError;
  final Map<String, dynamic>? conflictSnapshot;

  factory EquipmentSyncItem.fromMap(Map<String, Object?> map) {
    final payload = jsonDecode(map['payload_json'] as String);
    final conflict = map['conflict_snapshot_json'] == null
        ? null
        : jsonDecode(map['conflict_snapshot_json'] as String);
    if (payload is! Map || (conflict != null && conflict is! Map)) {
      throw const FormatException('Equipment outbox payload is invalid.');
    }
    return EquipmentSyncItem(
      operationId: map['operation_id'] as String,
      equipmentId: map['equipment_id'] as String,
      operation: EquipmentSyncOperationStorage.fromDatabase(
        map['operation_type'],
      ),
      baseRevision: (map['base_revision'] as num?)?.toInt(),
      payload: Map<String, dynamic>.from(payload),
      state: EquipmentSyncState.values.firstWhere(
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

class EquipmentSyncMetadata {
  const EquipmentSyncMetadata({
    required this.equipmentId,
    this.serverRevision,
    this.serverUpdatedAt,
    this.serverDeletedAt,
    this.lastSyncedAt,
    this.canonicalSnapshot,
  });

  final String equipmentId;
  final int? serverRevision;
  final DateTime? serverUpdatedAt;
  final DateTime? serverDeletedAt;
  final DateTime? lastSyncedAt;
  final Map<String, dynamic>? canonicalSnapshot;

  factory EquipmentSyncMetadata.fromMap(Map<String, Object?> map) {
    final raw = map['canonical_snapshot_json'];
    final decoded = raw is String ? jsonDecode(raw) : null;
    return EquipmentSyncMetadata(
      equipmentId: map['equipment_id'] as String,
      serverRevision: (map['server_revision'] as num?)?.toInt(),
      serverUpdatedAt: _date(map['server_updated_at']),
      serverDeletedAt: _date(map['server_deleted_at']),
      lastSyncedAt: _date(map['last_synced_at']),
      canonicalSnapshot: decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : null,
    );
  }

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;
}

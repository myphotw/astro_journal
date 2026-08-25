enum TcBackendChangeOperation { create, update, delete }

class TcBackendChange {
  const TcBackendChange({
    required this.resourceType,
    required this.resourceId,
    required this.operation,
    this.revision,
    this.deletedAt,
  });

  final String resourceType;
  final String resourceId;
  final TcBackendChangeOperation operation;
  final int? revision;
  final DateTime? deletedAt;

  bool get isObservationRecord {
    final normalized = resourceType
        .replaceAll(RegExp('[^a-zA-Z]'), '')
        .toLowerCase();
    return normalized == 'observationrecord';
  }

  bool get isAstroJournalReset {
    final normalized = resourceType
        .replaceAll(RegExp('[^a-zA-Z]'), '')
        .toLowerCase();
    return normalized == 'astrojournalreset';
  }
}

class TcBackendChangesPage {
  const TcBackendChangesPage({
    required this.changes,
    required this.hasMore,
    this.nextCursor,
  });

  final List<TcBackendChange> changes;
  final String? nextCursor;
  final bool hasMore;
}

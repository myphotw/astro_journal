enum TcBackendChangeOperation { create, update, delete }

enum TcBackendResourceState { active, deleted, missing, unavailable }

class TcBackendChange {
  const TcBackendChange({
    required this.resourceType,
    required this.resourceId,
    required this.operation,
    this.revision,
    this.deletedAt,
    this.currentResourceState,
    this.currentRevision,
    this.cursor,
  });

  final String resourceType;
  final String resourceId;
  final TcBackendChangeOperation operation;
  final int? revision;
  final DateTime? deletedAt;
  final TcBackendResourceState? currentResourceState;
  final int? currentRevision;
  final String? cursor;

  bool get isGalleryVisibility => resourceType == 'AstroGalleryVisibility';

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

  bool get isObservationSite {
    final normalized = resourceType
        .replaceAll(RegExp('[^a-zA-Z]'), '')
        .toLowerCase();
    return normalized == 'observationsite';
  }

  bool get isEquipment {
    final normalized = resourceType
        .replaceAll(RegExp('[^a-zA-Z]'), '')
        .toLowerCase();
    return normalized == 'equipment';
  }

  bool get isMultiNightFramingReference {
    final normalized = resourceType
        .replaceAll(RegExp('[^a-zA-Z]'), '')
        .toLowerCase();
    return normalized == 'multinightframingreference';
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

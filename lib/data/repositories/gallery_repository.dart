import '../models/gallery_item.dart';
import '../models/tc_backend_change.dart';

enum GallerySnapshotSource { remote, cache, none }

class GallerySnapshot {
  const GallerySnapshot({
    required this.items,
    required this.source,
    required this.backendEnabled,
    this.remoteFailed = false,
  });

  final List<GalleryItem> items;
  final GallerySnapshotSource source;
  final bool backendEnabled;
  final bool remoteFailed;
}

abstract class GalleryRepository {
  Future<List<GalleryItem>> getAll({bool forceRefresh = false});
  Future<GallerySnapshot> getSnapshot({bool forceRefresh = false});
  Future<GalleryItem?> getById(
    String backendRecordId, {
    bool forceRefresh = false,
  });
  Future<List<GalleryItem>> search(String query, {bool forceRefresh = false});
  Future<Map<String, dynamic>> getTimeline({bool forceRefresh = false});
  Future<Map<String, dynamic>> getStatistics({bool forceRefresh = false});
  Future<void> applyLocalPatch(
    String backendRecordId,
    Map<String, Object?> fields, {
    int? revision,
  });
  Future<void> applyLocalDelete(String backendRecordId);
  Future<int?> getCachedRevision(String backendRecordId);
  Future<int?> getAuthoritativeDeleteRevision(String backendRecordId);
  Future<bool> upsertPulledItem(GalleryItem item);
  Future<bool> applyPulledDelete(
    String backendRecordId, {
    required int revision,
    DateTime? deletedAt,
  });
}

/// Reads the projection already applied by incremental sync, without a rescan.
abstract interface class CachedGallerySnapshotReader {
  Future<GallerySnapshot> getCachedSnapshot();
}

/// Optional incremental-sync capability. Visibility is not an actual DELETE.
abstract interface class GalleryResourceStateRepository {
  Future<bool> shouldFetchPulledItem(String id, int? revision);
  Future<int?> getHiddenRevision(String id);
  Future<bool> applyPulledHidden(
    String id, {
    required int revision,
    required TcBackendResourceState state,
  });
}

/// Projection ordering is independent of ObservationRecord revision.
abstract interface class GalleryVisibilityRepository {
  Future<bool> shouldApplyVisibilityEvent(String id, String cursor);
  Future<bool> applyVisibilityHidden(
    String id, {
    required int revision,
    required TcBackendResourceState state,
    required String cursor,
  });
  Future<bool> upsertVisibilityItem(GalleryItem item, String cursor);
  Future<List<String>> takeHiddenRechecks({int limit = 5});
}

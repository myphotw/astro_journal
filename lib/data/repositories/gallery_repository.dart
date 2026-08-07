import '../models/gallery_item.dart';

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
  Future<bool> upsertPulledItem(GalleryItem item);
  Future<bool> applyPulledDelete(
    String backendRecordId, {
    required int revision,
    DateTime? deletedAt,
  });
}

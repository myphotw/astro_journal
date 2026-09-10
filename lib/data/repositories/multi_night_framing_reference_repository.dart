import '../models/multi_night_framing_reference.dart';

abstract interface class MultiNightFramingReferenceRepository {
  Future<List<MultiNightFramingReference>> list({
    String? catalogObjectId,
    String? equipmentId,
  });
  Future<MultiNightFramingReference?> get(String id);
  Future<MultiNightFramingReference?> find({
    required String catalogObjectId,
    required String equipmentId,
  });
  Future<void> create(MultiNightFramingReference reference);
  Future<void> update(MultiNightFramingReference reference);
  Future<void> delete(String id);
  Future<String?> latestConflictForCatalog(String catalogObjectId);
}

import '../models/shooting_record.dart';

abstract class ShootingRecordRepository {
  Future<List<ShootingRecord>> getAll();
  Future<List<ShootingRecord>> getByCelestialObjectId(String celestialObjectId);
  Future<ShootingRecord?> getById(String id);
  Future<ShootingRecord?> findByOriginalFilename(String originalFilename);
  Future<ShootingRecord?> findByObjectAndCapturedAt(
    String celestialObjectId,
    DateTime capturedAt, {
    Duration tolerance = const Duration(minutes: 1),
  });
  Future<void> save(ShootingRecord record);
  Future<void> update(ShootingRecord record);
  Future<void> delete(String id);
  Future<void> clearRepresentativeForObject(String celestialObjectId);
  Future<void> setRepresentative(String recordId);
}

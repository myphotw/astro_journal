import '../../services/app_logger.dart';
import '../../services/metadata_field_trace.dart';
import '../datasources/shooting_record_local_datasource.dart';
import '../models/shooting_record.dart';
import 'shooting_record_repository.dart';

class ShootingRecordRepositoryImpl implements ShootingRecordRepository {
  ShootingRecordRepositoryImpl({ShootingRecordLocalDataSource? dataSource})
      : _dataSource = dataSource ?? ShootingRecordLocalDataSource();

  final ShootingRecordLocalDataSource _dataSource;

  @override
  Future<List<ShootingRecord>> getAll() => _dataSource.getAll();

  @override
  Future<List<ShootingRecord>> getByCelestialObjectId(
    String celestialObjectId,
  ) =>
      _dataSource.getByCelestialObjectId(celestialObjectId);

  @override
  Future<ShootingRecord?> getById(String id) => _dataSource.getById(id);

  @override
  Future<ShootingRecord?> findByOriginalFilename(String originalFilename) =>
      _dataSource.findByOriginalFilename(originalFilename);

  @override
  Future<ShootingRecord?> findByObjectAndCapturedAt(
    String celestialObjectId,
    DateTime capturedAt, {
    Duration tolerance = const Duration(minutes: 1),
  }) =>
      _dataSource.findByObjectAndCapturedAt(
        celestialObjectId,
        capturedAt,
        tolerance: tolerance,
      );

  @override
  Future<void> save(ShootingRecord record) async {
    AppLogger.metadata('Repository', 'ShootingRecord save 시작');
    AppLogger.metadata(
      'Repository',
      'target=${record.exif?.targetName ?? "-"}, '
          'date=${record.exif?.date.isNotEmpty == true ? record.exif!.date : "-"}, '
          'equipment=${record.exif?.equipment ?? "-"}, '
          'stack=${record.exif?.stackNum ?? "-"}, '
          'singleExp=${record.exif?.singleExpSec ?? "-"}, '
          'totalExp=${record.exif?.exposure ?? "-"}',
    );
    if (record.exif != null) {
      MetadataFieldTrace.logExifInfo('Repository.Save', record.exif!);
    }
    await _dataSource.insert(record);
    AppLogger.metadata('Repository', 'Repository 저장 완료');
    AppLogger.metadata('Repository', 'SQLite 저장 완료');
  }

  @override
  Future<void> update(ShootingRecord record) => _dataSource.update(record);

  @override
  Future<void> delete(String id) async {
    final record = await _dataSource.getById(id);
    if (record == null) {
      await _dataSource.delete(id);
      return;
    }

    final wasRepresentative = record.isRepresentative;
    final objectId = record.celestialObjectId;

    await _dataSource.delete(id);

    if (wasRepresentative) {
      await _promoteNextRepresentative(objectId);
    }
  }

  Future<void> _promoteNextRepresentative(String celestialObjectId) async {
    final records =
        await _dataSource.getByCelestialObjectId(celestialObjectId);
    for (final candidate in records) {
      if (candidate.photoUri != null && candidate.photoUri!.isNotEmpty) {
        await _dataSource.setRepresentativeFlag(candidate.id, true);
        return;
      }
    }
  }

  @override
  Future<void> clearRepresentativeForObject(String celestialObjectId) =>
      _dataSource.clearRepresentativeForObject(celestialObjectId);

  @override
  Future<void> setRepresentative(String recordId) async {
    final record = await _dataSource.getById(recordId);
    if (record == null) return;

    await _dataSource.clearRepresentativeForObject(record.celestialObjectId);
    await _dataSource.setRepresentativeFlag(recordId, true);
  }
}

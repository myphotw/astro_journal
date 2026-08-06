import '../../services/app_logger.dart';
import '../datasources/photo_local_datasource.dart';
import '../models/photo.dart';
import 'photo_repository.dart';

class PhotoRepositoryImpl implements PhotoRepository {
  PhotoRepositoryImpl({PhotoLocalDataSource? dataSource})
      : _dataSource = dataSource ?? PhotoLocalDataSource();

  final PhotoLocalDataSource _dataSource;

  @override
  Future<List<Photo>> getAll() => _dataSource.getAll();

  @override
  Future<void> save(Photo photo) async {
    AppLogger.metadata('Repository', 'Photo save: ${photo.id}');
    await _dataSource.insert(photo);
    AppLogger.metadata('Repository', 'Repository Success');
  }

  @override
  Future<void> delete(String id) => _dataSource.delete(id);
}

import '../datasources/photo_object_local_datasource.dart';
import '../models/photo_object.dart';
import 'photo_object_repository.dart';

class PhotoObjectRepositoryImpl implements PhotoObjectRepository {
  PhotoObjectRepositoryImpl({PhotoObjectLocalDataSource? dataSource})
      : _dataSource = dataSource ?? PhotoObjectLocalDataSource();

  final PhotoObjectLocalDataSource _dataSource;

  @override
  Future<List<PhotoObject>> getByPhotoId(String photoId) =>
      _dataSource.getByPhotoId(photoId);

  @override
  Future<void> replaceForPhoto(String photoId, List<PhotoObject> objects) =>
      _dataSource.replaceForPhoto(photoId, objects);

  @override
  Future<void> deleteByPhotoId(String photoId) =>
      _dataSource.deleteByPhotoId(photoId);
}

import '../models/photo.dart';

abstract class PhotoRepository {
  Future<List<Photo>> getAll();
  Future<void> save(Photo photo);
  Future<void> delete(String id);
}

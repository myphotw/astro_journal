import '../models/photo_object.dart';

/// 사진(ShootingRecord)과 Plate Solve WCS로 검색된 천체의 관계를 관리한다.
abstract class PhotoObjectRepository {
  Future<List<PhotoObject>> getByPhotoId(String photoId);

  /// [photoId]의 기존 검색 결과를 [objects]로 교체한다 (재검색 시 사용).
  Future<void> replaceForPhoto(String photoId, List<PhotoObject> objects);

  Future<void> deleteByPhotoId(String photoId);
}

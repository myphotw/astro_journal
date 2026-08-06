import '../../data/models/catalog_object.dart';
import 'catalog_type.dart';
import 'object_type.dart';

/// 갤러리 카테고리 필터.
enum GalleryObjectCategory {
  all('전체'),
  nebula('성운'),
  cluster('성단'),
  galaxy('은하'),
  milkyWay('은하수'),
  nebulaAndCluster('성운+성단'),
  solar('태양계'),
  other('기타');

  const GalleryObjectCategory(this.label);

  final String label;

  static const List<GalleryObjectCategory> filterValues = [
    all,
    nebula,
    cluster,
    galaxy,
    milkyWay,
    nebulaAndCluster,
    solar,
    other,
  ];
}

class GalleryCategoryMapper {
  GalleryCategoryMapper._();

  static bool isNebula(CatalogObject obj) => obj.resolvedObjectType.isNebula;

  static bool isCluster(CatalogObject obj) => obj.resolvedObjectType.isCluster;

  static bool isGalaxy(CatalogObject obj) =>
      obj.resolvedObjectType == ObjectType.galaxy &&
      obj.catalog != CatalogType.milky;

  static bool isMilkyWay(CatalogObject obj) => obj.catalog == CatalogType.milky;

  static bool isSolar(CatalogObject obj) => obj.catalog == CatalogType.solar;

  static bool isOther(CatalogObject obj) =>
      !isNebula(obj) &&
      !isCluster(obj) &&
      !isGalaxy(obj) &&
      !isMilkyWay(obj) &&
      !isSolar(obj);

  static bool matches(CatalogObject obj, GalleryObjectCategory filter) {
    switch (filter) {
      case GalleryObjectCategory.all:
        return true;
      case GalleryObjectCategory.nebula:
        return isNebula(obj);
      case GalleryObjectCategory.cluster:
        return isCluster(obj);
      case GalleryObjectCategory.galaxy:
        return isGalaxy(obj);
      case GalleryObjectCategory.milkyWay:
        return isMilkyWay(obj);
      case GalleryObjectCategory.nebulaAndCluster:
        return isNebula(obj) || isCluster(obj);
      case GalleryObjectCategory.solar:
        return isSolar(obj);
      case GalleryObjectCategory.other:
        return isOther(obj);
    }
  }
}

import 'object_type.dart';

/// 카탈로그 목록용 천체 분류 필터 (촬영 여부와 별도).
enum CatalogKindFilter {
  all('전체'),
  galaxy('은하'),
  nebula('성운'),
  cluster('성단'),
  star('별'),
  solar('태양계'),
  milkyWay('은하수'),
  other('기타');

  const CatalogKindFilter(this.label);

  final String label;

  bool matches(ObjectType type) {
    return switch (this) {
      CatalogKindFilter.all => true,
      CatalogKindFilter.galaxy =>
        type == ObjectType.galaxy || type == ObjectType.galaxyGroup,
      CatalogKindFilter.nebula =>
        type.isNebula ||
        type == ObjectType.starCloud ||
        type == ObjectType.nebulaWithCluster,
      CatalogKindFilter.cluster =>
        type.isCluster || type == ObjectType.nebulaWithCluster,
      CatalogKindFilter.star =>
        type == ObjectType.star || type == ObjectType.doubleStar,
      CatalogKindFilter.solar =>
        type == ObjectType.planet ||
        type == ObjectType.moon ||
        type == ObjectType.dwarfPlanet,
      CatalogKindFilter.milkyWay => type == ObjectType.milkyWay,
      CatalogKindFilter.other => type == ObjectType.other,
    };
  }
}

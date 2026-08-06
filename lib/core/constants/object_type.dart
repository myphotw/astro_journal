/// 표준 천체 종류 (카탈로그·갤러리·통계·검색 공통).
enum ObjectType {
  galaxy('은하'),
  galaxyGroup('은하군'),
  emissionNebula('발광성운'),
  reflectionNebula('반사성운'),
  darkNebula('암흑성운'),
  planetaryNebula('행성상성운'),
  openCluster('산개성단'),
  globularCluster('구상성단'),
  supernovaRemnant('초신성잔해'),
  complexNebula('복합성운'),
  nebulaWithCluster('성운+성단'),
  starCloud('별구름'),
  milkyWay('은하수'),
  doubleStar('쌍성'),
  star('항성'),
  planet('행성'),
  moon('위성'),
  dwarfPlanet('왜소행성'),
  other('기타');

  const ObjectType(this.label);

  final String label;

  static ObjectType fromLabel(String label) {
    for (final type in ObjectType.values) {
      if (type.label == label) return type;
    }
    return _inferFromLegacy(label);
  }

  static ObjectType _inferFromLegacy(String legacy) {
    if (legacy.contains('행성상')) return ObjectType.planetaryNebula;
    if (legacy.contains('구상')) return ObjectType.globularCluster;
    if (legacy.contains('산개')) return ObjectType.openCluster;
    if (legacy == '은하군') return ObjectType.galaxyGroup;
    if (legacy == '은하') return ObjectType.galaxy;
    if (legacy == '복합성운') return ObjectType.complexNebula;
    if (legacy == '성운+성단') return ObjectType.nebulaWithCluster;
    if (legacy.contains('초신성')) return ObjectType.supernovaRemnant;
    if (legacy.contains('반사')) return ObjectType.reflectionNebula;
    if (legacy.contains('암흑')) return ObjectType.darkNebula;
    if (legacy == 'HII Region') return ObjectType.emissionNebula;
    if (legacy.contains('은하수')) return ObjectType.milkyWay;
    if (legacy.contains('별구름')) return ObjectType.starCloud;
    if (legacy.contains('쌍성')) return ObjectType.doubleStar;
    if (legacy.contains('성운')) return ObjectType.emissionNebula;
    if (legacy == '항성') return ObjectType.star;
    if (legacy == '왜소행성') return ObjectType.dwarfPlanet;
    if (legacy == '행성') return ObjectType.planet;
    if (legacy == '위성') return ObjectType.moon;
    return ObjectType.other;
  }

  bool get isNebula =>
      this == ObjectType.emissionNebula ||
      this == ObjectType.reflectionNebula ||
      this == ObjectType.darkNebula ||
      this == ObjectType.planetaryNebula ||
      this == ObjectType.supernovaRemnant ||
      this == ObjectType.complexNebula ||
      this == ObjectType.nebulaWithCluster;

  bool get isCluster =>
      this == ObjectType.openCluster || this == ObjectType.globularCluster;
}

import '../core/constants/object_type.dart';

/// Catalog metadata → 세분 [ObjectType] 분류기.
///
/// UI 7카테고리(은하/성운/성단/별/태양계/은하수/기타)는
/// [CatalogKindFilter]가 세분 타입을 매핑한다.
///
/// 이미 올바른 세분 타입이 있으면 유지하고,
/// `기타`·빈 값·명시적 보정 대상만 재분류한다.
class ObjectTypeClassifier {
  const ObjectTypeClassifier();

  /// 분류 가능한 경우 세분 타입을 반환하고, 판단이 어려우면 [ObjectType.other].
  ObjectType classify({
    required String id,
    String? catalog,
    String? name,
    String? commonName,
    String? objectType,
    String? type,
    String? description,
    Iterable<String> aliases = const [],
  }) {
    final existingLabel =
        (objectType?.trim().isNotEmpty == true ? objectType! : type)?.trim() ??
            '';
    final existing = ObjectType.fromLabel(existingLabel);

    final override = _overrideByIdOrName(
      id,
      _blob([id, name, commonName, ...aliases]),
    );
    if (override != null) return override;

    // 이미 세분 타입이 있으면 유지 (설명 키워드로 덮어쓰지 않음)
    if (existing != ObjectType.other && existing != ObjectType.darkNebula) {
      return existing;
    }

    final catalogValue = (catalog ?? '').trim().toLowerCase();
    final fromCatalog = _fromCatalog(
      catalogValue,
      _blob([id, name, commonName, ...aliases]),
    );
    if (fromCatalog != null) return fromCatalog;

    final titleBlob = _blob([id, name, commonName, ...aliases, type, objectType]);
    final fromTitle = _fromKeywords(titleBlob);
    if (fromTitle != null) return fromTitle;

    // 제목에서 못 찾으면 description까지 확대 (기타만)
    final fullBlob = _blob([
      id,
      name,
      commonName,
      objectType,
      type,
      description,
      ...aliases,
    ]);
    final fromFull = _fromKeywords(fullBlob);
    if (fromFull != null) return fromFull;

    return ObjectType.other;
  }

  /// 암흑성운 제거 대상. catalog 또는 object_type 기준 (설명 오탐 방지).
  bool isDarkNebulaTarget({
    String? catalog,
    String? objectType,
    String? type,
    String? name,
    String? commonName,
    String? description,
    Iterable<String> aliases = const [],
  }) {
    final catalogValue = (catalog ?? '').trim().toLowerCase();
    if (catalogValue == 'barnard' ||
        catalogValue == 'ldn' ||
        catalogValue == 'lbn') {
      return true;
    }

    final typeBlob = _blob([objectType, type]);
    return typeBlob.contains('암흑성운') ||
        typeBlob.contains('dark nebula') ||
        typeBlob.contains('molecular cloud') ||
        typeBlob.contains('dust cloud');
  }

  ObjectType? _overrideByIdOrName(String id, String blob) {
    final normalizedId = id.trim().toUpperCase().replaceAll(' ', '');

    if (normalizedId == 'NGC2359' ||
        normalizedId == 'SH2-298' ||
        blob.contains('토르의 헬멧') ||
        blob.contains("thor's helmet") ||
        blob.contains('thors helmet')) {
      return ObjectType.emissionNebula;
    }

    // ID-first: Sh2-273(성운) vs NGC2264(성단) share similar aliases.
    if (normalizedId == 'SH2-273') {
      return ObjectType.emissionNebula;
    }
    if (normalizedId == 'NGC2264') {
      return ObjectType.openCluster;
    }
    if (blob.contains('크리스마스 트리 성운') ||
        blob.contains('christmas tree nebula')) {
      return ObjectType.emissionNebula;
    }
    if (blob.contains('크리스마스 트리 성단') ||
        blob.contains('christmas tree cluster') ||
        blob.contains('cone nebula cluster')) {
      return ObjectType.openCluster;
    }

    if (normalizedId == 'SH2-171' ||
        blob.contains('북쪽 삼각형') ||
        blob.contains('northern triangle')) {
      return ObjectType.emissionNebula;
    }

    const emissionNgcs = {
      'NGC7380',
      'NGC7538',
      'NGC7822',
      'NGC2467',
    };
    if (emissionNgcs.contains(normalizedId)) {
      return ObjectType.emissionNebula;
    }

    if (normalizedId == 'MW' || normalizedId == 'MILKY') {
      return ObjectType.milkyWay;
    }

    return null;
  }

  ObjectType? _fromCatalog(String catalog, String blob) {
    switch (catalog) {
      case 'rcw':
      case 'sh2':
        return ObjectType.emissionNebula;
      case 'vdb':
        return ObjectType.reflectionNebula;
      case 'milky':
        return ObjectType.milkyWay;
      case 'solar':
        return _solarFromBlob(blob);
      case 'star':
      case 'stars':
        if (blob.contains('쌍성') || blob.contains('double star')) {
          return ObjectType.doubleStar;
        }
        return ObjectType.star;
      case 'barnard':
      case 'ldn':
      case 'lbn':
        return ObjectType.darkNebula;
      default:
        return null;
    }
  }

  ObjectType _solarFromBlob(String blob) {
    if (blob.contains('왜소') ||
        blob.contains('dwarf') ||
        blob.contains('명왕') ||
        blob.contains('pluto') ||
        blob.contains('세레스') ||
        blob.contains('ceres') ||
        blob.contains('소행성') ||
        blob.contains('asteroid')) {
      return ObjectType.dwarfPlanet;
    }
    if (blob.contains('위성') ||
        blob.contains('moon') ||
        blob.contains('달') ||
        blob.contains('타이탄') ||
        blob.contains('이오') ||
        blob.contains('유로파') ||
        blob.contains('가니메데') ||
        blob.contains('칼리스토')) {
      return ObjectType.moon;
    }
    if (blob.contains('태양') || blob.contains('sun')) {
      return ObjectType.star;
    }
    return ObjectType.planet;
  }

  ObjectType? _fromKeywords(String blob) {
    if (blob.contains('은하수') || blob.contains('milky way')) {
      return ObjectType.milkyWay;
    }
    if (blob.contains('은하군') || blob.contains('galaxy group')) {
      return ObjectType.galaxyGroup;
    }
    if ((blob.contains('galaxy') || blob.contains('은하')) &&
        !blob.contains('은하수')) {
      return ObjectType.galaxy;
    }

    if (blob.contains('초신성') || blob.contains('supernova remnant')) {
      return ObjectType.supernovaRemnant;
    }
    if (blob.contains('행성상') || blob.contains('planetary nebula')) {
      return ObjectType.planetaryNebula;
    }
    if (blob.contains('반사성운') || blob.contains('reflection nebula')) {
      return ObjectType.reflectionNebula;
    }
    if (blob.contains('암흑성운') || blob.contains('dark nebula')) {
      return ObjectType.darkNebula;
    }
    if (blob.contains('복합성운')) {
      return ObjectType.complexNebula;
    }
    if (blob.contains('성운+성단')) {
      return ObjectType.nebulaWithCluster;
    }
    if (blob.contains('발광성운') ||
        blob.contains('emission nebula') ||
        blob.contains('hii region')) {
      return ObjectType.emissionNebula;
    }
    if (blob.contains('성운') || blob.contains('nebula')) {
      return ObjectType.emissionNebula;
    }

    if (blob.contains('구상성단') || blob.contains('globular')) {
      return ObjectType.globularCluster;
    }
    if (blob.contains('산개성단') ||
        blob.contains('open cluster') ||
        blob.contains('성단') ||
        blob.contains('cluster')) {
      return ObjectType.openCluster;
    }

    if (blob.contains('별구름') || blob.contains('star cloud')) {
      return ObjectType.starCloud;
    }
    if (blob.contains('쌍성') || blob.contains('double star')) {
      return ObjectType.doubleStar;
    }
    if (blob.contains('항성') || blob.contains('bright star')) {
      return ObjectType.star;
    }

    if (blob.contains('왜소행성') || blob.contains('dwarf planet')) {
      return ObjectType.dwarfPlanet;
    }
    if (blob.contains('위성')) {
      return ObjectType.moon;
    }
    if (blob.contains('행성') ||
        blob.contains('planet') ||
        blob.contains('소행성') ||
        blob.contains('asteroid') ||
        blob.contains('혜성') ||
        blob.contains('comet')) {
      return ObjectType.planet;
    }

    return null;
  }

  String _blob(Iterable<String?> parts) {
    return parts
        .whereType<String>()
        .map((part) => part.trim().toLowerCase())
        .where((part) => part.isNotEmpty)
        .join(' | ');
  }
}

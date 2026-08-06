/// 성도용 항성 (실측 RA/DEC, J2000 근사).
class SkyMapStar {
  const SkyMapStar({
    required this.id,
    required this.name,
    required this.raDeg,
    required this.decDeg,
    required this.magnitude,
    this.nameKo,
  });

  final String id;
  final String name;
  final String? nameKo;
  final double raDeg;
  final double decDeg;
  final double magnitude;
}

/// 별자리 연결선 (star id 기준).
class ConstellationLine {
  const ConstellationLine({
    required this.startStarId,
    required this.endStarId,
  });

  final String startStarId;
  final String endStarId;
}

/// 별자리 도형 정의.
class SkyMapConstellation {
  const SkyMapConstellation({
    required this.id,
    required this.name,
    required this.nameEn,
    required this.starIds,
    required this.lines,
  });

  final String id;
  final String name;
  final String nameEn;
  final List<String> starIds;
  final List<ConstellationLine> lines;
}

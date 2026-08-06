/// RA/DEC 기준 근접 검색([CatalogRepository.findNearbyObjects]) 결과 1건.
///
/// 천체 상세정보는 담지 않고 목록/확인 화면 표시에 필요한 최소 정보만
/// 가진다 — 상세 조회는 [catalogId]로 `CatalogRepository.getById`를
/// 사용해야 한다.
class CatalogCandidate {
  const CatalogCandidate({
    required this.catalogId,
    required this.displayName,
    required this.commonName,
    required this.objectType,
    required this.distanceDeg,
  });

  /// Catalog DB 참조 — `CatalogObject.id`.
  final String catalogId;

  /// 예: "M31".
  final String displayName;

  /// 예: "안드로메다 은하".
  final String commonName;

  /// 표준 분류 라벨 (예: "은하").
  final String objectType;

  /// 기준 좌표로부터의 각거리 (degrees). 가까울수록 0에 가깝다.
  final double distanceDeg;

  /// 화면 표시용 — 소수점 2자리 각거리(°).
  String get displayDistance => '${distanceDeg.toStringAsFixed(2)}°';
}

/// Gallery 사진 상세 화면의 천체 Overlay 표시용 모델.
///
/// [CatalogObject] 좌표(RA/DEC)를 Plate Solve 결과(WCS) 기준으로 사진의
/// 원본 픽셀 좌표([pixelX]/[pixelY])로 변환한 결과를 담는다.
///
/// DB에 저장되지 않는 순수 표시용(View/Presentation) 모델이며,
/// [PhotoOverlayService]가 매 조회 시 계산해 생성한다. 향후 성능 개선을
/// 위해 캐시 테이블(PhotoOverlayCache 등)을 도입하더라도 이 모델의 구조는
/// 그대로 재사용할 수 있도록 설계되었다.
class PhotoOverlayObject {
  const PhotoOverlayObject({
    required this.id,
    required this.photoId,
    required this.catalogId,
    required this.name,
    required this.commonName,
    required this.objectType,
    required this.ra,
    required this.dec,
    required this.pixelX,
    required this.pixelY,
    required this.isTarget,
    this.angularSizeMajor,
    this.angularSizeMinor,
    this.rangeRadiusMajorPixel,
    this.rangeRadiusMinorPixel,
    this.ellipseRotationRadians = 0,
  });

  /// Overlay 항목 식별자 (`catalogId`와 동일하게 사용해도 무방).
  final String id;

  /// 이 Overlay가 속한 사진(=ShootingRecord) ID.
  final String photoId;

  /// Catalog DB 참조 ID.
  final String catalogId;

  /// 카탈로그 표기명 (예: M42).
  final String name;

  /// 통칭 (예: Orion Nebula).
  final String commonName;

  /// 천체 종류 표시 라벨 (예: Nebula, Galaxy).
  final String objectType;

  /// 적경 (degrees).
  final double ra;

  /// 적위 (degrees).
  final double dec;

  /// 사진 원본 픽셀 기준 X 좌표.
  final double pixelX;

  /// 사진 원본 픽셀 기준 Y 좌표.
  final double pixelY;

  /// 이 사진의 촬영 대상(ShootingRecord.celestialObjectId)과 일치하는지 여부.
  final bool isTarget;

  /// 장축 (arcmin).
  final double? angularSizeMajor;

  /// 단축 (arcmin).
  final double? angularSizeMinor;

  /// 장축을 사진 원본 픽셀 반지름으로 환산한 값.
  final double? rangeRadiusMajorPixel;

  /// 단축을 사진 원본 픽셀 반지름으로 환산한 값. 없으면 원으로 표시한다.
  final double? rangeRadiusMinorPixel;

  /// Canvas 기준 타원 장축 각도(radians, +방향은 화면에서 시계 방향).
  final double ellipseRotationRadians;

  /// 하위 호환용 — 장축 반지름.
  double? get rangeRadiusPixel => rangeRadiusMajorPixel;

  /// Stellarium 스타일 라벨: 카탈로그명 + 통칭(다를 때만).
  String get displayLabel {
    final catalog = name.trim();
    final common = commonName.trim();
    if (common.isEmpty || common == catalog) return catalog;
    return '$catalog  $common';
  }
}

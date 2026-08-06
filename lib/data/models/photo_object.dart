import '../../core/constants/database_constants.dart';

/// Plate Solve WCS 기반으로 검색된, 사진 안에 포함되는 천체 1건.
///
/// 천체 상세정보(설명, 시각 크기 등)는 저장하지 않으며 [catalogId]로
/// `celestial_objects`(Catalog DB)를 참조한다. 데이터 중복 저장을 금지한다.
class PhotoObject {
  const PhotoObject({
    required this.id,
    required this.photoId,
    required this.catalogId,
    required this.catalogType,
    required this.displayName,
    required this.ra,
    required this.dec,
    required this.angularDistance,
    required this.confidence,
    required this.isPrimaryTarget,
    required this.isVisible,
    this.pixelX,
    this.pixelY,
    required this.createdAt,
  });

  final String id;

  /// 이 천체가 포함된 사진 — `ShootingRecord.id`를 참조한다.
  final String photoId;

  /// Catalog DB 참조 — `CatalogObject.id`.
  final String catalogId;

  /// Catalog 종류 (`CatalogType.value`: messier/ngc/ic/sh2).
  final String catalogType;

  /// 검색 시점의 표시명 캐시 (예: "M42"). 목록 표시용이며 Catalog 상세는
  /// 여전히 [catalogId]로 조회해야 한다.
  final String displayName;

  /// 천체 적경 (10진수, degrees).
  final double ra;

  /// 천체 적위 (10진수, degrees).
  final double dec;

  /// 사진(WCS) 중심으로부터의 각거리 (degrees).
  final double angularDistance;

  /// 검색 신뢰도 (0.0 ~ 1.0). 중심에 가까울수록 1.0에 가깝다.
  final double confidence;

  /// 검색된 천체 중 사진 중심에 가장 가까운 대표 촬영 대상 여부.
  final bool isPrimaryTarget;

  /// 향후 Overlay 표시 on/off 관리용 (이번 단계에는 토글 UI 없음, 기본 true).
  final bool isVisible;

  /// 향후 Overlay에서 사용할 화면 좌표. 이번 단계에서는 계산하지 않는다.
  final double? pixelX;
  final double? pixelY;

  final DateTime createdAt;

  Map<String, dynamic> toMap() {
    return {
      DatabaseConstants.colId: id,
      DatabaseConstants.colPhotoId: photoId,
      DatabaseConstants.colCatalogId: catalogId,
      DatabaseConstants.colCatalogType: catalogType,
      DatabaseConstants.colDisplayName: displayName,
      DatabaseConstants.colRa: ra,
      DatabaseConstants.colDec: dec,
      DatabaseConstants.colAngularDistance: angularDistance,
      DatabaseConstants.colConfidence: confidence,
      DatabaseConstants.colIsPrimaryTarget: isPrimaryTarget ? 1 : 0,
      DatabaseConstants.colIsVisible: isVisible ? 1 : 0,
      DatabaseConstants.colPixelX: pixelX,
      DatabaseConstants.colPixelY: pixelY,
      DatabaseConstants.colCreatedAt: createdAt.toIso8601String(),
    };
  }

  factory PhotoObject.fromMap(Map<String, dynamic> map) {
    return PhotoObject(
      id: map[DatabaseConstants.colId] as String,
      photoId: map[DatabaseConstants.colPhotoId] as String,
      catalogId: map[DatabaseConstants.colCatalogId] as String,
      catalogType: map[DatabaseConstants.colCatalogType] as String,
      displayName: map[DatabaseConstants.colDisplayName] as String,
      ra: (map[DatabaseConstants.colRa] as num).toDouble(),
      dec: (map[DatabaseConstants.colDec] as num).toDouble(),
      angularDistance:
          (map[DatabaseConstants.colAngularDistance] as num).toDouble(),
      confidence: (map[DatabaseConstants.colConfidence] as num).toDouble(),
      isPrimaryTarget:
          (map[DatabaseConstants.colIsPrimaryTarget] as int? ?? 0) == 1,
      isVisible: (map[DatabaseConstants.colIsVisible] as int? ?? 1) == 1,
      pixelX: (map[DatabaseConstants.colPixelX] as num?)?.toDouble(),
      pixelY: (map[DatabaseConstants.colPixelY] as num?)?.toDouble(),
      createdAt: DateTime.parse(map[DatabaseConstants.colCreatedAt] as String),
    );
  }

  PhotoObject copyWith({
    bool? isPrimaryTarget,
    bool? isVisible,
    double? pixelX,
    double? pixelY,
  }) {
    return PhotoObject(
      id: id,
      photoId: photoId,
      catalogId: catalogId,
      catalogType: catalogType,
      displayName: displayName,
      ra: ra,
      dec: dec,
      angularDistance: angularDistance,
      confidence: confidence,
      isPrimaryTarget: isPrimaryTarget ?? this.isPrimaryTarget,
      isVisible: isVisible ?? this.isVisible,
      pixelX: pixelX ?? this.pixelX,
      pixelY: pixelY ?? this.pixelY,
      createdAt: createdAt,
    );
  }
}

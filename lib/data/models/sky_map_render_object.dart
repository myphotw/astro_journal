import 'dart:ui' show Offset, Rect;

import '../../core/constants/catalog_type.dart';
import '../../core/constants/object_type.dart';
import 'catalog_object.dart';

/// 성도 Canvas 렌더용 Catalog 천체 (크기 포함).
///
/// 좌표·크기는 [SkyMapProjectionService]가 계산하며,
/// CustomPaint는 이 값만 사용한다.
class SkyMapRenderObject {
  const SkyMapRenderObject({
    required this.catalogId,
    required this.name,
    required this.objectType,
    required this.catalog,
    required this.raDeg,
    required this.decDeg,
    required this.screenX,
    required this.screenY,
    required this.renderWidth,
    required this.renderHeight,
    this.commonName,
    this.magnitude,
    this.sizeMajorArcmin,
    this.sizeMinorArcmin,
    this.positionAngleDeg,
    this.raLabel = '',
    this.decLabel = '',
    this.captured = false,
    this.source,
  });

  final String catalogId;
  final String name;
  final String? commonName;
  final ObjectType objectType;
  final CatalogType catalog;
  final double raDeg;
  final double decDeg;
  final double screenX;
  final double screenY;
  final double renderWidth;
  final double renderHeight;
  final double? magnitude;
  final double? sizeMajorArcmin;
  final double? sizeMinorArcmin;
  final double? positionAngleDeg;
  final String raLabel;
  final String decLabel;
  final bool captured;
  final CatalogObject? source;

  String get displayName => source?.displayName ?? name;

  String get displayCommonName =>
      source?.displayCommonName ?? commonName ?? name;

  String get displayType => source?.displayType ?? objectType.label;

  String get sizeLabel {
    final major = sizeMajorArcmin;
    final minor = sizeMinorArcmin;
    if (major != null && minor != null) {
      return "${major.toStringAsFixed(major >= 10 ? 0 : 1)}' × "
          "${minor.toStringAsFixed(minor >= 10 ? 0 : 1)}'";
    }
    if (major != null) {
      return "${major.toStringAsFixed(major >= 10 ? 0 : 1)}'";
    }
    return source?.angularSize ?? '-';
  }

  /// 천체 종류별 심볼 형태.
  SkyMapShapeKind get shapeKind {
    if (objectType == ObjectType.galaxy ||
        objectType == ObjectType.galaxyGroup) {
      return SkyMapShapeKind.galaxy;
    }
    if (objectType == ObjectType.planetaryNebula) {
      return SkyMapShapeKind.planetaryNebula;
    }
    if (objectType.isNebula ||
        objectType == ObjectType.starCloud ||
        objectType == ObjectType.nebulaWithCluster) {
      return SkyMapShapeKind.nebula;
    }
    if (objectType == ObjectType.openCluster) {
      return SkyMapShapeKind.openCluster;
    }
    if (objectType == ObjectType.globularCluster) {
      return SkyMapShapeKind.globularCluster;
    }
    return SkyMapShapeKind.point;
  }
}

/// 은하=타원, 산개=원, 구상=이중원, 성운=마름모, 행성상=별.
enum SkyMapShapeKind {
  galaxy,
  openCluster,
  globularCluster,
  nebula,
  planetaryNebula,
  point,
}

/// 밝은 별 렌더 포인트.
class SkyMapStarRender {
  const SkyMapStarRender({
    required this.id,
    required this.name,
    required this.raDeg,
    required this.decDeg,
    required this.magnitude,
    required this.screenX,
    required this.screenY,
    required this.markerRadius,
  });

  final String id;
  final String name;
  final double raDeg;
  final double decDeg;
  final double magnitude;
  final double screenX;
  final double screenY;
  final double markerRadius;
}

/// 별자리 연결선 (이미 투영된 픽셀 좌표).
class SkyMapConstellationRender {
  const SkyMapConstellationRender({
    required this.id,
    required this.name,
    required this.segments,
    required this.labelX,
    required this.labelY,
    required this.labelWidth,
    required this.labelHeight,
  });

  final String id;
  final String name;
  final List<(SkyMapPoint, SkyMapPoint)> segments;
  final double labelX;
  final double labelY;
  final double labelWidth;
  final double labelHeight;

  /// 별자리 이름 라벨 히트 영역 (터치 여유 포함).
  Rect get labelHitRect => Rect.fromCenter(
        center: Offset(labelX, labelY),
        width: labelWidth + 20,
        height: labelHeight + 16,
      );
}

/// 픽셀 좌표 쌍 (View/Paint 계층에서 Offset으로 변환).
typedef SkyMapPoint = ({double x, double y});

/// 장비 FOV Overlay 미리보기 상태.
class FovPreview {
  const FovPreview({
    required this.equipmentId,
    required this.equipmentName,
    required this.widthDegrees,
    required this.heightDegrees,
    this.rotationDegrees = 0,
  });

  final String equipmentId;
  final String equipmentName;
  final double widthDegrees;
  final double heightDegrees;
  final double rotationDegrees;

  bool get isValid => widthDegrees > 0 && heightDegrees > 0;

  String get fovLabel =>
      '${widthDegrees.toStringAsFixed(2)}° × ${heightDegrees.toStringAsFixed(2)}°';

  FovPreview copyWith({
    String? equipmentId,
    String? equipmentName,
    double? widthDegrees,
    double? heightDegrees,
    double? rotationDegrees,
  }) {
    return FovPreview(
      equipmentId: equipmentId ?? this.equipmentId,
      equipmentName: equipmentName ?? this.equipmentName,
      widthDegrees: widthDegrees ?? this.widthDegrees,
      heightDegrees: heightDegrees ?? this.heightDegrees,
      rotationDegrees: rotationDegrees ?? this.rotationDegrees,
    );
  }
}

/// 성도 검색 결과 종류.
enum SkyMapSearchKind { catalog, star, constellation }

/// 성도 통합 검색 히트 (Catalog / 별 / 별자리).
class SkyMapSearchResult {
  const SkyMapSearchResult({
    required this.kind,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.raDeg,
    required this.decDeg,
    this.catalogObject,
  });

  final SkyMapSearchKind kind;
  final String id;
  final String title;
  final String subtitle;
  final double raDeg;
  final double decDeg;
  final CatalogObject? catalogObject;

  String get kindLabel => switch (kind) {
        SkyMapSearchKind.catalog => '천체',
        SkyMapSearchKind.star => '별',
        SkyMapSearchKind.constellation => '별자리',
      };
}

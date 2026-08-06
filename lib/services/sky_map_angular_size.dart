import '../../data/models/catalog_object.dart';
import 'equipment/angular_size_parser.dart';

/// Sky Map용 각크기(arcmin) 해석.
///
/// Catalog list 조회는 major_axis 컬럼을 포함하지 않는 경우가 많아
/// [CatalogObject.angularSize] 문자열(`177.83' × 69.66'`)을 파싱한다.
abstract final class SkyMapAngularSize {
  /// (major, minor) arcmin. 없으면 null.
  static ({double major, double minor})? resolveArcmin(CatalogObject object) {
    if (object.majorAxis != null && object.majorAxis! > 0) {
      final minor = (object.minorAxis != null && object.minorAxis! > 0)
          ? object.minorAxis!
          : object.majorAxis!;
      return (major: object.majorAxis!, minor: minor);
    }

    final parsed = AngularSizeParser.parse(object.angularSize);
    if (parsed == null) return null;
    if (parsed.widthArcmin <= 0) return null;
    return (
      major: parsed.widthArcmin,
      minor: parsed.heightArcmin > 0 ? parsed.heightArcmin : parsed.widthArcmin,
    );
  }

  /// 장비 FOV(°) 정규화.
  ///
  /// 폼에 arcmin(예: 128×72)을 degree로 잘못 넣은 경우 보정한다.
  /// Seestar급 촬영 화각은 보통 수 ° 이하이므로, 한 축이라도 15° 초과면 arcmin으로 본다.
  static ({double widthDeg, double heightDeg}) normalizeEquipmentFovDeg({
    required double width,
    required double height,
  }) {
    if (width > 15 || height > 15) {
      return (widthDeg: width / 60.0, heightDeg: height / 60.0);
    }
    return (widthDeg: width, heightDeg: height);
  }
}

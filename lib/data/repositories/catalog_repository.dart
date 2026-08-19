import '../../core/constants/catalog_type.dart';
import '../models/catalog_candidate.dart';
import '../models/catalog_object.dart';

abstract class CatalogRepository {
  Future<List<CatalogObject>> getAll({bool listOnly = true});
  Future<CatalogObject?> getById(String id);
  Future<List<CatalogObject>> getByCatalog(CatalogType type);
  Future<List<CatalogObject>> search(String query, {int limit = 50});
  Future<void> updateCaptured(
    String id, {
    required bool captured,
    String? capturedDate,
  });

  Future<void> insert(CatalogObject object);
  Future<void> delete(String id);

  /// 기준 좌표([raDeg], [decDeg]) 기준 [radiusDeg]° 이내의 Catalog 천체를
  /// 가까운 순으로 반환한다 (대표 Catalog만 대상, 각거리 기준 원형 검색).
  ///
  /// Plate Solve 결과(RA/DEC)로 촬영 대상 후보를 찾는 데 사용된다.
  Future<List<CatalogCandidate>> findNearbyObjects({
    required double raDeg,
    required double decDeg,
    required double radiusDeg,
  });

  /// Plate Solve WCS(중심 [centerRaDeg]/[centerDecDeg] + 화각
  /// [fovWidthDeg]/[fovHeightDeg] + 회전각 [rotationDeg])를 기준으로 사진
  /// 영역(FOV) 내부에 포함되는 Catalog 천체(Messier/NGC/IC/Sh2, 대표
  /// Catalog만)를 각거리가 가까운 순으로 반환한다.
  ///
  /// 사진 속 천체 검색([CelestialObjectSearchService])과 Gallery Overlay
  /// ([PhotoOverlayService])가 공통으로 사용하며, 향후 성도(FOV Preview)
  /// 기능에서도 재사용 가능하도록 설계되었다.
  Future<List<CatalogObject>> findObjectsInPhotoField({
    required double centerRaDeg,
    required double centerDecDeg,
    required double fovWidthDeg,
    required double fovHeightDeg,
    required double rotationDeg,
  });
}

/// Optional checked writer used by the capture projection. Keeping this as a
/// separate capability preserves the V1 CatalogRepository contract.
abstract interface class CatalogCaptureProjectionWriter {
  Future<int> updateCaptureProjection(
    String id, {
    required bool captured,
    String? capturedDate,
  });
}

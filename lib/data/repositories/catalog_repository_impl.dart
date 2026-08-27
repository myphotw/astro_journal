import '../../core/constants/catalog_type.dart';
import '../../core/services/performance_probe.dart';
import '../../services/celestial_position_service.dart';
import '../../services/plate_solve_projection.dart';
import '../datasources/catalog_local_datasource.dart';
import '../models/catalog_candidate.dart';
import '../models/catalog_object.dart';
import 'catalog_repository.dart';

class CatalogRepositoryImpl
    implements CatalogRepository, CatalogCaptureProjectionWriter {
  CatalogRepositoryImpl({CatalogLocalDataSource? dataSource})
    : _dataSource = dataSource ?? CatalogLocalDataSource();

  final CatalogLocalDataSource _dataSource;

  @override
  Future<List<CatalogObject>> getAll({bool listOnly = true}) =>
      PerformanceProbe.measureAsync(
        'db.catalog.list',
        () => _dataSource.getAll(listOnly: listOnly),
        state: 'list_only=$listOnly',
      );

  @override
  Future<CatalogObject?> getById(String id) => _dataSource.getById(id);

  @override
  Future<List<CatalogObject>> getByCatalog(CatalogType type) =>
      _dataSource.getByCatalog(type);

  @override
  Future<List<CatalogObject>> search(String query, {int limit = 50}) =>
      _dataSource.search(query, limit: limit);

  @override
  Future<void> updateCaptured(
    String id, {
    required bool captured,
    String? capturedDate,
  }) => _dataSource.updateCaptured(
    id,
    captured: captured,
    capturedDate: capturedDate,
  );

  @override
  Future<int> updateCaptureProjection(
    String id, {
    required bool captured,
    String? capturedDate,
  }) => _dataSource.updateCaptureProjection(
    id,
    captured: captured,
    capturedDate: capturedDate,
  );

  @override
  Future<void> insert(CatalogObject object) => _dataSource.insert(object);

  @override
  Future<void> delete(String id) async {
    final object = await _dataSource.getById(id);
    if (object == null) return;
    if (!object.canDelete) {
      throw StateError('내장 카탈로그 대상은 삭제할 수 없습니다.');
    }
    await _dataSource.delete(id);
  }

  @override
  Future<List<CatalogCandidate>> findNearbyObjects({
    required double raDeg,
    required double decDeg,
    required double radiusDeg,
  }) async {
    final all = await getAll(listOnly: true);
    final raHours = raDeg / 15;

    final candidates = <CatalogCandidate>[];
    for (final object in all) {
      if (!object.isPrimaryCatalog) continue;

      final objectRaHours = CelestialPositionService.parseRaHours(object.ra);
      final objectDecDeg = CelestialPositionService.parseDecDeg(object.dec);
      final distance = CelestialPositionService.angularSeparationDeg(
        ra1Hours: raHours,
        dec1Deg: decDeg,
        ra2Hours: objectRaHours,
        dec2Deg: objectDecDeg,
      );
      if (distance > radiusDeg) continue;

      candidates.add(
        CatalogCandidate(
          catalogId: object.id,
          displayName: object.displayName,
          commonName: object.displayCommonName,
          objectType: object.displayType,
          distanceDeg: distance,
        ),
      );
    }

    candidates.sort((a, b) => a.distanceDeg.compareTo(b.distanceDeg));
    return candidates;
  }

  /// [findObjectsInPhotoField]의 검색 대상 Catalog (사진 속 천체 검색과 동일).
  static const _photoFieldCatalogs = [
    CatalogType.messier,
    CatalogType.ngc,
    CatalogType.ic,
    CatalogType.sh2,
  ];

  @override
  Future<List<CatalogObject>> findObjectsInPhotoField({
    required double centerRaDeg,
    required double centerDecDeg,
    required double fovWidthDeg,
    required double fovHeightDeg,
    required double rotationDeg,
  }) async {
    if (fovWidthDeg <= 0 || fovHeightDeg <= 0) return const [];

    final candidates = <CatalogObject>[];
    for (final catalog in _photoFieldCatalogs) {
      final objects = await getByCatalog(catalog);
      candidates.addAll(objects.where((o) => o.isPrimaryCatalog));
    }

    final matches = <(CatalogObject, double)>[];
    for (final candidate in candidates) {
      final raDeg = CelestialPositionService.parseRaHours(candidate.ra) * 15;
      final decDeg = CelestialPositionService.parseDecDeg(candidate.dec);

      final offset = PlateSolveProjection.tangentPlaneOffsetDeg(
        centerRaDeg: centerRaDeg,
        centerDecDeg: centerDecDeg,
        targetRaDeg: raDeg,
        targetDecDeg: decDeg,
        rotationDeg: rotationDeg,
      );

      final withinFov =
          offset.xDeg.abs() <= fovWidthDeg / 2 &&
          offset.yDeg.abs() <= fovHeightDeg / 2;
      if (!withinFov) continue;

      final distance = CelestialPositionService.angularSeparationDeg(
        ra1Hours: centerRaDeg / 15,
        dec1Deg: centerDecDeg,
        ra2Hours: raDeg / 15,
        dec2Deg: decDeg,
      );
      matches.add((candidate, distance));
    }

    matches.sort((a, b) => a.$2.compareTo(b.$2));
    return [for (final m in matches) m.$1];
  }
}

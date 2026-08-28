import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/data/models/catalog_candidate.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/photo_object.dart';
import 'package:astro_journal/data/models/plate_solve_result.dart';
import 'package:astro_journal/data/models/shooting_record.dart';
import 'package:astro_journal/data/repositories/catalog_repository.dart';
import 'package:astro_journal/data/repositories/photo_object_repository.dart';
import 'package:astro_journal/services/celestial_object_search_service.dart';
import 'package:astro_journal/services/celestial_position_service.dart';
import 'package:astro_journal/services/plate_solve_projection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 사진 중심(WCS)을 RA=10h00m, Dec=+20°00m으로 고정하고, FOV(가로/세로 2°)
  // 안에 들어오는 후보 1개와 밖에 있는 후보 1개를 준비한다.
  const nearObject = CatalogObject(
    id: 'M-near',
    number: 1,
    catalog: CatalogType.messier,
    name: 'M-near',
    type: '성운',
    constellation: '-',
    ra: '10h02m', // 중심에서 약 0.5° 이내
    dec: '+20d00m',
    magnitude: '-',
  );
  const farObject = CatalogObject(
    id: 'NGC-far',
    number: 2,
    catalog: CatalogType.ngc,
    name: 'NGC-far',
    type: '성운',
    constellation: '-',
    ra: '14h00m', // 중심에서 훨씬 멀리 떨어짐 (FOV 밖)
    dec: '-10d00m',
    magnitude: '-',
  );

  CatalogRepository buildCatalogRepository() =>
      _FakeCatalogRepository({
        CatalogType.messier: [nearObject],
        CatalogType.ngc: [farObject],
      });

  PlateSolveResult successWcs() => PlateSolveResult.success(
        centerRa: 150.0, // 10h → 150°
        centerDec: 20.0,
        rotation: 0,
        fovWidth: 2.0,
        fovHeight: 2.0,
      );

  group('CelestialObjectSearchService.matchCandidates', () {
    test('FOV 내 후보만 가까운 순으로 반환하고 저장하지 않는다', () async {
      final photoObjectRepo = _FakePhotoObjectRepository();
      final service = CelestialObjectSearchService(
        buildCatalogRepository(),
        photoObjectRepo,
      );

      final candidates = await service.matchCandidates(successWcs());

      expect(candidates.length, 1);
      expect(candidates.first.id, 'M-near');
      expect(photoObjectRepo.replaceForPhotoCalls, isEmpty);
    });

    test('Plate Solve가 성공이 아니면 빈 리스트를 반환한다', () async {
      final service = CelestialObjectSearchService(
        buildCatalogRepository(),
        _FakePhotoObjectRepository(),
      );

      final candidates = await service.matchCandidates(
        PlateSolveResult.failure(errorMessage: 'boom'),
      );

      expect(candidates, isEmpty);
    });
  });

  group('CelestialObjectSearchService.searchAndSave', () {
    test('FOV 내 후보를 저장하고 가장 가까운 후보를 primary로 지정한다', () async {
      final photoObjectRepo = _FakePhotoObjectRepository();
      final service = CelestialObjectSearchService(
        buildCatalogRepository(),
        photoObjectRepo,
      );

      final record = ShootingRecord(
        id: 'photo-1',
        celestialObjectId: 'M-near',
        capturedAt: DateTime(2026, 1, 1),
        createdAt: DateTime(2026, 1, 1),
        plateSolve: successWcs(),
      );

      final saved = await service.searchAndSave(record);

      expect(saved.length, 1);
      expect(saved.first.catalogId, 'M-near');
      expect(saved.first.isPrimaryTarget, isTrue);
      expect(photoObjectRepo.replaceForPhotoCalls, hasLength(1));
      expect(photoObjectRepo.replaceForPhotoCalls.first.$1, 'photo-1');
    });

    test('Plate Solve 결과가 없으면 저장소를 건드리지 않는다', () async {
      final photoObjectRepo = _FakePhotoObjectRepository();
      final service = CelestialObjectSearchService(
        buildCatalogRepository(),
        photoObjectRepo,
      );

      final record = ShootingRecord(
        id: 'photo-2',
        celestialObjectId: 'M-near',
        capturedAt: DateTime(2026, 1, 1),
        createdAt: DateTime(2026, 1, 1),
      );

      final saved = await service.searchAndSave(record);

      expect(saved, isEmpty);
      expect(photoObjectRepo.replaceForPhotoCalls, isEmpty);
    });

    test('Plate Solve가 실패면 저장소를 건드리지 않는다 (재실행으로 이전 결과가 남는 것을 방지하지 않음)',
        () async {
      final photoObjectRepo = _FakePhotoObjectRepository();
      final service = CelestialObjectSearchService(
        buildCatalogRepository(),
        photoObjectRepo,
      );

      final record = ShootingRecord(
        id: 'photo-3',
        celestialObjectId: 'M-near',
        capturedAt: DateTime(2026, 1, 1),
        createdAt: DateTime(2026, 1, 1),
        plateSolve: PlateSolveResult.failure(errorMessage: 'boom'),
      );

      final saved = await service.searchAndSave(record);

      expect(saved, isEmpty);
      expect(photoObjectRepo.replaceForPhotoCalls, isEmpty);
    });
  });
}

class _FakeCatalogRepository implements CatalogRepository {
  _FakeCatalogRepository(this._byCatalog);

  final Map<CatalogType, List<CatalogObject>> _byCatalog;

  @override
  Future<List<CatalogObject>> getAll({bool listOnly = true}) async =>
      _byCatalog.values.expand((e) => e).toList();

  @override
  Future<List<CatalogCandidate>> findNearbyObjects({
    required double raDeg,
    required double decDeg,
    required double radiusDeg,
  }) async =>
      const [];

  // 실제 [CatalogRepositoryImpl.findObjectsInPhotoField]와 동일한 FOV
  // 필터링/정렬 로직을 재사용한다 — 이 테스트는 FOV 내 후보만 가까운 순으로
  // 반환하는 동작을 검증하므로, Fake도 동일한 필터링을 수행해야 의미가 있다.
  @override
  Future<List<CatalogObject>> findObjectsInPhotoField({
    required double centerRaDeg,
    required double centerDecDeg,
    required double fovWidthDeg,
    required double fovHeightDeg,
    required double rotationDeg,
  }) async {
    if (fovWidthDeg <= 0 || fovHeightDeg <= 0) return const [];

    final all = _byCatalog.values.expand((e) => e);
    final matches = <(CatalogObject, double)>[];
    for (final candidate in all) {
      final raDeg = CelestialPositionService.parseRaHours(candidate.ra) * 15;
      final decDeg = CelestialPositionService.parseDecDeg(candidate.dec);
      final offset = PlateSolveProjection.tangentPlaneOffsetDeg(
        centerRaDeg: centerRaDeg,
        centerDecDeg: centerDecDeg,
        targetRaDeg: raDeg,
        targetDecDeg: decDeg,
        rotationDeg: rotationDeg,
        rasterCalibration: true,
      );
      final withinFov = offset.xDeg.abs() <= fovWidthDeg / 2 &&
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

  @override
  Future<CatalogObject?> getById(String id) async => null;

  @override
  Future<List<CatalogObject>> getByCatalog(CatalogType type) async =>
      _byCatalog[type] ?? const [];

  @override
  Future<List<CatalogObject>> search(String query, {int limit = 50}) async =>
      const [];

  @override
  Future<void> updateCaptured(
    String id, {
    required bool captured,
    String? capturedDate,
  }) async {}

  @override
  Future<void> insert(CatalogObject object) async {}

  @override
  Future<void> delete(String id) async {}
}

class _FakePhotoObjectRepository implements PhotoObjectRepository {
  final List<(String, List<PhotoObject>)> replaceForPhotoCalls = [];

  @override
  Future<List<PhotoObject>> getByPhotoId(String photoId) async => const [];

  @override
  Future<void> replaceForPhoto(
    String photoId,
    List<PhotoObject> objects,
  ) async {
    replaceForPhotoCalls.add((photoId, objects));
  }

  @override
  Future<void> deleteByPhotoId(String photoId) async {}
}

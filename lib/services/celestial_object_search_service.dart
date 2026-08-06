import 'package:uuid/uuid.dart';

import '../data/models/catalog_object.dart';
import '../data/models/photo_object.dart';
import '../data/models/plate_solve_result.dart';
import '../data/models/shooting_record.dart';
import '../data/repositories/catalog_repository.dart';
import '../data/repositories/photo_object_repository.dart';
import 'app_logger.dart';
import 'celestial_position_service.dart';
import 'plate_solve_projection.dart';

/// Plate Solve WCS(중심 RA/Dec/회전/화각)를 이용해 사진 영역(FOV)에 포함되는
/// 천체를 검색하여 [PhotoObjectRepository]에 저장한다.
///
/// 검색 대상은 Catalog DB에 등록된 Messier/NGC/IC/Sh2 뿐이며, 별(HIP/HD)·
/// 행성·소행성·혜성은 검색하지 않는다. 천체 상세정보는 저장하지 않고
/// `catalogId`로 Catalog DB를 참조한다.
///
/// 검색 실패(예외)는 절대 상위로 전파하지 않는다 — Plate Solve/사진 등록
/// 결과에 영향을 주지 않아야 한다.
class CelestialObjectSearchService {
  CelestialObjectSearchService(this._catalogRepository, this._repository);

  final CatalogRepository _catalogRepository;
  final PhotoObjectRepository _repository;

  static const _tag = 'CelestialObjectSearchService';
  static const _uuid = Uuid();

  /// [record]의 Plate Solve 결과(WCS)를 이용해 사진 안에 포함되는 천체를
  /// 검색하고 저장한다. 결과가 없거나 WCS 정보가 불충분해도 정상 처리한다
  /// (빈 리스트 저장, 예외 없음).
  Future<List<PhotoObject>> searchAndSave(ShootingRecord record) async {
    try {
      final wcs = record.plateSolve;
      if (wcs == null || wcs.status != PlateSolveStatus.success) {
        AppLogger.info(_tag, '${record.id}: Plate Solve 성공 결과 없음 — 검색 생략');
        return const [];
      }

      final matches = await _matchWithinFov(wcs);
      final withPrimary = <PhotoObject>[
        for (var i = 0; i < matches.length; i++)
          PhotoObject(
            id: _uuid.v4(),
            photoId: record.id,
            catalogId: matches[i].candidate.id,
            catalogType: matches[i].candidate.catalog.value,
            displayName: matches[i].candidate.displayName,
            ra: matches[i].raDeg,
            dec: matches[i].decDeg,
            angularDistance: matches[i].angularDistance,
            confidence: matches[i].confidence,
            isPrimaryTarget: i == 0,
            isVisible: true,
            createdAt: DateTime.now(),
          ),
      ];

      await _repository.replaceForPhoto(record.id, withPrimary);
      AppLogger.info(
        _tag,
        '${record.id}: 천체 검색 완료 — ${withPrimary.length}개 발견',
      );
      return withPrimary;
    } catch (e, s) {
      AppLogger.error(_tag, e, s);
      return const [];
    }
  }

  /// 저장 없이 WCS 기준으로 FOV 내 후보 카탈로그 천체를 가까운 순으로
  /// 반환한다. 사진 등록 전 "대상 인식"에 사용된다.
  Future<List<CatalogObject>> matchCandidates(PlateSolveResult wcs) async {
    try {
      final matches = await _matchWithinFov(wcs);
      return [for (final m in matches) m.candidate];
    } catch (e, s) {
      AppLogger.error(_tag, e, s);
      return const [];
    }
  }

  /// [wcs]의 중심/화각/회전 정보를 이용해 FOV 내에 포함되는 카탈로그 후보를
  /// 각거리가 가까운 순으로 정렬해 반환한다. WCS 정보가 불충분하면 빈
  /// 리스트를 반환한다 (예외 없음).
  Future<List<_Match>> _matchWithinFov(PlateSolveResult wcs) async {
    if (wcs.status != PlateSolveStatus.success) {
      AppLogger.info(_tag, 'Plate Solve 성공 결과 없음 — 검색 생략');
      return const [];
    }

    final centerRa = wcs.centerRa;
    final centerDec = wcs.centerDec;
    final fovWidth = wcs.fovWidth;
    final fovHeight = wcs.fovHeight;
    if (centerRa == null ||
        centerDec == null ||
        fovWidth == null ||
        fovHeight == null) {
      AppLogger.info(_tag, 'WCS 화각 정보 부족 — 검색 생략');
      return const [];
    }
    final rotationDeg = wcs.rotation ?? 0.0;

    // FOV 내부 포함 여부 판정 및 카탈로그 검색은 Repository 계층
    // ([CatalogRepository.findObjectsInPhotoField])에서 공통으로 처리한다
    // — Gallery Overlay 등 다른 기능에서도 동일 로직을 재사용한다.
    final candidates = await _catalogRepository.findObjectsInPhotoField(
      centerRaDeg: centerRa,
      centerDecDeg: centerDec,
      fovWidthDeg: fovWidth,
      fovHeightDeg: fovHeight,
      rotationDeg: rotationDeg,
    );

    final found = <_Match>[
      for (final candidate in candidates)
        _buildMatch(candidate, centerRa, centerDec, fovWidth, fovHeight),
    ];

    found.sort((a, b) => a.angularDistance.compareTo(b.angularDistance));
    return found;
  }

  _Match _buildMatch(
    CatalogObject candidate,
    double centerRa,
    double centerDec,
    double fovWidth,
    double fovHeight,
  ) {
    final raDeg = CelestialPositionService.parseRaHours(candidate.ra) * 15;
    final decDeg = CelestialPositionService.parseDecDeg(candidate.dec);
    final angularDistance = CelestialPositionService.angularSeparationDeg(
      ra1Hours: centerRa / 15,
      dec1Deg: centerDec,
      ra2Hours: raDeg / 15,
      dec2Deg: decDeg,
    );
    return _Match(
      candidate: candidate,
      raDeg: raDeg,
      decDeg: decDeg,
      angularDistance: angularDistance,
      confidence: PlateSolveProjection.confidence(
        angularDistance,
        fovWidth,
        fovHeight,
      ),
    );
  }
}

/// FOV 내 카탈로그 후보 하나에 대한 매칭 결과 (저장 전 중간 표현).
class _Match {
  const _Match({
    required this.candidate,
    required this.raDeg,
    required this.decDeg,
    required this.angularDistance,
    required this.confidence,
  });

  final CatalogObject candidate;
  final double raDeg;
  final double decDeg;
  final double angularDistance;
  final double confidence;
}

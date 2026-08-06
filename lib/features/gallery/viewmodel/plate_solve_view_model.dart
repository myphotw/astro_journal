import 'package:flutter/foundation.dart';

import '../../../core/constants/analysis_status.dart';
import '../../../data/models/catalog_object.dart';
import '../../../data/models/equipment.dart';
import '../../../data/models/plate_solve_result.dart';
import '../../../data/models/shooting_record.dart';
import '../../../data/repositories/catalog_repository.dart';
import '../../../data/repositories/equipment_repository.dart';
import '../../../services/app_logger.dart';
import '../../../services/celestial_object_search_service.dart';
import '../../../services/plate_solve/plate_solve_provider.dart';
import '../../../services/plate_solve_service.dart';
import '../../../services/plate_solve_settings_service.dart';
import 'gallery_view_model.dart';

/// 특정 [ShootingRecord]에 대한 Plate Solve 실행 상태.
class PlateSolveRunState {
  const PlateSolveRunState({
    this.isRunning = false,
    this.stage,
    this.message,
    this.result,
  });

  static const idle = PlateSolveRunState();

  final bool isRunning;
  final PlateSolveStage? stage;
  final String? message;
  final PlateSolveResult? result;
}

/// Gallery 사진 상세에서 Plate Solve 수동 실행을 담당하는 ViewModel.
///
/// Catalog 대상(RA/DEC/angular_size)이 있으면 Targeted Solve를 사용하고,
/// 없거나 실패 시 Blind로 폴백한다.
class PlateSolveViewModel extends ChangeNotifier {
  PlateSolveViewModel(
    this._plateSolveService,
    this._settingsService,
    this._galleryViewModel,
    this._searchService,
    this._catalogRepository,
    this._equipmentRepository,
  );

  final PlateSolveService _plateSolveService;
  final PlateSolveSettingsService _settingsService;
  final GalleryViewModel _galleryViewModel;
  final CelestialObjectSearchService _searchService;
  final CatalogRepository _catalogRepository;
  final EquipmentRepository _equipmentRepository;

  static const _tag = 'PlateSolveViewModel';

  final Map<String, PlateSolveRunState> _states = {};

  PlateSolveRunState stateFor(String recordId) =>
      _states[recordId] ?? PlateSolveRunState.idle;

  /// [record]의 사진에 대해 Plate Solve를 실행하고, 결과를 Gallery에 반영한다.
  ///
  /// 이미 Plate Solve가 완료된 기록에도 언제든 다시 실행할 수 있다
  /// ("Plate Solve 다시 실행").
  Future<PlateSolveResult> solve(ShootingRecord record) async {
    final photoUri = record.photoUri;
    if (photoUri == null || photoUri.isEmpty) {
      final failure = PlateSolveResult.failure(
        errorMessage: '사진 파일이 없어 Plate Solve를 수행할 수 없습니다.',
      );
      _setState(record.id, PlateSolveRunState(result: failure));
      return failure;
    }

    final settings = await _settingsService.load();
    if (!settings.astrometryEnabled) {
      final failure = PlateSolveResult.failure(
        errorMessage: 'Astrometry.net이 비활성화되어 있습니다. 설정에서 활성화해주세요.',
      );
      _setState(record.id, PlateSolveRunState(result: failure));
      return failure;
    }

    _setState(
      record.id,
      const PlateSolveRunState(
        isRunning: true,
        stage: PlateSolveStage.uploading,
        message: 'Plate Solving...',
      ),
    );

    final pending = PlateSolveResult.pending(
      solver: _plateSolveService.activeProvider.id,
    );
    try {
      await _galleryViewModel.updateRecord(
        record.copyWith(
          plateSolve: pending,
          analysisStatus: AnalysisStatus.processing,
        ),
      );
    } catch (e, s) {
      AppLogger.error(_tag, e, s);
    }

    final target = await _resolveTarget(record.celestialObjectId);
    final equipment = await _resolveImagingEquipment();

    if (target != null) {
      AppLogger.info(
        _tag,
        'Targeted Solve 대상=${target.displayName} '
        'ra=${target.ra} dec=${target.dec} '
        'angularSize=${target.angularSize} '
        'equipment=${equipment?.name ?? '-'}',
      );
    } else {
      AppLogger.info(
        _tag,
        'celestial_object_id=${record.celestialObjectId} '
        'Catalog 없음/좌표 없음 → Blind Solve',
      );
    }

    final result = await _plateSolveService.solve(
      imagePath: photoUri,
      imageWidth: record.exif?.imageWidth,
      imageHeight: record.exif?.imageHeight,
      target: target,
      imagingEquipment: equipment,
      onProgress: (progress) {
        _setState(
          record.id,
          PlateSolveRunState(
            isRunning: true,
            stage: progress.stage,
            message: progress.message,
          ),
        );
      },
    );

    _setState(record.id, PlateSolveRunState(result: result));

    final solved = record.copyWith(
      plateSolve: result,
      analysisStatus:
          result.success ? AnalysisStatus.completed : AnalysisStatus.failed,
    );
    try {
      await _galleryViewModel.updateRecord(solved);
    } catch (e, s) {
      AppLogger.error(_tag, e, s);
    }

    if (result.success) {
      await _searchService.searchAndSave(solved);
    }

    return result;
  }

  Future<Equipment?> _resolveImagingEquipment() async {
    try {
      final list = await _equipmentRepository.getAll(activeOnly: true);
      final imaging = list
          .where((e) => e.isImaging && e.hasFov)
          .toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return imaging.isEmpty ? null : imaging.first;
    } catch (e, s) {
      AppLogger.error(_tag, e, s);
      return null;
    }
  }

  /// celestial_object_id → Catalog. RA/DEC 파싱 불가하면 null (Blind).
  Future<CatalogObject?> _resolveTarget(String celestialObjectId) async {
    if (celestialObjectId.trim().isEmpty) return null;
    try {
      final object = await _catalogRepository.getById(celestialObjectId);
      if (object == null) return null;
      final coords =
          _plateSolveService.planner.resolveInputCoords(object);
      return coords == null ? null : object;
    } catch (e, s) {
      AppLogger.error(_tag, e, s);
      return null;
    }
  }

  void _setState(String recordId, PlateSolveRunState state) {
    _states[recordId] = state;
    notifyListeners();
  }
}

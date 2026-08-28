import 'package:flutter/foundation.dart';

import '../../../core/constants/analysis_status.dart';
import '../../../data/models/catalog_object.dart';
import '../../../data/datasources/common_file_link_datasource.dart';
import '../../../data/models/equipment.dart';
import '../../../data/models/plate_solve_result.dart';
import '../../../data/models/plate_solve_queue.dart';
import '../../../data/models/shooting_record.dart';
import '../../../data/repositories/catalog_repository.dart';
import '../../../data/repositories/equipment_repository.dart';
import '../../../services/app_logger.dart';
import '../../../services/celestial_object_search_service.dart';
import '../../../services/plate_solve/plate_solve_provider.dart';
import '../../../services/plate_solve_service.dart';
import '../../../services/plate_solve_settings_service.dart';
import '../../../services/tc_backend_plate_solve_service.dart';
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

/// Legacy explicit Plate Solve execution compatibility.
///
/// New ObservationRecords are automatically queued by TC-Backend and the
/// Gallery UI no longer invokes this ViewModel. Keep the public contract for
/// explicit compatibility flows while the backend job/result contract evolves.
class PlateSolveViewModel extends ChangeNotifier {
  PlateSolveViewModel(
    this._plateSolveService,
    PlateSolveSettingsService settingsService,
    this._galleryViewModel,
    this._searchService,
    this._catalogRepository,
    this._equipmentRepository, {
    this._commonFileLinks,
    TcBackendPlateSolveService? backendPlateSolveService,
  }) : _backendPlateSolveService = backendPlateSolveService;

  final PlateSolveService _plateSolveService;
  final GalleryViewModel _galleryViewModel;
  final CelestialObjectSearchService _searchService;
  final CatalogRepository _catalogRepository;
  final EquipmentRepository _equipmentRepository;
  final CommonFileLinkDataSource? _commonFileLinks;
  final TcBackendPlateSolveService? _backendPlateSolveService;

  static const _tag = 'PlateSolveViewModel';

  final Map<String, PlateSolveRunState> _states = {};
  final Map<String, Future<PlateSolveResult>> _inFlight = {};
  final Map<String, Future<bool>> _retryInFlight = {};

  PlateSolveRunState stateFor(String recordId) =>
      _states[recordId] ?? PlateSolveRunState.idle;

  bool canRetryFailedJob(ShootingRecord record) {
    return record.plateSolveQueueStatus == PlateSolveQueueStatus.failed &&
        record.plateSolveJobId?.trim().isNotEmpty == true &&
        _backendPlateSolveService != null &&
        !_retryInFlight.containsKey(record.id);
  }

  /// Requests retry of the existing durable backend job without polling.
  Future<bool> retryFailedJob(ShootingRecord record) {
    final existing = _retryInFlight[record.id];
    if (existing != null) return existing;
    if (!canRetryFailedJob(record) || _backendPlateSolveService == null) {
      return Future<bool>.value(false);
    }
    final run = _retryFailedJobOnce(record);
    _retryInFlight[record.id] = run;
    return run.whenComplete(() {
      if (identical(_retryInFlight[record.id], run)) {
        _retryInFlight.remove(record.id);
        notifyListeners();
      }
    });
  }

  Future<bool> _retryFailedJobOnce(ShootingRecord record) async {
    final jobId = record.plateSolveJobId!.trim();
    _setState(
      record.id,
      const PlateSolveRunState(
        isRunning: true,
        message: 'Plate Solve 재시도 요청 중…',
      ),
    );
    try {
      await _backendPlateSolveService!.retryFailedJob(jobId);
      final updated = record.copyWith(
        plateSolveQueueStatus: PlateSolveQueueStatus.waiting,
        plateSolveJobId: jobId,
        analysisStatus: AnalysisStatus.waiting,
      );
      final saved = await _galleryViewModel.updateRecord(updated);
      if (!saved) {
        _setState(
          record.id,
          const PlateSolveRunState(message: 'Plate Solve 대기 상태를 갱신하지 못했습니다.'),
        );
        return false;
      }
      _setState(record.id, PlateSolveRunState.idle);
      return true;
    } catch (error, stackTrace) {
      AppLogger.error(_tag, error, stackTrace);
      _setState(
        record.id,
        const PlateSolveRunState(message: 'Plate Solve 재시도 요청에 실패했습니다.'),
      );
      return false;
    }
  }

  /// [record]의 사진에 대해 Plate Solve를 실행하고, 결과를 Gallery에 반영한다.
  ///
  /// Explicit legacy execution. Normal Gallery UX uses backend queue status.
  Future<PlateSolveResult> solve(ShootingRecord record) async {
    final existing = _inFlight[record.id];
    if (existing != null) return existing;

    final run = _solveOnce(record);
    _inFlight[record.id] = run;
    try {
      return await run;
    } finally {
      if (identical(_inFlight[record.id], run)) {
        _inFlight.remove(record.id);
      }
    }
  }

  Future<PlateSolveResult> _solveOnce(ShootingRecord record) async {
    final photoUri = record.photoUri;
    if (photoUri == null || photoUri.isEmpty) {
      final failure = PlateSolveResult.failure(
        errorMessage: '사진 파일이 없어 Plate Solve를 수행할 수 없습니다.',
      );
      _setState(record.id, PlateSolveRunState(result: failure));
      return failure;
    }

    var commonFileId = record.commonFileId;
    var commonFileIdSource = commonFileId == null ? 'none' : 'ShootingRecord';
    if (commonFileId == null && _commonFileLinks != null) {
      commonFileId = await _commonFileLinks.getCommonFileId(record.id);
      if (commonFileId != null) commonFileIdSource = 'sync_outbox';
    }
    AppLogger.info(
      _tag,
      'identity '
      'shooting_record_id=${record.id} '
      'backend_record_id=${record.backendRecordId ?? "null"} '
      'backend_file_id=${record.backendFileId ?? "null"} '
      'common_file_id=${commonFileId ?? "null"} '
      'common_file_id_source=$commonFileIdSource',
    );
    if (_commonFileLinks != null && commonFileId == null) {
      final failure = PlateSolveResult.failure(
        errorMessage: '사진 등록이 완료된 후 Plate Solve를 사용할 수 있습니다.',
        solver: 'tc_backend',
      );
      _setState(record.id, PlateSolveRunState(result: failure));
      return failure;
    }

    _setState(
      record.id,
      const PlateSolveRunState(
        isRunning: true,
        stage: PlateSolveStage.uploading,
        message: '플레이트 솔빙 요청 중…',
      ),
    );

    final pending = PlateSolveResult.pending(
      solver: _plateSolveService.activeProvider.id,
    );
    await _galleryViewModel.updateRecord(
      record.copyWith(
        plateSolve: pending,
        analysisStatus: AnalysisStatus.processing,
      ),
    );

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
      commonFileId: commonFileId,
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

    final current = _galleryViewModel.recordForId(record.id);
    if (_galleryViewModel.hasLoaded && current == null) {
      return result;
    }
    final solved = (current ?? record).copyWith(
      plateSolve: result,
      analysisStatus: result.success
          ? AnalysisStatus.completed
          : AnalysisStatus.failed,
    );
    final saved = await _galleryViewModel.updateRecord(solved);

    if (saved && result.success) {
      await _searchService.searchAndSave(solved);
    }

    return result;
  }

  Future<Equipment?> _resolveImagingEquipment() async {
    try {
      final list = await _equipmentRepository.getAll(activeOnly: true);
      final imaging = list.where((e) => e.isImaging && e.hasFov).toList()
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
      final coords = _plateSolveService.planner.resolveInputCoords(object);
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

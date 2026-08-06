import 'package:flutter/material.dart';

import '../../../core/constants/analysis_status.dart';
import '../../../core/constants/detect_method.dart';
import '../../../data/models/catalog_object.dart';
import '../../../data/models/plate_solve_result.dart';
import '../../../data/models/shooting_record.dart';
import '../../../data/repositories/catalog_repository.dart';
import '../../../services/catalog_search_service.dart';
import '../../../services/photo_registration_service.dart';

class PhotoFirstRegistrationViewModel extends ChangeNotifier {
  PhotoFirstRegistrationViewModel(
    this._catalogRepository,
    this._registrationService,
    this._catalogSearchService,
  );

  final CatalogRepository _catalogRepository;
  final PhotoRegistrationService _registrationService;
  final CatalogSearchService _catalogSearchService;

  bool _isProcessing = false;
  String? _errorMessage;
  List<CatalogObject> _allObjects = [];
  String? _previewLocalPath;

  bool get isProcessing => _isProcessing;
  String? get errorMessage => _errorMessage;
  List<CatalogObject> get allObjects => _allObjects;
  String? get previewLocalPath => _previewLocalPath;

  Future<void> loadCatalog() async {
    _allObjects = await _catalogRepository.getAll();
  }

  /// 파일만 복사 (EXIF는 위저드에서 progressive enrich).
  Future<List<PhotoRegistrationPayload>> pickPhotosCopyOnly(
    BuildContext context,
  ) async {
    _isProcessing = true;
    _errorMessage = null;
    notifyListeners();

    try {
      if (_allObjects.isEmpty) {
        await loadCatalog();
      }
      if (!context.mounted) return [];
      final payloads =
          await _registrationService.pickMultipleAndCopyOnly(context);
      _previewLocalPath =
          payloads.isNotEmpty ? payloads.last.localPath : null;
      return payloads;
    } catch (error) {
      _errorMessage = error.toString();
      _previewLocalPath = null;
      return [];
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  /// 레거시: 복사 + EXIF 일괄 분석.
  Future<List<PhotoRegistrationPayload>> pickPhotosFromGallery(
    BuildContext context,
  ) =>
      pickPhotosCopyOnly(context);

  Future<PhotoRegistrationPayload> enrichPayload(
    PhotoRegistrationPayload stub,
  ) {
    return _registrationService.enrichPayload(stub);
  }

  CatalogObject? resolveTarget(String? targetName) {
    return _catalogSearchService.resolveTarget(targetName, _allObjects);
  }

  /// 사진 선택 직후 — 원본 파일명 중복만 확인한다.
  Future<DuplicateCheckResult?> checkDuplicateByFilename(
    PhotoRegistrationPayload payload,
  ) {
    return _registrationService.checkDuplicateByFilename(payload);
  }

  Future<DuplicateCheckResult?> checkDuplicate({
    required PhotoRegistrationPayload payload,
    required String celestialObjectId,
    ConfirmedMetadata? confirmed,
  }) {
    return _registrationService.checkDuplicate(
      payload: payload,
      celestialObjectId: celestialObjectId,
      confirmed: confirmed,
    );
  }

  Future<ShootingRecord?> registerPhoto({
    required CatalogObject object,
    required PhotoRegistrationPayload payload,
    required ConfirmedMetadata confirmed,
    DetectMethod? detectMethod,
    AnalysisStatus analysisStatus = AnalysisStatus.completed,
    PlateSolveResult? plateSolve,
  }) async {
    _errorMessage = null;

    try {
      final record = await _registrationService.registerPhotoRecord(
        payload: payload,
        confirmed: confirmed,
        celestialObjectId: object.id,
        detectMethod: detectMethod,
        analysisStatus: analysisStatus,
        plateSolve: plateSolve,
      );
      return record;
    } catch (error) {
      _errorMessage = error.toString();
      return null;
    }
  }

  void beginBackgroundSave() {
    _isProcessing = true;
    _errorMessage = null;
    _previewLocalPath = null;
    notifyListeners();
  }

  void endBackgroundSave() {
    _isProcessing = false;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  void reset() {
    _isProcessing = false;
    _errorMessage = null;
    _previewLocalPath = null;
    notifyListeners();
  }
}

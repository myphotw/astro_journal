import 'package:flutter/foundation.dart';

import 'package:uuid/uuid.dart';

import '../../../core/constants/detect_method.dart';
import '../../../data/models/catalog_exposure_guidance.dart';
import '../../../data/models/catalog_object.dart';

import '../../../data/models/equipment_recommendation.dart';
import '../../../data/models/imaging_suitability_assessment.dart';

import '../../../data/models/plate_solve_result.dart';

import '../../../data/models/shooting_record.dart';

import '../../../data/repositories/catalog_repository.dart';

import '../../../data/repositories/equipment_repository.dart';

import '../../../data/repositories/shooting_record_repository.dart';

import '../../../services/app_logger.dart';

import '../../../services/base_exposure_settings_service.dart';
import '../../../services/catalog_exposure_guidance_builder.dart';

import '../../../services/exposure_policy.dart';

import '../../../services/equipment/equipment_recommendation_service.dart';

import '../../../services/metadata_service.dart';

import '../../../services/object_imaging_profile_provider.dart';

import '../../../services/photo_registration_service.dart';

class CatalogDetailViewModel extends ChangeNotifier {
  CatalogDetailViewModel(
    CatalogObject object,

    this._shootingRecordRepository,

    this._catalogRepository,

    this._registrationService,

    this._metadataService,

    this._equipmentRepository,

    this._equipmentRecommendationService,

    this._baseExposureSettingsService,

    this._profileProvider,

    this._exposurePolicy, {
    CatalogExposureGuidanceBuilder? exposureGuidanceBuilder,
    List<CatalogObject>? navigationObjects,
  }) : _exposureGuidanceBuilder =
           exposureGuidanceBuilder ?? const CatalogExposureGuidanceBuilder(),
       _objects = List<CatalogObject>.from(navigationObjects ?? [object]),

       _currentIndex = _resolveInitialIndex(object, navigationObjects);

  final ShootingRecordRepository _shootingRecordRepository;

  final CatalogRepository _catalogRepository;

  final PhotoRegistrationService _registrationService;

  final MetadataService _metadataService;

  final EquipmentRepository _equipmentRepository;

  final EquipmentRecommendationService _equipmentRecommendationService;

  final BaseExposureSettingsService _baseExposureSettingsService;

  final ObjectImagingProfileProvider _profileProvider;

  final ExposurePolicy _exposurePolicy;

  final CatalogExposureGuidanceBuilder _exposureGuidanceBuilder;

  final List<CatalogObject> _objects;

  int _currentIndex;

  bool _isLoading = false;

  bool _isPicking = false;

  String? _errorMessage;

  int _captureCount = 0;

  DateTime? _lastCapturedAt;

  bool _dataChanged = false;

  List<ShootingRecord> _records = [];

  bool? _capturedState;

  ObjectEquipmentRecommendation _equipmentRecommendation =
      ObjectEquipmentRecommendation.empty;

  Duration? _minimumExposure;

  Duration? _recommendedExposure;

  CatalogExposureGuidance? _exposureGuidance;

  List<CatalogObject> get objects => List.unmodifiable(_objects);

  int get currentIndex => _currentIndex;

  int get objectCount => _objects.length;

  bool get canSwipe => _objects.length > 1;

  String? get positionLabel =>
      canSwipe ? '${_currentIndex + 1} / ${_objects.length}' : null;

  CatalogObject get object => _objects[_currentIndex];

  CatalogObject objectAt(int index) => _objects[index];

  bool get isLoading => _isLoading;

  bool get isPicking => _isPicking;

  String? get errorMessage => _errorMessage;

  int get captureCount => _captureCount;

  DateTime? get lastCapturedAt => _lastCapturedAt;

  bool get dataChanged => _dataChanged;

  List<ShootingRecord> get records => _records;

  bool get isCaptured => _capturedState ?? object.captured;

  ObjectEquipmentRecommendation get equipmentRecommendation =>
      _equipmentRecommendation;

  Duration? get minimumExposure => _minimumExposure;

  Duration? get recommendedExposure => _recommendedExposure;

  CatalogExposureGuidance? get exposureGuidance => _exposureGuidance;

  String? get exposureTimeLineLabel {
    final min = _minimumExposure;

    final rec = _recommendedExposure;

    if (min == null || rec == null) return null;

    return '${min.inMinutes}분 / ${rec.inMinutes}분';
  }

  static int indexOfObject(List<CatalogObject> objects, CatalogObject target) {
    return objects.indexWhere((o) => o.id == target.id);
  }

  static int _resolveInitialIndex(
    CatalogObject object,

    List<CatalogObject>? navigationObjects,
  ) {
    if (navigationObjects == null || navigationObjects.isEmpty) {
      return 0;
    }

    final index = indexOfObject(navigationObjects, object);

    return index >= 0 ? index : 0;
  }

  Future<void> onPageChanged(int index) async {
    if (index < 0 || index >= _objects.length || index == _currentIndex) {
      return;
    }

    _currentIndex = index;

    _resetRecordState();

    notifyListeners();

    await load();
  }

  void _resetRecordState() {
    _capturedState = null;

    _records = [];

    _captureCount = 0;

    _lastCapturedAt = null;

    _errorMessage = null;

    _equipmentRecommendation = ObjectEquipmentRecommendation.empty;

    _minimumExposure = null;

    _recommendedExposure = null;

    _exposureGuidance = null;
  }

  Future<void> load() async {
    _isLoading = true;

    _errorMessage = null;

    notifyListeners();

    try {
      final full = await _catalogRepository.getById(object.id);
      if (full != null) {
        _objects[_currentIndex] = full;
      }

      final fetched = await _shootingRecordRepository.getByCelestialObjectId(
        object.id,
      );

      fetched.sort((a, b) => b.capturedAt.compareTo(a.capturedAt));

      _records = fetched;

      _captureCount = fetched.length;

      _lastCapturedAt = fetched.isNotEmpty ? fetched.first.capturedAt : null;

      if (_captureCount == 0 && isCaptured) {
        await _catalogRepository.updateCaptured(object.id, captured: false);

        _capturedState = false;

        _dataChanged = true;
      }

      await _loadEquipmentRecommendation();

      await _loadBaseExposureInfo();
    } catch (error) {
      _errorMessage = error.toString();
    } finally {
      _isLoading = false;

      notifyListeners();
    }
  }

  Future<void> _loadEquipmentRecommendation() async {
    final equipment = await _equipmentRepository.getAll(activeOnly: true);

    _equipmentRecommendation = _equipmentRecommendationService
        .recommendForObject(object: object, equipment: equipment);
  }

  Future<void> _loadBaseExposureInfo() async {
    _minimumExposure = null;

    _recommendedExposure = null;

    _exposureGuidance = null;

    try {
      final settings = await _baseExposureSettingsService.load();

      final profile = _profileProvider.profileFor(object);

      final bortle = settings.referenceBortle;

      _minimumExposure = _exposurePolicy.calculateMinimumExposure(
        bortle: bortle,

        profile: profile,
      );

      _recommendedExposure = _exposurePolicy.calculateRecommendedExposure(
        bortle: bortle,

        profile: profile,
      );

      _exposureGuidance = _exposureGuidanceBuilder.build(
        profile: profile,

        referenceBortle: bortle,

        equipmentFit: _catalogEquipmentFit(),
      );
    } catch (_) {
      // Keep UI stable when settings cannot be loaded.
    }
  }

  ImagingEquipmentFit? _catalogEquipmentFit() {
    if (_equipmentRecommendation.imaging.isEmpty) return null;
    final best = _equipmentRecommendation.imaging.first;
    return ImagingEquipmentFit(
      score: best.score,
      screenFillPercent: best.screenFillPercent,
      equipmentId: best.equipment.id,
      equipmentName: best.equipment.name,
      framingRecommendation: best.framingRecommendation,
      supportsMosaic: best.equipment.supportsMosaic,
    );
  }

  /// 갤러리에서 사진을 선택하고 파일만 복사한다 (EXIF는 위저드에서 enrich).
  Future<PhotoRegistrationPayload?> pickPhotoAndPrepare() async {
    _isPicking = true;
    _errorMessage = null;
    notifyListeners();

    try {
      return await _registrationService.pickAndCopyOnly();
    } catch (error) {
      _errorMessage = error.toString();
      return null;
    } finally {
      _isPicking = false;
      notifyListeners();
    }
  }

  Future<PhotoRegistrationPayload> enrichPayload(
    PhotoRegistrationPayload stub,
  ) {
    return _registrationService.enrichPayload(stub);
  }

  /// 메타데이터 확인 후 ShootingRecord를 DB에 저장한다.
  ///
  /// 저장에 성공하면 저장된 [ShootingRecord]를 반환한다 (실패 시 null).
  Future<ShootingRecord?> savePhotoRecord(
    PhotoRegistrationPayload payload,
    ConfirmedMetadata confirmed, {
    PlateSolveResult? plateSolve,
  }) async {
    _errorMessage = null;

    try {
      await _registrationService.savePhotoFile(payload);

      final confirmedWithTarget = ConfirmedMetadata(
        targetName: confirmed.targetName ?? object.displayId,
        memo: confirmed.memo,
        capturedAt: confirmed.capturedAt,
        equipment: confirmed.equipment,
        locationName: confirmed.locationName,
        lat: confirmed.lat,
        lng: confirmed.lng,
        stackNum: confirmed.stackNum,
        singleExpSec: confirmed.singleExpSec,
        totalExpSec: confirmed.totalExpSec,
        filter: confirmed.filter,
        iso: confirmed.iso,
        fstop: confirmed.fstop,
        focal: confirmed.focal,
      );

      final record = await _registrationService.registerPhotoRecord(
        payload: payload,
        confirmed: confirmedWithTarget,
        celestialObjectId: object.id,
        detectMethod: DetectMethod.manual,
        plateSolve: plateSolve,
      );

      AppLogger.metadata('CatalogDetail', 'UI Success');

      if (record.isRepresentative) {
        _records = _records
            .map((r) => r.copyWith(isRepresentative: false))
            .toList();
      }

      final capturedAt = record.capturedAt;

      _capturedState = true;

      if (_lastCapturedAt == null || capturedAt.isAfter(_lastCapturedAt!)) {
        _lastCapturedAt = capturedAt;
      }

      final insertIndex = _records.indexWhere(
        (r) => r.capturedAt.isBefore(capturedAt),
      );

      if (insertIndex == -1) {
        _records.add(record);
      } else {
        _records.insert(insertIndex, record);
      }

      _dataChanged = true;

      return record;
    } catch (error) {
      _errorMessage = error.toString();

      return null;
    } finally {
      notifyListeners();
    }
  }

  /// OwnerName 또는 파일명에서 추출한 대상명이 이 카탈로그 항목과 일치하는지 확인한다.

  ///

  /// 공백 제거 + 대문자 정규화 후 displayId 및 name과 비교한다.

  bool isMetadataTargetMatch(String? metadataTarget) {
    return _metadataService.isTargetMatch(
      metadataTarget,

      object.displayId,

      object.name,
    );
  }

  /// 사진 없이 날짜와 메모만으로 촬영 기록을 수동 등록한다.

  Future<void> addManualRecord(DateTime capturedAt, String memo) async {
    _errorMessage = null;

    try {
      final now = DateTime.now();

      final record = ShootingRecord(
        id: const Uuid().v4(),

        celestialObjectId: object.id,

        capturedAt: capturedAt,

        memo: memo,

        createdAt: now,
      );

      await _shootingRecordRepository.save(record);

      final dateStr =
          '${capturedAt.year}-${capturedAt.month.toString().padLeft(2, '0')}-${capturedAt.day.toString().padLeft(2, '0')}';

      await _catalogRepository.updateCaptured(
        object.id,

        captured: true,

        capturedDate: dateStr,
      );

      _captureCount++;

      _capturedState = true;

      if (_lastCapturedAt == null || capturedAt.isAfter(_lastCapturedAt!)) {
        _lastCapturedAt = capturedAt;
      }

      final insertIndex = _records.indexWhere(
        (r) => r.capturedAt.isBefore(capturedAt),
      );

      if (insertIndex == -1) {
        _records.add(record);
      } else {
        _records.insert(insertIndex, record);
      }

      _dataChanged = true;
    } catch (error) {
      _errorMessage = error.toString();
    } finally {
      notifyListeners();
    }
  }

  Future<void> deleteObject() async {
    _errorMessage = null;

    try {
      for (final record in List.of(_records)) {
        await _shootingRecordRepository.delete(record.id);
      }

      await _catalogRepository.delete(object.id);

      _dataChanged = true;

      _objects.removeAt(_currentIndex);

      if (_objects.isEmpty) {
        notifyListeners();

        return;
      }

      if (_currentIndex >= _objects.length) {
        _currentIndex = _objects.length - 1;
      }

      _resetRecordState();

      await load();
    } catch (error) {
      _errorMessage = error.toString();

      notifyListeners();
    }
  }

  Future<void> setRepresentativePhoto(String recordId) async {
    _errorMessage = null;

    try {
      await _shootingRecordRepository.setRepresentative(recordId);

      _records = _records
          .map((r) => r.copyWith(isRepresentative: r.id == recordId))
          .toList();

      _dataChanged = true;
    } catch (error) {
      _errorMessage = error.toString();
    } finally {
      notifyListeners();
    }
  }

  ShootingRecord? get representativeRecord {
    for (final record in _records) {
      if (record.isRepresentative &&
          record.photoUri != null &&
          record.photoUri!.isNotEmpty) {
        return record;
      }
    }

    for (final record in _records) {
      if (record.photoUri != null && record.photoUri!.isNotEmpty) {
        return record;
      }
    }

    return null;
  }
}

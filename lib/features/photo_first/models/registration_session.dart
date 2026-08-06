import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../../core/constants/detect_method.dart';
import '../../../data/models/catalog_object.dart';
import '../../../data/models/exif_info.dart';
import '../../../data/models/plate_solve_result.dart';
import '../../../services/metadata_format.dart';
import '../../../services/photo_registration_service.dart';
import '../../../shared/widgets/material_date_time_picker_field.dart';
import '../services/registration_image_cache.dart';

/// 사진 등록 위저드 단계.
enum RegistrationWizardStep {
  target,
  shooting,
  location,
  memo,
}

/// 한 장의 등록 결과를 위저드에서 반환할 때 사용.
class RegistrationOutcome {
  const RegistrationOutcome({
    required this.session,
    required this.confirmed,
  });

  final RegistrationSession session;
  final ConfirmedMetadata confirmed;
}

/// 등록 시작~저장까지 메모리에만 유지하는 세션.
///
/// 중간 단계에서는 DB 조회·이미지 재로드·EXIF 재분석을 하지 않는다.
/// DB 저장은 마지막 단계에서 [toConfirmedMetadata] 결과로 한 번만 수행한다.
class RegistrationSession {
  RegistrationSession({
    required PhotoRegistrationPayload payload,
    this.selectedObject,
    this.detectMethod,
    this.autoDetected = false,
    this.plateSolveResult,
  }) : _payload = payload {
    _exifReady = !payload.exifInfo.isPlaceholder;
    exifReady = ValueNotifier<bool>(_exifReady);
    analysisMessage = ValueNotifier<String?>(
      _exifReady ? null : '메타데이터 분석 중…',
    );
    plateSolveBusy = ValueNotifier<bool>(false);
    plateSolveMessage = ValueNotifier<String?>(null);
    _seedFromExif(payload.exifInfo);
  }

  PhotoRegistrationPayload _payload;
  PhotoRegistrationPayload get payload => _payload;

  CatalogObject? selectedObject;
  DetectMethod? detectMethod;
  bool autoDetected;
  PlateSolveResult? plateSolveResult;

  late final ValueNotifier<bool> exifReady;
  late final ValueNotifier<String?> analysisMessage;
  late final ValueNotifier<bool> plateSolveBusy;
  late final ValueNotifier<String?> plateSolveMessage;

  bool _exifReady = false;
  bool get isExifReady => _exifReady;

  /// 원본 경로 (재로드하지 않음).
  String get localPath => _payload.localPath;

  ExifInfo get exifInfo => _payload.exifInfo;

  /// 디코드된 썸네일 바이트·[MemoryImage] — 등록 완료까지 동일 객체.
  Uint8List? thumbnailBytes;
  MemoryImage? thumbnailImage;

  /// UI 표시용 (ResizeImage 래핑) — 위젯 재생성 시에도 동일 provider.
  ImageProvider? displayThumbnailProvider;

  bool get hasCachedThumbnail => thumbnailImage != null;

  // —— 촬영 정보 (Step 2) ——
  DateTime? capturedAt;
  String? equipment;
  int? stackNum;

  /// 숫자만 (UI 입력값).
  String? singleExpSecDigits;

  /// 적분시간(분) 숫자 문자열.
  String? totalExpMinutesDigits;
  String? filter;
  String? isoDigits;
  String? fstopDigits;
  String? focalDigits;

  // —— 위치 (Step 3) ——
  String? locationName;
  double? lat;
  double? lng;

  // —— 메모 (Step 4) ——
  String? memo;

  /// 대상명 오버라이드 (검색 선택과 다를 때).
  String? targetNameOverride;

  void disposeNotifiers() {
    exifReady.dispose();
    analysisMessage.dispose();
    plateSolveBusy.dispose();
    plateSolveMessage.dispose();
  }

  void _seedFromExif(ExifInfo exif) {
    capturedAt ??= MaterialDateTimePickerField.tryParse(exif.date);
    if (equipment == null || equipment!.trim().isEmpty) {
      equipment = exif.equipment.trim().isEmpty ? null : exif.equipment.trim();
    }
    if (locationName == null || locationName!.trim().isEmpty) {
      locationName = exif.locationName?.trim();
    }
    lat ??= exif.lat;
    lng ??= exif.lng;
    stackNum ??= exif.stackNum;
    if (singleExpSecDigits == null || singleExpSecDigits!.isEmpty) {
      singleExpSecDigits = _digitsOnly(exif.singleExpSec ?? '');
    }
    if (totalExpMinutesDigits == null || totalExpMinutesDigits!.isEmpty) {
      totalExpMinutesDigits =
          MetadataFormat.minutesNumberFromDisplay(exif.exposure);
    }
    if (filter == null || filter!.isEmpty) {
      filter = exif.filter;
    }
    if (isoDigits == null || isoDigits!.isEmpty) {
      isoDigits = _digitsOnly(exif.iso);
    }
    if (fstopDigits == null || fstopDigits!.isEmpty) {
      fstopDigits = _fstopNumber(exif.fstop);
    }
    if (focalDigits == null || focalDigits!.isEmpty) {
      focalDigits = _digitsOnly(exif.focal);
    }
    if ((targetNameOverride == null || targetNameOverride!.isEmpty) &&
        exif.targetName?.trim().isNotEmpty == true) {
      targetNameOverride = exif.targetName!.trim();
    }
  }

  /// EXIF/파이프라인 결과를 반영한다. 사용자가 이미 입력한 값은 덮어쓰지 않는다.
  void applyEnrichedPayload(PhotoRegistrationPayload enriched) {
    _payload = enriched;
    _seedFromExif(enriched.exifInfo);
    _exifReady = true;
    analysisMessage.value = null;
    exifReady.value = true;
  }

  void markAnalysisFailed(Object error) {
    analysisMessage.value = '메타데이터 분석 실패 — 수동 입력으로 진행하세요.';
    _exifReady = true;
    exifReady.value = true;
    if (kDebugMode) {
      debugPrint('RegistrationSession enrich failed: $error');
    }
  }

  /// 썸네일을 한 번만 로드해 [thumbnailImage]에 고정한다.
  Future<void> ensureThumbnailLoaded() async {
    if (thumbnailImage != null) return;
    final cached = await RegistrationImageCache.loadThumbnail(localPath);
    thumbnailBytes = cached.bytes;
    thumbnailImage = cached.image;
    displayThumbnailProvider = ResizeImage(cached.image, height: 440);
  }

  void selectTarget(CatalogObject object, {DetectMethod? method}) {
    selectedObject = object;
    detectMethod = method ?? DetectMethod.manual;
    targetNameOverride ??= object.displayId;
  }

  ConfirmedMetadata toConfirmedMetadata() {
    final object = selectedObject;
    final targetName = (targetNameOverride?.trim().isNotEmpty == true)
        ? targetNameOverride!.trim()
        : object?.displayId;

    final single = singleExpSecDigits?.trim();
    final iso = isoDigits?.trim();
    final fstop = fstopDigits?.trim();
    final focal = focalDigits?.trim();
    final totalExp = MetadataFormat.formatMinutesInputToExposure(
      totalExpMinutesDigits ?? '',
    );

    return ConfirmedMetadata(
      targetName: _v(targetName),
      memo: _v(memo),
      capturedAt: capturedAt?.toIso8601String(),
      equipment: equipment,
      locationName: _v(locationName),
      lat: lat,
      lng: lng,
      stackNum: stackNum,
      singleExpSec: (single == null || single.isEmpty) ? null : '$single초',
      totalExpSec: totalExp,
      filter: _v(filter),
      iso: (iso == null || iso.isEmpty) ? null : 'ISO $iso',
      fstop: (fstop == null || fstop.isEmpty) ? null : 'f/$fstop',
      focal: (focal == null || focal.isEmpty) ? null : '$focal mm',
    );
  }

  static String? _v(String? s) {
    final t = s?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  static String _digitsOnly(String raw) {
    final match = RegExp(r'[\d.]+').firstMatch(raw.replaceAll(',', ''));
    return match?.group(0) ?? '';
  }

  static String _fstopNumber(String raw) {
    final cleaned = raw.replaceFirst(RegExp(r'^[fF]/\s*'), '');
    return _digitsOnly(cleaned);
  }
}

import 'equipment.dart';

import 'fov_box.dart';

import 'eyepiece.dart';

enum EquipmentRecommendationAvailability {
  available,
  notRegistered,
  insufficientData,
  noSuitableMatch,
}

/// 천체·조건에 대한 장비 추천 결과 묶음.

class ObjectEquipmentRecommendation {
  const ObjectEquipmentRecommendation({
    required this.imaging,

    required this.visual,

    this.hasRegisteredEquipment = true,

    this.showImaging = true,

    this.showVisual = true,

    this.imagingAvailability = EquipmentRecommendationAvailability.available,

    this.visualAvailability = EquipmentRecommendationAvailability.available,
  });

  final List<ImagingEquipmentRecommendation> imaging;

  final List<VisualEquipmentRecommendation> visual;

  final bool hasRegisteredEquipment;

  final bool showImaging;

  final bool showVisual;

  final EquipmentRecommendationAvailability imagingAvailability;

  final EquipmentRecommendationAvailability visualAvailability;

  static const empty = ObjectEquipmentRecommendation(
    imaging: [],

    visual: [],

    hasRegisteredEquipment: false,

    showImaging: false,

    showVisual: false,
  );
}

class ImagingEquipmentRecommendation {
  const ImagingEquipmentRecommendation({
    required this.equipment,

    required this.score,

    required this.starCount,

    required this.reason,

    required this.screenFillPercent,

    this.screenFillNote,

    this.framingRecommendation = FramingRecommendation.good,

    this.rank = 0,

    this.captureSettings = const [],
  });

  final Equipment equipment;

  final double score;

  final int starCount;

  final String reason;

  final int screenFillPercent;

  final String? screenFillNote;

  final FramingRecommendation framingRecommendation;

  final int rank;

  /// 장비에 등록된 촬영 capability를 천체 프로필과 교차한 모드별 안내.
  ///
  /// 화각 적합도 [score]와는 독립이며, 검증되지 않은 최적 노출/Gain을
  /// 만들지 않기 위해 권장값은 nullable이다.
  final List<CaptureModeRecommendation> captureSettings;
}

enum CaptureRecommendationMode { altAz, equatorial, custom }

enum CaptureRecommendationConfidence {
  recommended('권장값'),
  experimental('시험 촬영 시작값'),
  unavailable('추천 불가');

  const CaptureRecommendationConfidence(this.label);

  final String label;
}

enum CaptureExposurePurpose {
  standard('기본 촬영'),
  highlightProtection('밝은 영역 보호'),
  faintStructure('희미한 구조');

  const CaptureExposurePurpose(this.label);

  final String label;
}

/// 촬영 목적별 단일 프레임 노출 안내.
///
/// [exposureSeconds]가 null인 경우에는 더 긴 단일 노출을 만들어내지 않고
/// [guidance]로 총 적산시간 등 안전한 촬영 방향만 안내한다.
class CaptureExposureRecommendation {
  const CaptureExposureRecommendation({
    required this.purpose,
    this.exposureSeconds,
    required this.confidence,
    required this.policyId,
    required this.reason,
    this.guidance,
    this.inputs = const [],
  });

  final CaptureExposurePurpose purpose;
  final double? exposureSeconds;
  final CaptureRecommendationConfidence confidence;
  final String policyId;
  final String reason;
  final String? guidance;
  final List<String> inputs;
}

/// 촬영 설정 정책에 선택적으로 전달되는 관측 환경 스냅샷.
///
/// 값이 없는 환경은 추정하지 않으며, 정책 결과의 [exposureInputs] 등에는
/// 실제 산출에 사용된 값만 기록한다.
class CaptureRecommendationContext {
  const CaptureRecommendationContext({
    this.siteName,
    this.bortle,
    this.sqm,
    this.targetAltitude,
    this.moonIllumination,
    this.moonSeparation,
    this.observableMinutes,
    this.referenceTime,
  });

  final String? siteName;
  final int? bortle;
  final double? sqm;
  final double? targetAltitude;
  final double? moonIllumination;
  final double? moonSeparation;
  final int? observableMinutes;
  final DateTime? referenceTime;

  bool get hasData =>
      siteName != null ||
      bortle != null ||
      sqm != null ||
      targetAltitude != null ||
      moonIllumination != null ||
      moonSeparation != null ||
      observableMinutes != null ||
      referenceTime != null;
}

class CaptureModeRecommendation {
  const CaptureModeRecommendation({
    required this.modeId,
    required this.mode,
    required this.label,
    required this.exposureSupportLabel,
    required this.exposureReason,
    this.usesSensorDerotation = false,
    this.recommendedExposureSeconds,
    this.exposureConfidence = CaptureRecommendationConfidence.unavailable,
    this.exposurePolicyId = 'capture.exposure.unavailable',
    this.exposureInputs = const [],
    this.exposureRecommendations = const [],
    this.exposureAdvisories = const [],
    this.recommendedGain,
    this.gainSupportLabel,
    this.gainConfidence = CaptureRecommendationConfidence.unavailable,
    this.gainPolicyId = 'capture.gain.unavailable',
    this.gainReason,
    this.gainInputs = const [],
    this.recommendedFilters = const [],
    this.supportedFilters = const [],
    this.filterReason,
    this.filterConfidence = CaptureRecommendationConfidence.unavailable,
    this.filterPolicyId = 'capture.filter.unavailable',
    this.filterInputs = const [],
    this.channelCombinations = const [],
    this.cautions = const [],
  });

  final String modeId;
  final CaptureRecommendationMode mode;
  final String label;
  final bool usesSensorDerotation;

  /// 검증된 장비별 규칙이 있을 때만 채운다.
  final double? recommendedExposureSeconds;
  final CaptureRecommendationConfidence exposureConfidence;
  final String exposurePolicyId;
  final List<String> exposureInputs;
  final List<CaptureExposureRecommendation> exposureRecommendations;
  final List<String> exposureAdvisories;
  final String exposureSupportLabel;
  final String exposureReason;

  /// 검증된 장비별 규칙이 있을 때만 채운다.
  final double? recommendedGain;
  final String? gainSupportLabel;
  final CaptureRecommendationConfidence gainConfidence;
  final String gainPolicyId;
  final String? gainReason;
  final List<String> gainInputs;

  final List<String> recommendedFilters;
  final List<String> supportedFilters;
  final String? filterReason;
  final CaptureRecommendationConfidence filterConfidence;
  final String filterPolicyId;
  final List<String> filterInputs;
  final List<ChannelCombinationRecommendation> channelCombinations;
  final List<String> cautions;
}

class ChannelCombinationRecommendation {
  const ChannelCombinationRecommendation({
    required this.id,
    required this.name,
    required this.guidance,
    this.confidence = CaptureRecommendationConfidence.unavailable,
    this.policyId = 'capture.channels.unavailable',
    this.reason,
    this.inputs = const [],
    this.recommendedPrimaryPercent,
    this.recommendedSecondaryPercent,
  });

  final String id;
  final String name;
  final String guidance;
  final CaptureRecommendationConfidence confidence;
  final String policyId;
  final String? reason;
  final List<String> inputs;

  /// 검증된 천체별 비율이 있을 때만 채운다. 둘 다 null이면 지원 정보만
  /// 표시하며 특정 비율을 추천하지 않는다.
  final int? recommendedPrimaryPercent;
  final int? recommendedSecondaryPercent;
}

class VisualEquipmentRecommendation {
  const VisualEquipmentRecommendation({
    required this.equipment,

    this.eyepiece,

    required this.score,

    required this.starCount,

    required this.reason,

    required this.isRecommended,

    required this.screenFillPercent,

    this.screenFillNote,

    this.isFeasibleToday = true,

    this.recommendedEyepieceFocalLengthMm,
  });

  final Equipment equipment;

  final Eyepiece? eyepiece;

  final double score;

  final int starCount;

  final String reason;

  final bool isRecommended;

  final int screenFillPercent;

  final String? screenFillNote;

  /// 오늘 조건 기준 안시 가능 여부.

  final bool isFeasibleToday;

  /// 대상과 망원경 기준 이론적 권장 아이피스 초점거리.

  final double? recommendedEyepieceFocalLengthMm;

  /// 아이피스 초점거리 (mm) 표시. 이름과 무관하게 항상 mm를 노출한다.

  String get eyepieceFocalLabel {
    if (eyepiece == null) return '';

    final mm = eyepiece!.focalLengthMm;

    final text = mm == mm.roundToDouble()
        ? mm.toStringAsFixed(0)
        : mm.toStringAsFixed(1);

    return '${text}mm';
  }

  String get eyepieceDisplayName {
    if (eyepiece == null) return '';

    final name = eyepiece!.name.trim();

    if (name.isNotEmpty) return name;

    return eyepieceFocalLabel;
  }

  String get eyepieceLabel =>
      eyepieceFocalLabel.isNotEmpty ? '$eyepieceFocalLabel 아이피스' : '';

  String get recommendedEyepieceFocalLabel {
    final mm = recommendedEyepieceFocalLengthMm;
    if (mm == null || !mm.isFinite || mm <= 0) return '';
    return '약 ${mm.round()}mm';
  }

  int? get magnification {
    final telescopeFocalLength = equipment.focalLengthMm;
    final eyepieceFocalLength = eyepiece?.focalLengthMm;
    if (telescopeFocalLength == null ||
        eyepieceFocalLength == null ||
        telescopeFocalLength <= 0 ||
        eyepieceFocalLength <= 0) {
      return null;
    }
    return (telescopeFocalLength / eyepieceFocalLength).round();
  }

  VisualEquipmentRecommendation copyWith({
    Equipment? equipment,

    Eyepiece? eyepiece,

    double? score,

    int? starCount,

    String? reason,

    bool? isRecommended,

    int? screenFillPercent,

    String? screenFillNote,

    bool? isFeasibleToday,

    double? recommendedEyepieceFocalLengthMm,
  }) {
    return VisualEquipmentRecommendation(
      equipment: equipment ?? this.equipment,

      eyepiece: eyepiece ?? this.eyepiece,

      score: score ?? this.score,

      starCount: starCount ?? this.starCount,

      reason: reason ?? this.reason,

      isRecommended: isRecommended ?? this.isRecommended,

      screenFillPercent: screenFillPercent ?? this.screenFillPercent,

      screenFillNote: screenFillNote ?? this.screenFillNote,

      isFeasibleToday: isFeasibleToday ?? this.isFeasibleToday,

      recommendedEyepieceFocalLengthMm:
          recommendedEyepieceFocalLengthMm ??
          this.recommendedEyepieceFocalLengthMm,
    );
  }
}

/// 추천대상 상세용 — 오늘 최적 장비 1건씩.

class TodayEquipmentRecommendation {
  const TodayEquipmentRecommendation({
    this.imaging,

    this.visual = const [],

    this.hasRegisteredEquipment = true,

    this.showImaging = true,

    this.showVisual = true,

    this.imagingAvailability = EquipmentRecommendationAvailability.available,

    this.visualAvailability = EquipmentRecommendationAvailability.available,
  });

  final ImagingEquipmentRecommendation? imaging;

  final List<VisualEquipmentRecommendation> visual;

  final bool hasRegisteredEquipment;

  final bool showImaging;

  final bool showVisual;

  final EquipmentRecommendationAvailability imagingAvailability;

  final EquipmentRecommendationAvailability visualAvailability;

  static const empty = TodayEquipmentRecommendation(
    hasRegisteredEquipment: false,

    showImaging: false,

    showVisual: false,
  );
}

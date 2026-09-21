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
  });

  final Equipment equipment;

  final double score;

  final int starCount;

  final String reason;

  final int screenFillPercent;

  final String? screenFillNote;

  final FramingRecommendation framingRecommendation;

  final int rank;
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

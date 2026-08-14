import 'fov_box.dart';

enum TrackingMode { altAz, eq }

extension TrackingModeLabel on TrackingMode {
  String get label => switch (this) {
    TrackingMode.altAz => 'Alt-Az',
    TrackingMode.eq => 'EQ',
  };
}

enum FilterMode { on, off }

extension FilterModeLabel on FilterMode {
  String get label => switch (this) {
    FilterMode.on => 'ON',
    FilterMode.off => 'OFF',
  };
}

enum MosaicMode { on, off }

extension MosaicModeLabel on MosaicMode {
  String get label => switch (this) {
    MosaicMode.on => 'ON',
    MosaicMode.off => 'OFF',
  };
}

enum ExpectedResultQuality { trace, shape, mainStructure, detail, excellent }

extension ExpectedResultQualityLabel on ExpectedResultQuality {
  int get level => index + 1;

  String get label => switch (this) {
    ExpectedResultQuality.trace => '흔적 확인',
    ExpectedResultQuality.shape => '대상 형태 확인',
    ExpectedResultQuality.mainStructure => '주요 구조 확인',
    ExpectedResultQuality.detail => '세부 구조 표현',
    ExpectedResultQuality.excellent => '매우 좋은 대상',
  };

  String get starLabel => '${'★' * level}${'☆' * (5 - level)}';
}

class ImagingEquipmentFit {
  const ImagingEquipmentFit({
    required this.score,
    required this.screenFillPercent,
    this.equipmentId,
    this.equipmentName,
    this.framingRecommendation,
    this.supportsMosaic = false,
  });

  final double score;
  final int screenFillPercent;
  final String? equipmentId;
  final String? equipmentName;
  final FramingRecommendation? framingRecommendation;
  final bool supportsMosaic;
}

class ImagingSuitabilityAssessment {
  const ImagingSuitabilityAssessment({
    required this.quality,
    required this.filterMode,
    this.mosaicMode = MosaicMode.off,
    required this.trackingMode,
    required this.suitabilityScore,
    required this.scoreMultiplier,
    required this.reason,
    required this.hasReliableSurfaceBrightness,
    this.fieldRotationSpanDegrees = 0,
  });

  final ExpectedResultQuality quality;
  final FilterMode filterMode;
  final MosaicMode mosaicMode;
  final TrackingMode trackingMode;
  final double suitabilityScore;
  final double scoreMultiplier;
  final String reason;
  final bool hasReliableSurfaceBrightness;
  final double fieldRotationSpanDegrees;
}

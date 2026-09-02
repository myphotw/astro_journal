import 'fov_box.dart';
import 'object_imaging_profile.dart';

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

/// Expected benefit of enabling the existing ON/OFF filter for a target.
/// This does not describe a physical filter type.
enum FilterEffectiveness { none, low, medium, high }

extension FilterEffectivenessLabel on FilterEffectiveness {
  String get label => switch (this) {
    FilterEffectiveness.none => '효과 없음',
    FilterEffectiveness.low => '효과 낮음',
    FilterEffectiveness.medium => '효과 보통',
    FilterEffectiveness.high => '효과 높음',
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

/// Stable, target/site-derived Hour Angle window for Alt-Az scheduling.
/// Values are signed hours in the -12h..+12h range.
class TargetPreferredHaWindow {
  const TargetPreferredHaWindow({
    required this.startHours,
    required this.endHours,
    required this.centerHours,
    required this.durationMinutes,
    this.todayStartTime,
    this.todayEndTime,
  });

  final double startHours;
  final double endHours;
  final double centerHours;
  final int durationMinutes;

  /// Date-specific interval selected by the existing Alt-Az policy. The HA
  /// values remain the stable cross-date identity; these values are for UI.
  final DateTime? todayStartTime;
  final DateTime? todayEndTime;
}

class ImagingSuitabilityAssessment {
  const ImagingSuitabilityAssessment({
    required this.quality,
    required this.filterMode,
    this.mosaicMode = MosaicMode.off,
    required this.trackingMode,
    required double suitabilityScore,
    required this.scoreMultiplier,
    required this.reason,
    required this.hasReliableSurfaceBrightness,
    this.targetLightPollutionSensitivity =
        TargetLightPollutionSensitivity.medium,
    this.filterEffectiveness = FilterEffectiveness.none,
    double? imagingEfficiencyScore,
    this.recommendedDailyExposure,
    this.preferredHaWindow,
    this.dailyDurationLimitedByFieldRotation = false,
    this.dailyFieldRotationSpanDegrees = 0,
    this.fieldRotationSpanDegrees = 0,
  }) : imagingEfficiencyScore = imagingEfficiencyScore ?? suitabilityScore;

  final ExpectedResultQuality quality;
  final FilterMode filterMode;
  final MosaicMode mosaicMode;
  final TrackingMode trackingMode;
  final double imagingEfficiencyScore;
  final double scoreMultiplier;
  final String reason;
  final bool hasReliableSurfaceBrightness;
  final TargetLightPollutionSensitivity targetLightPollutionSensitivity;
  final FilterEffectiveness filterEffectiveness;
  final Duration? recommendedDailyExposure;
  final TargetPreferredHaWindow? preferredHaWindow;
  final bool dailyDurationLimitedByFieldRotation;
  final double dailyFieldRotationSpanDegrees;
  final double fieldRotationSpanDegrees;

  /// Backward-compatible name used by the existing detail and tests.
  double get suitabilityScore => imagingEfficiencyScore;
}

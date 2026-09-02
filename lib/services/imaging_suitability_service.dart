import '../core/constants/object_type.dart';
import '../core/constants/surface_brightness_class.dart';
import '../data/models/fov_box.dart';
import '../data/models/imaging_suitability_assessment.dart';
import '../data/models/object_imaging_profile.dart';
import 'equipment/fov_framing_engine.dart';

/// Converts the existing exposure/profile/equipment outputs into a conservative
/// expected-result assessment. It deliberately avoids sensor/QE assumptions.
class ImagingSuitabilityService {
  const ImagingSuitabilityService();

  ImagingSuitabilityAssessment assess({
    required ObjectImagingProfile profile,
    required int bortle,
    TrackingMode trackingMode = TrackingMode.altAz,
    FilterMode? filterMode,
    ImagingEquipmentFit? equipmentFit,
    Duration? recommendedExposure,
    Duration? recommendedDailyExposure,
    TargetPreferredHaWindow? preferredHaWindow,
    bool dailyDurationLimitedByFieldRotation = false,
    double dailyFieldRotationSpanDegrees = 0,
    double? targetAltitude,
    double moonIllumination = 0,
    double moonSeparation = 180,
    double cloudCover = 0,
    double fieldRotationSpanDegrees = 0,
  }) {
    final resolvedFilterMode = filterMode ?? recommendedFilterMode(profile);
    final filterEffectiveness = filterEffectivenessFor(profile);
    final lightPollutionSensitivity = profile.lightPollutionSensitivity;
    final framingRecommendation = _framingRecommendation(equipmentFit);
    final mosaicMode =
        framingRecommendation == FramingRecommendation.mosaicRequired &&
            (equipmentFit?.supportsMosaic ?? false)
        ? MosaicMode.on
        : MosaicMode.off;
    var qualityLevel = _baseQuality(profile.surfaceBrightnessClass);

    final urbanSky = bortle >= 7;
    final lowSurfaceBrightness =
        profile.surfaceBrightnessClass.index >=
        SurfaceBrightnessClass.dim.index;
    final narrowbandRelief =
        resolvedFilterMode == FilterMode.on &&
        filterEffectiveness.index >= FilterEffectiveness.medium.index;

    if (urbanSky && lowSurfaceBrightness) {
      var lightPollutionPenalty = bortle >= 8 ? 2 : 1;
      if (narrowbandRelief) {
        // A filter can recover part of the lost contrast, but it must never
        // turn light pollution into a benefit over a dark site.
        lightPollutionPenalty -= 1;
      }
      qualityLevel -= lightPollutionPenalty.clamp(0, 2);
    } else if (urbanSky && profile.objectType == ObjectType.galaxy) {
      // Even a galaxy with a bright core loses faint outer structure under an
      // urban sky. This is a contrast penalty, not extra exposure credit.
      qualityLevel -= 1;
    }

    final fitScore = equipmentFit?.score;
    final screenFillPercent = equipmentFit?.screenFillPercent;
    final extremelyTiny = screenFillPercent != null && screenFillPercent <= 1;
    final smallInFrame =
        screenFillPercent != null &&
        screenFillPercent > 1 &&
        screenFillPercent <= 5;
    if (fitScore != null) {
      if (mosaicMode == MosaicMode.on) {
        // The framing deficit is recoverable, so do not apply the same
        // oversize penalty as a single-frame-only setup.
      } else if (fitScore < 30) {
        qualityLevel -= 2;
      } else if (fitScore < 55) {
        qualityLevel -= 1;
      } else if (fitScore >= 90) {
        qualityLevel += 1;
      }
    }

    if (targetAltitude != null && targetAltitude < 25) {
      qualityLevel -= 1;
    }
    if (moonIllumination > 0.6 && moonSeparation < 45) {
      qualityLevel -= 1;
    }
    if (cloudCover > 50) {
      qualityLevel -= 1;
    }

    final longExposure = (recommendedExposure?.inMinutes ?? 0) >= 90;
    final highAltitude = (targetAltitude ?? 0) >= 65;
    final altAzRotationRisk =
        trackingMode == TrackingMode.altAz &&
        !dailyDurationLimitedByFieldRotation &&
        longExposure &&
        (highAltitude || fieldRotationSpanDegrees >= 20);
    if (altAzRotationRisk) {
      qualityLevel -= 1;
    }

    final hasReliableSurfaceBrightness =
        profile.estimatedSurfaceBrightness != null;
    final metadataQualityCap = switch (profile.metadataReliability) {
      ImagingMetadataReliability.reliable => 5,
      ImagingMetadataReliability.partial => 3,
      ImagingMetadataReliability.missing => 2,
    };
    if (qualityLevel > metadataQualityCap) {
      qualityLevel = metadataQualityCap;
    }

    if (extremelyTiny && qualityLevel > 1) {
      qualityLevel = 1;
    } else if (smallInFrame && qualityLevel > 2) {
      qualityLevel = 2;
    }

    qualityLevel = qualityLevel.clamp(1, 5);
    final quality = ExpectedResultQuality.values[qualityLevel - 1];

    var multiplier = switch (quality) {
      ExpectedResultQuality.trace => 0.45,
      ExpectedResultQuality.shape => 0.65,
      ExpectedResultQuality.mainStructure => 0.82,
      ExpectedResultQuality.detail => 0.95,
      ExpectedResultQuality.excellent => 1.0,
    };
    final effectiveFitScore = fitScore == null
        ? null
        : mosaicMode == MosaicMode.on
        ? fitScore.clamp(60, 100)
        : fitScore.clamp(0, 100);
    final equipmentFactor = effectiveFitScore == null
        ? 1.0
        : 0.7 + 0.3 * (effectiveFitScore / 100);
    final skyFactor = _skyQualityFactor(
      profile: profile,
      bortle: bortle,
      filterMode: resolvedFilterMode,
      filterEffectiveness: filterEffectiveness,
    );
    final framingFactor = extremelyTiny
        ? 0.65
        : smallInFrame
        ? 0.82
        : 1.0;
    final metadataFactor = switch (profile.metadataReliability) {
      ImagingMetadataReliability.reliable => 1.0,
      ImagingMetadataReliability.partial => 0.9,
      ImagingMetadataReliability.missing => 0.75,
    };
    multiplier *= equipmentFactor * skyFactor * framingFactor * metadataFactor;
    if (altAzRotationRisk) multiplier *= 0.85;

    final suitabilityScore =
        (quality.level *
                20 *
                equipmentFactor *
                skyFactor *
                framingFactor *
                metadataFactor)
            .clamp(0, 100)
            .toDouble();

    return ImagingSuitabilityAssessment(
      quality: quality,
      filterMode: resolvedFilterMode,
      mosaicMode: mosaicMode,
      trackingMode: trackingMode,
      suitabilityScore: suitabilityScore,
      imagingEfficiencyScore: suitabilityScore,
      scoreMultiplier: multiplier.clamp(0.2, 1.0).toDouble(),
      reason: _reason(
        profile: profile,
        bortle: bortle,
        filterMode: resolvedFilterMode,
        mosaicMode: mosaicMode,
        framingRecommendation: framingRecommendation,
        screenFillPercent: screenFillPercent,
        fitScore: fitScore,
        altAzRotationRisk: altAzRotationRisk,
      ),
      hasReliableSurfaceBrightness: hasReliableSurfaceBrightness,
      targetLightPollutionSensitivity: lightPollutionSensitivity,
      filterEffectiveness: filterEffectiveness,
      recommendedDailyExposure: recommendedDailyExposure,
      preferredHaWindow: preferredHaWindow,
      dailyDurationLimitedByFieldRotation:
          dailyDurationLimitedByFieldRotation,
      dailyFieldRotationSpanDegrees: dailyFieldRotationSpanDegrees,
      fieldRotationSpanDegrees: fieldRotationSpanDegrees,
    );
  }

  FramingRecommendation? _framingRecommendation(
    ImagingEquipmentFit? equipmentFit,
  ) {
    if (equipmentFit == null) return null;
    return equipmentFit.framingRecommendation ??
        FovFramingEngine.recommendationFor(
          equipmentFit.screenFillPercent / 100,
        );
  }

  double _skyQualityFactor({
    required ObjectImagingProfile profile,
    required int bortle,
    required FilterMode filterMode,
    required FilterEffectiveness filterEffectiveness,
  }) {
    final sensitivity = profile.lightPollutionSensitivity;
    var maximumPenalty = switch (sensitivity) {
      TargetLightPollutionSensitivity.veryHigh =>
        switch (profile.surfaceBrightnessClass) {
          SurfaceBrightnessClass.extremeDim => 0.24,
          SurfaceBrightnessClass.veryDim => 0.20,
          _ => 0.16,
        },
      TargetLightPollutionSensitivity.high =>
        profile.surfaceBrightnessClass == SurfaceBrightnessClass.dim
            ? 0.16
            : 0.10,
      TargetLightPollutionSensitivity.medium
          when profile.objectType == ObjectType.galaxy =>
        0.10,
      TargetLightPollutionSensitivity.low
          when profile.objectType == ObjectType.galaxy =>
        0.06,
      _ => 0.0,
    };

    // Keep filter benefit inside the existing sky factor. No additional
    // Bortle multiplier is applied to the final recommendation score.
    if (maximumPenalty == 0 &&
        filterMode == FilterMode.off &&
        filterEffectiveness == FilterEffectiveness.high) {
      maximumPenalty = 0.06;
    }
    if (filterMode == FilterMode.on) {
      maximumPenalty *= switch (filterEffectiveness) {
        FilterEffectiveness.high => 0.0,
        FilterEffectiveness.medium => 0.55,
        FilterEffectiveness.low => 0.9,
        FilterEffectiveness.none => 1.0,
      };
    }
    final pollutionRatio = ((bortle.clamp(1, 9) - 1) / 8).toDouble();
    return 1 - maximumPenalty * pollutionRatio;
  }

  FilterMode recommendedFilterMode(ObjectImagingProfile profile) {
    return switch (profile.objectType) {
      ObjectType.emissionNebula ||
      ObjectType.planetaryNebula ||
      ObjectType.supernovaRemnant => FilterMode.on,
      ObjectType.complexNebula || ObjectType.nebulaWithCluster =>
        profile.supportsNarrowband ? FilterMode.on : FilterMode.off,
      _ => FilterMode.off,
    };
  }

  FilterEffectiveness filterEffectivenessFor(ObjectImagingProfile profile) {
    return switch (profile.objectType) {
      ObjectType.emissionNebula ||
      ObjectType.planetaryNebula ||
      ObjectType.supernovaRemnant => FilterEffectiveness.high,
      ObjectType.complexNebula || ObjectType.nebulaWithCluster =>
        profile.supportsNarrowband
            ? FilterEffectiveness.medium
            : FilterEffectiveness.low,
      ObjectType.galaxy ||
      ObjectType.galaxyGroup ||
      ObjectType.reflectionNebula => FilterEffectiveness.low,
      ObjectType.darkNebula => FilterEffectiveness.none,
      _ => FilterEffectiveness.none,
    };
  }

  int _baseQuality(SurfaceBrightnessClass brightness) => switch (brightness) {
    SurfaceBrightnessClass.veryBright => 5,
    SurfaceBrightnessClass.bright => 5,
    SurfaceBrightnessClass.normal => 4,
    SurfaceBrightnessClass.dim => 3,
    SurfaceBrightnessClass.veryDim => 2,
    SurfaceBrightnessClass.extremeDim => 1,
  };

  String _reason({
    required ObjectImagingProfile profile,
    required int bortle,
    required FilterMode filterMode,
    required MosaicMode mosaicMode,
    required FramingRecommendation? framingRecommendation,
    required int? screenFillPercent,
    required double? fitScore,
    required bool altAzRotationRisk,
  }) {
    if (profile.metadataReliability == ImagingMetadataReliability.missing) {
      return '밝기와 크기 정보가 부족해 예상 품질을 보수적으로 제한했습니다.';
    }
    if (profile.metadataReliability == ImagingMetadataReliability.partial) {
      return '밝기 또는 크기 정보가 부족해 예상 품질을 제한했습니다.';
    }
    if (screenFillPercent != null && screenFillPercent <= 1) {
      return '대상이 매우 작아 S30급 화각에서는 세부 표현이 어렵습니다.';
    }
    if (screenFillPercent != null && screenFillPercent <= 5) {
      return '대상이 작아 현재 장비에서는 세부 표현이 제한됩니다.';
    }
    if (mosaicMode == MosaicMode.on) {
      return '단일 화각보다 큰 대상 — 모자이크 촬영을 권장합니다.';
    }
    if (framingRecommendation == FramingRecommendation.mosaicRequired) {
      return '단일 화각보다 크고 현재 장비는 모자이크를 지원하지 않습니다.';
    }
    if (profile.surfaceBrightnessClass.index >=
            SurfaceBrightnessClass.veryDim.index &&
        bortle >= 7 &&
        filterMode == FilterMode.off) {
      return '저표면밝기 대상이며 현재 광해 환경에서는 배경과의 대비가 매우 낮습니다.';
    }
    if (fitScore != null && fitScore < 30) {
      return '현재 장비의 시야에서 대상이 너무 작거나 프레이밍 적합도가 낮습니다.';
    }
    if (altAzRotationRisk) {
      return 'Alt-Az 장시간 촬영에서는 필드 회전 영향을 받을 수 있습니다.';
    }
    if (filterMode == FilterMode.on && bortle >= 7) {
      return '내장 필터 사용 시 도시 광해 환경에서 대비 확보에 유리합니다.';
    }
    return '현재 광해와 장비 프레이밍을 기준으로 한 예상 결과입니다.';
  }
}

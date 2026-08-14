import '../core/constants/object_type.dart';
import '../core/constants/surface_brightness_class.dart';
import '../data/models/imaging_suitability_assessment.dart';
import '../data/models/object_imaging_profile.dart';

/// Converts the existing exposure/profile/equipment outputs into a conservative
/// expected-result assessment. It deliberately avoids sensor/QE assumptions.
class ImagingSuitabilityService {
  const ImagingSuitabilityService();

  ImagingSuitabilityAssessment assess({
    required ObjectImagingProfile profile,
    required int bortle,
    TrackingMode trackingMode = TrackingMode.altAz,
    ImagingEquipmentFit? equipmentFit,
    Duration? recommendedExposure,
    double? targetAltitude,
    double moonIllumination = 0,
    double moonSeparation = 180,
    double cloudCover = 0,
    double fieldRotationSpanDegrees = 0,
  }) {
    final filterMode = recommendedFilterMode(profile);
    var qualityLevel = _baseQuality(profile.surfaceBrightnessClass);

    final urbanSky = bortle >= 7;
    final lowSurfaceBrightness =
        profile.surfaceBrightnessClass.index >=
        SurfaceBrightnessClass.dim.index;
    final narrowbandRelief =
        urbanSky && filterMode == FilterMode.on && profile.supportsNarrowband;

    if (urbanSky && lowSurfaceBrightness) {
      if (narrowbandRelief) {
        qualityLevel += 1;
      } else {
        qualityLevel -= bortle >= 8 ? 2 : 1;
      }
    } else if (urbanSky && profile.objectType == ObjectType.galaxy) {
      // Even a galaxy with a bright core loses faint outer structure under an
      // urban sky. This is a contrast penalty, not extra exposure credit.
      qualityLevel -= 1;
    }

    final fitScore = equipmentFit?.score;
    if (fitScore != null) {
      if (fitScore < 30) {
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
        longExposure &&
        (highAltitude || fieldRotationSpanDegrees >= 20);
    if (altAzRotationRisk) {
      qualityLevel -= 1;
    }

    final hasReliableSurfaceBrightness =
        profile.estimatedSurfaceBrightness != null;
    if (!hasReliableSurfaceBrightness) {
      final hasTypeSpecificRelief =
          filterMode == FilterMode.on && profile.supportsNarrowband;
      final confidenceCap = hasTypeSpecificRelief ? 4 : 3;
      if (qualityLevel > confidenceCap) qualityLevel = confidenceCap;
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
    if (fitScore != null) {
      multiplier *= 0.7 + 0.3 * (fitScore.clamp(0, 100) / 100);
    }
    if (altAzRotationRisk) multiplier *= 0.85;

    final suitabilityScore =
        (quality.level *
                20 *
                (fitScore == null ? 1 : 0.7 + 0.3 * fitScore / 100))
            .clamp(0, 100)
            .toDouble();

    return ImagingSuitabilityAssessment(
      quality: quality,
      filterMode: filterMode,
      trackingMode: trackingMode,
      suitabilityScore: suitabilityScore,
      scoreMultiplier: multiplier.clamp(0.2, 1.0).toDouble(),
      reason: _reason(
        profile: profile,
        bortle: bortle,
        filterMode: filterMode,
        fitScore: fitScore,
        altAzRotationRisk: altAzRotationRisk,
        hasReliableSurfaceBrightness: hasReliableSurfaceBrightness,
      ),
      hasReliableSurfaceBrightness: hasReliableSurfaceBrightness,
      fieldRotationSpanDegrees: fieldRotationSpanDegrees,
    );
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
    required double? fitScore,
    required bool altAzRotationRisk,
    required bool hasReliableSurfaceBrightness,
  }) {
    if (!hasReliableSurfaceBrightness) {
      return '광도 또는 각크기 정보가 부족해 보수적으로 평가했습니다.';
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

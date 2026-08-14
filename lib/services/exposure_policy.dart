import 'dart:math' as math;

import '../core/constants/exposure_policy_config.dart';
import '../core/constants/imaging_difficulty.dart';
import '../core/constants/imaging_recommendation_rules.dart';
import '../core/constants/object_type.dart';
import '../core/constants/surface_brightness_class.dart';
import '../data/models/object_imaging_profile.dart';
import '../features/light_pollution_map/overlay/light_pollution_scale.dart';

/// Computes per-target exposure requirements from site light pollution
/// and [ObjectImagingProfile].
class ExposurePolicy {
  const ExposurePolicy();

  int resolveBortle({int? bortle, double? brightness}) {
    if (bortle != null) return bortle.clamp(1, 9);
    if (brightness != null) {
      return LightPollutionScale.artificialMcdToBortle(brightness);
    }
    return ExposurePolicyConfig.defaultBortle;
  }

  Duration calculateMinimumExposure({
    int? bortle,
    double? brightness,
    required ObjectImagingProfile profile,
  }) {
    final resolved = resolveBortle(bortle: bortle, brightness: brightness);
    final minutes = _minimumMinutesForProfile(resolved, profile);
    return Duration(minutes: minutes);
  }

  Duration calculateRecommendedExposure({
    int? bortle,
    double? brightness,
    required ObjectImagingProfile profile,
  }) {
    final resolved = resolveBortle(bortle: bortle, brightness: brightness);
    final minimum = calculateMinimumExposure(
      bortle: bortle,
      brightness: brightness,
      profile: profile,
    );

    final multiplier = _recommendedMultiplier(resolved, profile);
    return Duration(minutes: (minimum.inMinutes * multiplier).round());
  }

  bool isRecommended({
    int? bortle,
    double? brightness,
    required ObjectImagingProfile profile,
  }) {
    final resolved = resolveBortle(bortle: bortle, brightness: brightness);

    if (ImagingRecommendationRules.isTypeExcludedAtBortle(
      profile.objectType,
      resolved,
    )) {
      return false;
    }

    if (resolved > profile.minimumRecommendedBortle) {
      if (profile.supportsNarrowband &&
          resolved <= ImagingRecommendationRules.narrowbandReliefMaxBortle) {
        return true;
      }
      if (resolved == profile.minimumRecommendedBortle + 1 &&
          profile.estimatedSurfaceBrightness != null &&
          profile.surfaceBrightnessClass.index <=
              SurfaceBrightnessClass.bright.index) {
        // A metadata-backed high-surface-brightness target may remain useful
        // one Bortle step beyond the type template. This keeps eligibility
        // aligned with a strong expected-quality assessment without hiding
        // the sky penalty or special-casing a catalog ID.
        return true;
      }
      return false;
    }

    return true;
  }

  int _minimumMinutesForProfile(int bortle, ObjectImagingProfile profile) {
    var minutes = profile.baseExposureMinutes.toDouble();

    final bortleGap = math.max(0, bortle - profile.recommendedBortle);
    minutes += bortleGap * ExposurePolicyConfig.bortleExposureStepMinutes;
    minutes +=
        bortleGap * profile.surfaceBrightnessClass.lightPollutionPenaltyMinutes;

    minutes *= profile.imagingDifficulty.exposureMultiplier;

    if (profile.objectType == ObjectType.galaxy &&
        bortle >= ImagingRecommendationRules.seoulBortle - 1) {
      minutes +=
          ImagingRecommendationRules.galaxyHighBortleExposureBonusMinutes;
    }

    return minutes.round().clamp(
      ExposurePolicyConfig.baseMinimumMinutes,
      24 * 60,
    );
  }

  double _recommendedMultiplier(int bortle, ObjectImagingProfile profile) {
    if (profile.objectType == ObjectType.galaxy &&
        bortle >= ImagingRecommendationRules.seoulBortle - 1) {
      return ExposurePolicyConfig.galaxyHighBortleRecommendedMultiplier;
    }
    return ExposurePolicyConfig.recommendedExposureMultiplier;
  }
}

import '../../core/constants/exposure_policy_config.dart';
import '../../core/constants/surface_brightness_class.dart';
import '../../data/models/object_imaging_profile.dart';
import '../../data/models/observation_context.dart';
import '../observation_score_service.dart';

/// Scores site sky quality from brightness / Bortle data and target profile.
class LightPollutionScore {
  const LightPollutionScore();

  double calculate({
    required ObservationContext context,
    required ObjectImagingProfile profile,
  }) {
    final siteScore = ObservationScoreService.computeSiteObservationScore(
      brightness: context.brightness,
      bortle: context.bortle,
    );
    final base = siteScore ?? ObservationScoreService.siteObservationScoreNeutral;

    final bortle = context.bortle ?? ExposurePolicyConfig.defaultBortle;
    final bortleGap = (bortle - profile.recommendedBortle).clamp(0, 9);
    final profilePenalty =
        profile.surfaceBrightnessClass.lightPollutionScorePenalty * bortleGap;

    return (base - profilePenalty).clamp(0.0, 100.0);
  }
}

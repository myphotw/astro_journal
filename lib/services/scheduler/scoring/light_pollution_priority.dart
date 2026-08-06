import '../../../core/constants/surface_brightness_class.dart';
import '../../../data/models/object_imaging_profile.dart';
import '../../../data/models/observation_context.dart';

/// Prioritizes light-pollution-sensitive targets for darker portions of the night.
class LightPollutionPriority {
  const LightPollutionPriority();

  double calculate({
    required ObjectImagingProfile profile,
    required ObservationContext context,
  }) {
    final siteBortle = context.bortle ?? 5;
    final bortleGap = (siteBortle - profile.recommendedBortle).clamp(0, 9);
    final surfacePenalty =
        profile.surfaceBrightnessClass.lightPollutionScorePenalty;

    final score = 40 + bortleGap * 6 + surfacePenalty * bortleGap;
    return score.clamp(0.0, 100.0);
  }
}

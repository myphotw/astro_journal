import '../../core/constants/imaging_difficulty.dart';
import '../../data/models/object_imaging_profile.dart';

/// Recommendation filters applied when tonight is [ObservationStatus.limited].
abstract final class LimitedRecommendationPolicy {
  static bool allowsTarget(ObjectImagingProfile profile) {
    return switch (profile.imagingDifficulty) {
      ImagingDifficulty.veryEasy ||
      ImagingDifficulty.easy ||
      ImagingDifficulty.normal =>
        true,
      ImagingDifficulty.hard ||
      ImagingDifficulty.veryHard ||
      ImagingDifficulty.extreme =>
        false,
    };
  }
}

/// Thresholds for [ObservationStatus] evaluation.
abstract final class ObservationStatusConfig {
  static const minGoodOqi = 75;
  static const maxGoodAverageCloudPercent = 40;
  static const minGoodContinuousMinutes = 90;

  static const minLimitedOqi = 45;
  static const maxUnavailableOqi = 44;

  static const minLimitedAverageCloudPercent = 40;
  static const maxLimitedAverageCloudPercent = 70;
  static const minUnavailableAverageCloudPercent = 70;

  static const minLimitedContinuousMinutes = 30;
  static const maxLimitedContinuousMinutes = 90;
  static const minUnavailableContinuousMinutes = 30;

  /// Score multiplier for [ImagingDifficulty.normal] targets in LIMITED nights.
  static const limitedNormalDifficultyScoreMultiplier = 0.85;
}

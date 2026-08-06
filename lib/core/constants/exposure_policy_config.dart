/// Tunable exposure-time thresholds for [ExposurePolicy].
///
/// Values are provisional and can be adjusted without changing policy logic.
abstract final class ExposurePolicyConfig {
  /// Legacy global cap kept for sites without profile context.
  static const int maxRecommendableBortle = 8;

  /// Minimum exposure at Bortle 2 (dark sky) when no profile base is used.
  static const int baseMinimumMinutes = 30;

  /// Recommended exposure at Bortle 2 (dark sky).
  static const int baseRecommendedMinutes = 90;

  /// Additional minimum minutes per Bortle step above recommended site bortle.
  static const int bortleExposureStepMinutes = 10;

  /// Additional minimum minutes per Bortle step above 2 (legacy fallback).
  static const int minimumMinutesPerBortleStep = 10;

  /// Recommended exposure multiplier relative to minimum exposure.
  static const double recommendedExposureMultiplier = 2.0;

  /// Extra multiplier applied at very light-polluted sites for galaxies.
  static const double galaxyHighBortleRecommendedMultiplier = 2.0;

  /// Default Bortle when lookup data is unavailable.
  static const int defaultBortle = 5;
}

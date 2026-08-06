/// Hard-cut thresholds for observation feasibility.
abstract final class ObservationFeasibilityConfig {
  /// Cloud coverage at or above this value is infeasible for DSO imaging.
  static const minInfeasibleCloudCoveragePercent = 80;

  /// Precipitation probability at or above this value is infeasible.
  static const minInfeasibleRainProbabilityPercent = 60.0;

  /// Visibility at or below this value (metres) is infeasible.
  static const maxInfeasibleVisibilityMeters = 3000;

  /// Wind speed at or above this value (m/s) is infeasible.
  static const minInfeasibleWindSpeedMetersPerSecond = 15.0;

  /// Minimum contiguous feasible shooting time for recommendations/scheduling.
  static const minContinuousShootingMinutes = 30;

  static const minContinuousShootingSlots =
      minContinuousShootingMinutes ~/ 10;
}

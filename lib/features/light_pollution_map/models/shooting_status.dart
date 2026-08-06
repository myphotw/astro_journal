import '../../../core/constants/observation_feasibility_config.dart';
import '../../../core/constants/observation_status_config.dart';
import '../../../data/models/observation_status.dart';
import '../../../data/models/weather_forecast_slot.dart';

/// Compact shooting recommendation for the light-pollution map weather tab.
enum ShootingStatus {
  good('🟢', '촬영하기 좋음'),
  limited('🟡', '촬영 가능'),
  notRecommended('🔴', '촬영 비추천');

  const ShootingStatus(this.emoji, this.label);

  final String emoji;
  final String label;

  String get displayText => '$emoji $label';

  static ShootingStatus fromObservationStatus(ObservationStatus status) {
    switch (status) {
      case ObservationStatus.good:
        return ShootingStatus.good;
      case ObservationStatus.limited:
        return ShootingStatus.limited;
      case ObservationStatus.unavailable:
        return ShootingStatus.notRecommended;
    }
  }

  static bool hasRainIssue(WeatherForecastSlot forecast) {
    if (forecast.rainVolumeMm != null && forecast.rainVolumeMm! > 0) {
      return true;
    }
    return forecast.rainVolumeMm == null &&
        forecast.pop >=
            ObservationFeasibilityConfig.minInfeasibleRainProbabilityPercent;
  }

  static ShootingStatus evaluate({
    required WeatherForecastSlot forecast,
    required int starCount,
  }) {
    if (hasRainIssue(forecast)) {
      return ShootingStatus.notRecommended;
    }
    if (starCount >= 3 &&
        forecast.cloudCoverage <
            ObservationStatusConfig.maxGoodAverageCloudPercent) {
      return ShootingStatus.good;
    }
    return ShootingStatus.limited;
  }
}

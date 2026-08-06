import '../../data/models/weather_forecast_slot.dart';
import '../observation_quality_service.dart';
import '../observation_score_service.dart';

/// Granular weather components for per-slot [ObservationScore].
abstract final class WeatherObservationScoreCalculator {
  static double totalScore({
    required int cloudCover,
    required int visibilityMeters,
    required int humidity,
    required double windSpeed,
    required double precipitationProbability,
    required double temperature,
    DateTime? time,
  }) {
    final slotTime = time ?? DateTime.now();
    final moon = ObservationScoreService.computeMoonInfo(slotTime);
    return const ObservationQualityService().computeSlotQuality(
      forecast: WeatherForecastSlot(
        time: slotTime,
        temperature: temperature,
        humidity: humidity,
        windSpeed: windSpeed,
        cloudCoverage: cloudCover,
        visibility: visibilityMeters,
        pop: precipitationProbability,
        description: '',
        icon: '',
      ),
      moon: moon,
    ).oqi ??
        0;
  }

  static double cloudScore(int cloudCover) {
    return ObservationQualityService.cloudQuality(cloudCover.toDouble());
  }

  static double visibilityScore(int visibilityMeters) {
    return ObservationQualityService.visibilityQuality(visibilityMeters);
  }

  static double humidityScore(int humidity, double temperature) {
    return ObservationQualityService.condensationQuality(
      temperature: temperature,
      humidity: humidity,
    );
  }

  static double windScore(double windSpeed) {
    return ObservationQualityService.windQuality(windSpeed);
  }

  static double rainScore(double precipitationProbability) {
    return ObservationQualityService.rainQuality(precipitationProbability);
  }

  static double dewScore(double temperature, int humidity) {
    return ObservationQualityService.condensationQuality(
      temperature: temperature,
      humidity: humidity,
    );
  }
}

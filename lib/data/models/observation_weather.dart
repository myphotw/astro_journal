import '../../services/observation_score_service.dart';
import '../../services/scoring/weather_observation_score.dart';
import 'weather_forecast_slot.dart';

/// Hourly weather snapshot mapped to an observation time slot.
class ObservationWeather {
  const ObservationWeather({
    required this.cloudCover,
    required this.visibility,
    required this.humidity,
    required this.windSpeed,
    required this.precipitationProbability,
    required this.dewPoint,
    required this.forecastTime,
    required this.temperature,
    required this.weatherScore,
  });

  final int cloudCover;
  final int visibility;
  final int humidity;
  final double windSpeed;
  final double precipitationProbability;
  final double dewPoint;
  final DateTime forecastTime;
  final double temperature;
  final double weatherScore;

  factory ObservationWeather.fromForecast(WeatherForecastSlot forecast) {
    final dewPoint = ObservationScoreService.dewPointCelsius(
      forecast.temperature,
      forecast.humidity,
    );
    final weatherScore = WeatherObservationScoreCalculator.totalScore(
      cloudCover: forecast.cloudCoverage,
      visibilityMeters: forecast.visibility,
      humidity: forecast.humidity,
      windSpeed: forecast.windSpeed,
      precipitationProbability: forecast.pop,
      temperature: forecast.temperature,
      time: forecast.time,
    );

    return ObservationWeather(
      cloudCover: forecast.cloudCoverage,
      visibility: forecast.visibility,
      humidity: forecast.humidity,
      windSpeed: forecast.windSpeed,
      precipitationProbability: forecast.pop,
      dewPoint: dewPoint,
      forecastTime: forecast.time,
      temperature: forecast.temperature,
      weatherScore: weatherScore,
    );
  }

  WeatherForecastSlot toForecastSlot() {
    return WeatherForecastSlot(
      time: forecastTime,
      temperature: temperature,
      humidity: humidity,
      windSpeed: windSpeed,
      cloudCoverage: cloudCover,
      visibility: visibility,
      pop: precipitationProbability,
      description: '',
      icon: '',
    );
  }

  factory ObservationWeather.fallback({
    required DateTime time,
    int cloudCover = 0,
    int visibility = 10000,
    int humidity = 50,
    double windSpeed = 0,
    double precipitationProbability = 0,
    double temperature = 10,
  }) {
    return ObservationWeather.fromForecast(
      WeatherForecastSlot(
        time: time,
        temperature: temperature,
        humidity: humidity,
        windSpeed: windSpeed,
        cloudCoverage: cloudCover,
        visibility: visibility,
        pop: precipitationProbability,
        description: '',
        icon: '',
      ),
    );
  }
}

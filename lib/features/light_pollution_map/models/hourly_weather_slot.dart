import '../../../services/observation_score_service.dart';

/// One forecast time slot for the compact hourly weather strip.
class HourlyWeatherSlot {
  const HourlyWeatherSlot({
    required this.time,
    required this.temperature,
    required this.cloudCoverage,
    required this.precipitationProbability,
    required this.windSpeed,
    required this.starCount,
    required this.weatherEmoji,
    this.weatherDescription,
  });

  final DateTime time;
  final double temperature;
  final int cloudCoverage;
  final double precipitationProbability;
  final double windSpeed;
  final int starCount;
  final String weatherEmoji;
  final String? weatherDescription;

  String get hourLabel =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  String get starsText =>
      '${'★' * starCount}${'☆' * (5 - starCount)}';

  String get weatherLabel {
    final description = weatherDescription?.trim();
    if (description != null && description.isNotEmpty) {
      return description;
    }
    return weatherEmoji;
  }

  factory HourlyWeatherSlot.fromTonightSlot(TonightObservationSlot slot) {
    final score = slot.observationScore?.round() ?? 0;
    return HourlyWeatherSlot(
      time: slot.targetTime,
      temperature: slot.forecast.temperature,
      cloudCoverage: slot.forecast.cloudCoverage,
      precipitationProbability: slot.forecast.pop,
      windSpeed: slot.forecast.windSpeed,
      starCount: ObservationScoreService.recommendationStarCount(score),
      weatherEmoji: slot.forecast.weatherEmoji,
      weatherDescription: slot.forecast.description,
    );
  }
}

import '../../data/models/object_observation_window.dart';

/// Scores weather suitability at the target's optimal astronomical slot.
class WeatherScore {
  const WeatherScore();

  double calculate({ObjectObservationWindow? window}) {
    if (window == null) return 0;
    return (window.optimalWeatherScore ?? window.bestObservationScore).clamp(
      0.0,
      100.0,
    );
  }
}

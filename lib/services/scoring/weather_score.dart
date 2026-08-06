import '../../data/models/object_observation_window.dart';

/// Scores weather suitability from feasible-slot observation quality.
class WeatherScore {
  const WeatherScore();

  double calculate({ObjectObservationWindow? window}) {
    if (window == null || window.bestObservationScore <= 0) {
      return 0;
    }
    return window.bestObservationScore.clamp(0.0, 100.0);
  }
}

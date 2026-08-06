import '../../data/models/object_observation_window.dart';

/// Scores how well a target is placed in the sky tonight.
class VisibilityScore {
  const VisibilityScore();

  double calculate({required ObjectObservationWindow window}) {
    final altitude =
        window.optimalAltitude ?? window.peakAltitude ?? window.currentAltitude;
    return _scoreAltitude(altitude);
  }

  double calculateForAltitude(double altitude) => _scoreAltitude(altitude);

  double _scoreAltitude(double altitude) {
    if (altitude < 0) return 0;
    if (altitude >= 60) return 100;
    if (altitude >= 45) return 85;
    if (altitude >= 30) return 70;
    if (altitude >= 15) return 50;
    return 25;
  }
}

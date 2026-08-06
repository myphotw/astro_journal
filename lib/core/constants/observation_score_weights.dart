/// Weight constants for per-slot observation scoring.
abstract final class ObservationScoreWeights {
  static const double altitude = 0.30;
  static const double moon = 0.25;
  static const double lightPollution = 0.20;
  static const double weather = 0.25;

  /// Site-level weights (altitude excluded, renormalized to 1.0).
  static const double siteMoon = moon / (moon + lightPollution + weather);
  static const double siteLightPollution =
      lightPollution / (moon + lightPollution + weather);
  static const double siteWeather =
      weather / (moon + lightPollution + weather);

  static const double nightAverageWeight = 0.40;
  static const double windowAverageWeight = 0.60;
}

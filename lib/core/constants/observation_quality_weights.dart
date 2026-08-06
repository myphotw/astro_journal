/// Weight constants for [ObservationQualityIndex] (OQI).
abstract final class ObservationQualityWeights {
  static const double cloud = 0.45;
  static const double rain = 0.20;
  static const double visibility = 0.15;
  static const double moon = 0.10;
  static const double wind = 0.05;
  static const double condensation = 0.05;
}

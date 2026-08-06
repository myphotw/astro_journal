/// Weight constants for scheduler target ordering.
abstract final class SchedulerPriorityWeights {
  static const double urgency = 0.35;
  static const double moon = 0.20;
  static const double lightPollution = 0.15;
  static const double observation = 0.15;
  static const double exposure = 0.10;
  static const double recommendation = 0.05;
}

import '../../../data/models/object_observation_window.dart';

/// Prioritizes targets that still need recommended integration time tonight.
class ExposurePriority {
  const ExposurePriority();

  double calculate({
    required ObjectObservationWindow window,
    required Duration recommendedExposure,
  }) {
    if (window.totalObservableMinutes <= 0) return 0;

    final ratio =
        recommendedExposure.inMinutes / window.totalObservableMinutes;
    if (ratio >= 1) return 90;
    if (ratio >= 0.75) return 70;
    if (ratio >= 0.5) return 50;
    return 30;
  }
}

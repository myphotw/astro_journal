import '../../../data/models/object_observation_window.dart';

/// Scores how urgent it is to shoot a target tonight before the window closes.
class UrgencyScore {
  const UrgencyScore();

  double calculate({
    required ObjectObservationWindow window,
    required Duration recommendedExposure,
    required DateTime referenceTime,
  }) {
    var score = 0.0;

    final remaining = window.remainingVisibleMinutes;
    if (remaining > 0) {
      score += (1 - (remaining / 480).clamp(0.0, 1.0)) * 35;
    }

    final latestStart = window.latestStartTime;
    if (latestStart != null) {
      if (!referenceTime.isBefore(latestStart)) {
        score += 35;
      } else {
        final minutesUntilLatest =
            latestStart.difference(referenceTime).inMinutes;
        if (minutesUntilLatest <= 120) {
          score += (1 - minutesUntilLatest / 120) * 20;
        }
      }
    }

    if (remaining < recommendedExposure.inMinutes) {
      score += 20;
    }

    if (window.totalObservableMinutes <= recommendedExposure.inMinutes + 30) {
      score += 10;
    }

    return score.clamp(0.0, 100.0);
  }
}

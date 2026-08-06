import '../../data/models/observation_session.dart';
import '../../data/models/recommendation_result.dart';

abstract final class ObservationSessionBuilder {
  static List<ObservationSession> buildFromResults(
    List<RecommendationResult> results,
  ) {
    final sessions = <ObservationSession>[];

    for (final result in results) {
      final window = result.observationWindow;
      if (window == null ||
          window.optimalTime == null ||
          (window.optimalAltitude == null && window.peakAltitude == null)) {
        continue;
      }

      final start = window.recommendStartTime;
      final end = window.observationEndTime;
      final best = window.optimalTime ?? window.peakAltitudeTime;
      if (start == null || end == null || best == null) continue;

      sessions.add(
        ObservationSession(
          target: result.object,
          startTime: start,
          bestTime: best,
          endTime: end,
          maxAltitude: window.optimalAltitude ?? window.peakAltitude ?? 0,
          score: result.score,
          result: result,
        ),
      );
    }

    sessions.sort((a, b) {
      final cmp = a.bestTime.compareTo(b.bestTime);
      if (cmp != 0) return cmp;
      return a.startTime.compareTo(b.startTime);
    });

    return sessions;
  }
}

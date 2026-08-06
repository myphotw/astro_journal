import '../../core/constants/recommendation_catalog_priority.dart';
import '../../core/constants/recommendation_mixed_priority.dart';
import '../../core/constants/recommendation_priority_mode.dart';
import '../../data/models/object_observation_window.dart';
import '../../data/models/scored_observation_target.dart';

abstract final class RecommendationCandidateSorter {
  static void sort(
    List<ScoredObservationTarget> candidates,
    RecommendationPriorityMode mode,
  ) {
    candidates.sort((a, b) => _compare(a, b, mode));
  }

  static int _compare(
    ScoredObservationTarget a,
    ScoredObservationTarget b,
    RecommendationPriorityMode mode,
  ) {
    return switch (mode) {
      RecommendationPriorityMode.uncapturedFirst =>
        _compareUncapturedFirst(a, b),
      RecommendationPriorityMode.scoreFirst => _compareScoreFirst(a, b),
      RecommendationPriorityMode.mixed => _compareMixed(a, b),
    };
  }

  static int _compareUncapturedFirst(
    ScoredObservationTarget a,
    ScoredObservationTarget b,
  ) {
    final uncaptured = _compareUncaptured(a, b);
    if (uncaptured != 0) return uncaptured;

    final score = b.score.compareTo(a.score);
    if (score != 0) return score;

    return _compareSharedTail(a, b);
  }

  static int _compareScoreFirst(
    ScoredObservationTarget a,
    ScoredObservationTarget b,
  ) {
    final score = b.score.compareTo(a.score);
    if (score != 0) return score;

    final uncaptured = _compareUncaptured(a, b);
    if (uncaptured != 0) return uncaptured;

    return _compareSharedTail(a, b);
  }

  static int _compareMixed(ScoredObservationTarget a, ScoredObservationTarget b) {
    final effective = _effectiveScore(b).compareTo(_effectiveScore(a));
    if (effective != 0) return effective;

    final score = b.score.compareTo(a.score);
    if (score != 0) return score;

    return _compareSharedTail(a, b);
  }

  static double _effectiveScore(ScoredObservationTarget candidate) {
    final bonus = candidate.object.captured
        ? 0.0
        : RecommendationMixedPriority.uncapturedBonus;
    return candidate.score + bonus;
  }

  static int _compareUncaptured(
    ScoredObservationTarget a,
    ScoredObservationTarget b,
  ) {
    if (a.object.captured == b.object.captured) return 0;
    return a.object.captured ? 1 : -1;
  }

  static int _compareSharedTail(
    ScoredObservationTarget a,
    ScoredObservationTarget b,
  ) {
    final moonCmp = b.moonSeparation.compareTo(a.moonSeparation);
    if (moonCmp != 0) return moonCmp;

    final aStart = _shootingStartTime(a.window);
    final bStart = _shootingStartTime(b.window);
    if (aStart != null && bStart != null) {
      final cmp = aStart.compareTo(bStart);
      if (cmp != 0) return cmp;
    } else if (aStart != null) {
      return -1;
    } else if (bStart != null) {
      return 1;
    }

    final aAlt = a.window.peakAltitude ?? 0;
    final bAlt = b.window.peakAltitude ?? 0;
    final altCmp = bAlt.compareTo(aAlt);
    if (altCmp != 0) return altCmp;

    final catalogCmp = RecommendationCatalogPriority.rank(a.object.catalog)
        .compareTo(RecommendationCatalogPriority.rank(b.object.catalog));
    if (catalogCmp != 0) return catalogCmp;

    return a.object.displayName.compareTo(b.object.displayName);
  }

  static DateTime? _shootingStartTime(ObjectObservationWindow window) {
    return window.optimalTime ?? window.recommendStartTime;
  }
}

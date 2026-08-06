import 'catalog_object.dart';
import 'object_imaging_profile.dart';
import 'object_observation_window.dart';

/// A catalog target that passed filtering and scoring for tonight's session.
class ScoredObservationTarget {
  const ScoredObservationTarget({
    required this.object,
    required this.window,
    required this.profile,
    required this.score,
    required this.moonSeparation,
    required this.minimumExposure,
    required this.recommendedExposure,
    this.schedulerPriority = 0,
    this.urgencyScore = 0,
  });

  final CatalogObject object;
  final ObjectObservationWindow window;
  final ObjectImagingProfile profile;
  final double score;
  final double moonSeparation;
  final Duration minimumExposure;
  final Duration recommendedExposure;
  final double schedulerPriority;
  final double urgencyScore;

  ScoredObservationTarget copyWith({
    ObjectObservationWindow? window,
    double? schedulerPriority,
    double? urgencyScore,
  }) {
    return ScoredObservationTarget(
      object: object,
      window: window ?? this.window,
      profile: profile,
      score: score,
      moonSeparation: moonSeparation,
      minimumExposure: minimumExposure,
      recommendedExposure: recommendedExposure,
      schedulerPriority: schedulerPriority ?? this.schedulerPriority,
      urgencyScore: urgencyScore ?? this.urgencyScore,
    );
  }
}

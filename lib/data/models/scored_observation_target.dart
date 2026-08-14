import 'catalog_object.dart';
import 'object_imaging_profile.dart';
import 'object_observation_window.dart';
import 'imaging_suitability_assessment.dart';

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
    this.imagingAssessment,
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
  final ImagingSuitabilityAssessment? imagingAssessment;

  ScoredObservationTarget copyWith({
    ObjectObservationWindow? window,
    double? score,
    double? schedulerPriority,
    double? urgencyScore,
    ImagingSuitabilityAssessment? imagingAssessment,
  }) {
    return ScoredObservationTarget(
      object: object,
      window: window ?? this.window,
      profile: profile,
      score: score ?? this.score,
      moonSeparation: moonSeparation,
      minimumExposure: minimumExposure,
      recommendedExposure: recommendedExposure,
      schedulerPriority: schedulerPriority ?? this.schedulerPriority,
      urgencyScore: urgencyScore ?? this.urgencyScore,
      imagingAssessment: imagingAssessment ?? this.imagingAssessment,
    );
  }
}

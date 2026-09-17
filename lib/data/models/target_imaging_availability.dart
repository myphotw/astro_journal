import 'catalog_object.dart';
import 'object_observation_window.dart';
import 'recommendation_result.dart';
import 'shooting_time_window.dart';

enum TargetImagingAvailabilityState {
  noObservableWindow,
  shortWindow,
  multiNightAccumulation,
  sufficientWindow,
}

/// A site-specific, reusable availability projection for one catalog target.
///
/// It deliberately retains the [RecommendationResult] produced by the shared
/// recommendation engine so mobile and future desktop clients present the
/// same visibility and imaging policy.
class TargetImagingAvailability {
  const TargetImagingAvailability({
    required this.object,
    required this.referenceDate,
    required this.isAvailableTonight,
    this.nightStart,
    this.nightEnd,
    this.recommendation,
    this.primaryReason,
    this.tomorrow,
    this.observableSeasonLabel,
    this.optimalSeasonLabel,
    this.state,
    this.usableWindow,
    this.usableMinutes,
    this.minimumMinutes,
    this.recommendedMinutes,
    this.hasFramingReference = false,
    this.framingMatched = false,
    this.sameFramingMinutes,
    this.weatherAdvisory,
  });

  final CatalogObject object;
  final DateTime referenceDate;
  final bool isAvailableTonight;
  final DateTime? nightStart;
  final DateTime? nightEnd;
  final RecommendationResult? recommendation;
  final String? primaryReason;

  /// Tomorrow uses the same astronomical pipeline without weather inputs.
  final TargetImagingAvailability? tomorrow;
  final String? observableSeasonLabel;
  final String? optimalSeasonLabel;
  final TargetImagingAvailabilityState? state;

  /// Exclusive-end interval after equipment/HA and optional same-framing
  /// constraints are intersected with the astronomical observation window.
  final ShootingTimeWindow? usableWindow;
  final int? usableMinutes;
  final int? minimumMinutes;
  final int? recommendedMinutes;
  final bool hasFramingReference;
  final bool framingMatched;
  final int? sameFramingMinutes;
  final String? weatherAdvisory;

  ObjectObservationWindow? get window => recommendation?.observationWindow;

  bool get isDifficultTonight =>
      isAvailableTonight &&
      (recommendation?.imagingAssessment?.quality.index ?? 2) <= 1;

  TargetImagingAvailabilityState get effectiveState =>
      state ??
      (isAvailableTonight
          ? TargetImagingAvailabilityState.sufficientWindow
          : TargetImagingAvailabilityState.noObservableWindow);

  String get tonightStatusLabel {
    return switch (effectiveState) {
      TargetImagingAvailabilityState.noObservableWindow => '관측 가능 구간 없음',
      TargetImagingAvailabilityState.shortWindow => '촬영 가능 시간이 짧음',
      TargetImagingAvailabilityState.multiNightAccumulation => '동일구도 누적 가능',
      TargetImagingAvailabilityState.sufficientWindow => '최소 촬영시간 충족',
    };
  }
}

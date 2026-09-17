import 'multi_night_framing_reference.dart';
import 'shooting_time_window.dart';

enum ShootingSuitabilityRejection {
  equipmentTooSmall,
  framingUnavailable,
  noObservationWindow,
  noOptimalOverlap,
  insufficientDuration,
}

class ShootingSuitability {
  const ShootingSuitability({
    required this.eligible,
    required this.observationWindow,
    required this.optimalWindow,
    required this.recommendedWindow,
    this.rejection,
    this.rejectionReason,
    this.hasFramingReference = false,
    this.framingAvailable = false,
    this.framingWindow,
    this.referenceBranch,
  });

  final bool eligible;
  final ShootingSuitabilityRejection? rejection;
  final String? rejectionReason;
  final ShootingTimeWindow? observationWindow;
  final ShootingTimeWindow? optimalWindow;
  final ShootingTimeWindow? framingWindow;
  final ShootingTimeWindow? recommendedWindow;
  final bool hasFramingReference;
  final bool framingAvailable;
  final MultiNightFramingBranch? referenceBranch;

  bool get automaticEligible =>
      eligible &&
      recommendedWindow != null &&
      rejection != ShootingSuitabilityRejection.noOptimalOverlap &&
      rejection != ShootingSuitabilityRejection.insufficientDuration;

  bool get hasUsableWindow => recommendedWindow?.isValid ?? false;

  bool get manualMultiNightEligible =>
      eligible && hasFramingReference && framingAvailable && hasUsableWindow;

  bool selectedWindowIsObservable(ShootingTimeWindow selected) =>
      observationWindow?.containsWindow(selected) ?? false;

  bool selectedWindowMatchesFraming(ShootingTimeWindow selected) =>
      !hasFramingReference ||
      (framingAvailable && (framingWindow?.containsWindow(selected) ?? false));

  bool selectedWindowIsOptimal(ShootingTimeWindow selected) =>
      optimalWindow?.containsWindow(selected) ?? false;

  bool selectedWindowOverlapsOptimal(ShootingTimeWindow selected) =>
      optimalWindow?.overlaps(selected) ?? false;
}

class ManualShootingWindowProposal {
  const ManualShootingWindowProposal({
    required this.searchWindow,
    required this.usableWindow,
    required this.proposedWindow,
    required this.minimumDuration,
    required this.recommendedDuration,
    required this.hasFramingReference,
    required this.framingMatched,
  });

  final ShootingTimeWindow searchWindow;
  final ShootingTimeWindow usableWindow;
  final ShootingTimeWindow proposedWindow;
  final Duration minimumDuration;
  final Duration recommendedDuration;
  final bool hasFramingReference;
  final bool framingMatched;

  Duration get proposedDuration => proposedWindow.duration;
  bool get isBelowMinimumDuration => proposedDuration < minimumDuration;
  bool get isBelowRecommendedDuration => proposedDuration < recommendedDuration;
  bool get isMultiNightAccumulationOpportunity =>
      hasFramingReference && framingMatched && isBelowMinimumDuration;
}

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

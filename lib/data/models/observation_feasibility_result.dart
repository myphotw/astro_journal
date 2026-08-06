import 'observation_feasibility_reason.dart';

/// Result of [ObservationFeasibilityPolicy] for a single slot.
class ObservationFeasibilityResult {
  const ObservationFeasibilityResult({
    required this.canObserve,
    this.reason,
    this.failedConditions = const [],
  });

  const ObservationFeasibilityResult.observable()
      : canObserve = true,
        reason = null,
        failedConditions = const [];

  const ObservationFeasibilityResult.infeasible({
    required this.reason,
    required this.failedConditions,
  }) : canObserve = false;

  final bool canObserve;
  final String? reason;
  final List<ObservationFeasibilityReason> failedConditions;
}

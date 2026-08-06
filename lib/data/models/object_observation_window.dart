/// Time-based observation window for a recommended target.
class ObjectObservationWindow {
  const ObjectObservationWindow({
    required this.currentAltitude,
    required this.currentAzimuth,
    required this.isCurrentlyVisible,
    this.recommendStartTime,
    this.optimalStartTime,
    this.optimalEndTime,
    this.optimalTime,
    this.optimalAltitude,
    this.peakAltitude,
    this.peakAltitudeTime,
    this.meridianPassTime,
    this.observationEndTime,
    this.totalObservableMinutes = 0,
    this.remainingVisibleMinutes = 0,
    this.latestStartTime,
    this.moonSafeMinutes = 0,
    this.bestObservationScore = 0,
    this.urgencyScore = 0,
    this.schedulerPriority = 0,
    this.slotObservationScores = const {},
    this.feasibleWindowSummary,
    this.optimalFeasibleCloudCoverage,
    this.optimalFeasibleWindSpeed,
  });

  final double currentAltitude;
  final double currentAzimuth;
  final bool isCurrentlyVisible;
  final DateTime? recommendStartTime;
  final DateTime? optimalStartTime;
  final DateTime? optimalEndTime;
  final DateTime? optimalTime;
  final double? optimalAltitude;
  final double? peakAltitude;
  final DateTime? peakAltitudeTime;
  final DateTime? meridianPassTime;
  final DateTime? observationEndTime;
  final int totalObservableMinutes;
  final int remainingVisibleMinutes;
  final DateTime? latestStartTime;
  final int moonSafeMinutes;
  final double bestObservationScore;
  final double urgencyScore;
  final double schedulerPriority;
  final Map<DateTime, double> slotObservationScores;

  /// User-facing summary, e.g. "오늘 밤 22:00~01:00만 촬영 가능".
  final String? feasibleWindowSummary;

  /// Slot weather at the optimal feasible shooting time (not nightly average).
  final int? optimalFeasibleCloudCoverage;
  final double? optimalFeasibleWindSpeed;

  String get totalObservableLabel {
    final h = totalObservableMinutes ~/ 60;
    final m = totalObservableMinutes % 60;
    if (h == 0) return '$m분';
    if (m == 0) return '$h시간';
    return '$h시간 $m분';
  }

  ObjectObservationWindow copyWith({
    double? urgencyScore,
    double? schedulerPriority,
  }) {
    return ObjectObservationWindow(
      currentAltitude: currentAltitude,
      currentAzimuth: currentAzimuth,
      isCurrentlyVisible: isCurrentlyVisible,
      recommendStartTime: recommendStartTime,
      optimalStartTime: optimalStartTime,
      optimalEndTime: optimalEndTime,
      optimalTime: optimalTime,
      optimalAltitude: optimalAltitude,
      peakAltitude: peakAltitude,
      peakAltitudeTime: peakAltitudeTime,
      meridianPassTime: meridianPassTime,
      observationEndTime: observationEndTime,
      totalObservableMinutes: totalObservableMinutes,
      remainingVisibleMinutes: remainingVisibleMinutes,
      latestStartTime: latestStartTime,
      moonSafeMinutes: moonSafeMinutes,
      bestObservationScore: bestObservationScore,
      urgencyScore: urgencyScore ?? this.urgencyScore,
      schedulerPriority: schedulerPriority ?? this.schedulerPriority,
      slotObservationScores: slotObservationScores,
      feasibleWindowSummary: feasibleWindowSummary,
      optimalFeasibleCloudCoverage: optimalFeasibleCloudCoverage,
      optimalFeasibleWindSpeed: optimalFeasibleWindSpeed,
    );
  }
}

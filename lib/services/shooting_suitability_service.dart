import '../data/models/scored_observation_target.dart';
import '../data/models/shooting_suitability.dart';
import '../data/models/shooting_time_window.dart';
import 'multi_night_framing_match_service.dart';

/// Combines existing recommendation, equipment, and framing outputs without
/// introducing a second astronomy calculation path.
class ShootingSuitabilityService {
  const ShootingSuitabilityService();

  ShootingSuitability evaluate({
    required ScoredObservationTarget target,
    bool hasFramingReference = false,
    MultiNightFramingMatchResult? framingMatch,
  }) {
    final observation = _observationWindow(target);
    if (observation == null) {
      return const ShootingSuitability(
        eligible: false,
        observationWindow: null,
        optimalWindow: null,
        recommendedWindow: null,
        rejection: ShootingSuitabilityRejection.noObservationWindow,
        rejectionReason: '관측 가능한 시간 범위를 확인할 수 없습니다.',
      );
    }

    if (target.imagingAssessment?.isExtremelyTiny ?? false) {
      return ShootingSuitability(
        eligible: false,
        observationWindow: observation,
        optimalWindow: _optimalWindow(target),
        recommendedWindow: null,
        rejection: ShootingSuitabilityRejection.equipmentTooSmall,
        rejectionReason: '현재 장비에서는 대상이 너무 작아 의미 있는 결과를 얻기 어렵습니다.',
      );
    }

    ShootingTimeWindow? framingWindow;
    if (hasFramingReference) {
      final rangeStart = framingMatch?.rangeStart;
      final rangeEnd = framingMatch?.rangeEnd;
      if (framingMatch == null ||
          !framingMatch.isAvailable ||
          rangeStart == null ||
          rangeEnd == null ||
          !rangeEnd.isAfter(rangeStart)) {
        return ShootingSuitability(
          eligible: false,
          observationWindow: observation,
          optimalWindow: _optimalWindow(target),
          recommendedWindow: null,
          hasFramingReference: true,
          framingAvailable: false,
          referenceBranch: framingMatch?.reference.referenceBranch,
          rejection: ShootingSuitabilityRejection.framingUnavailable,
          rejectionReason:
              framingMatch?.unavailableReason ??
              '오늘은 기준 구도와 같은 구도를 재현하기 어렵습니다.',
        );
      }
      framingWindow = ShootingTimeWindow(start: rangeStart, end: rangeEnd);
      if (observation.intersect(framingWindow) == null) {
        return ShootingSuitability(
          eligible: false,
          observationWindow: observation,
          optimalWindow: _optimalWindow(target),
          framingWindow: framingWindow,
          recommendedWindow: null,
          hasFramingReference: true,
          framingAvailable: false,
          referenceBranch: framingMatch.reference.referenceBranch,
          rejection: ShootingSuitabilityRejection.framingUnavailable,
          rejectionReason: '오늘 관측 가능 시간에는 기준 구도와 같은 구도를 재현하기 어렵습니다.',
        );
      }
    }

    final optimal = _optimalWindow(target) ?? observation;
    var recommended = observation.intersect(optimal);
    if (recommended == null) {
      return ShootingSuitability(
        eligible: true,
        observationWindow: observation,
        optimalWindow: optimal,
        framingWindow: framingWindow,
        recommendedWindow: null,
        hasFramingReference: hasFramingReference,
        framingAvailable: !hasFramingReference || framingMatch!.isAvailable,
        referenceBranch: framingMatch?.reference.referenceBranch,
        rejection: ShootingSuitabilityRejection.noOptimalOverlap,
        rejectionReason: '관측 가능 시간과 최적 촬영 구간이 겹치지 않습니다.',
      );
    }
    if (framingWindow != null) {
      recommended = recommended.intersect(framingWindow);
    }
    if (recommended == null) {
      return ShootingSuitability(
        eligible: true,
        observationWindow: observation,
        optimalWindow: optimal,
        framingWindow: framingWindow,
        recommendedWindow: null,
        hasFramingReference: true,
        framingAvailable: true,
        referenceBranch: framingMatch?.reference.referenceBranch,
        rejection: ShootingSuitabilityRejection.noOptimalOverlap,
        rejectionReason: '기준 구도 가능 범위와 최적 촬영 구간이 겹치지 않습니다.',
      );
    }

    if (recommended.duration < target.minimumExposure) {
      return ShootingSuitability(
        eligible: true,
        observationWindow: observation,
        optimalWindow: optimal,
        framingWindow: framingWindow,
        recommendedWindow: recommended,
        hasFramingReference: hasFramingReference,
        framingAvailable: !hasFramingReference || framingMatch!.isAvailable,
        referenceBranch: framingMatch?.reference.referenceBranch,
        rejection: ShootingSuitabilityRejection.insufficientDuration,
        rejectionReason: '품질 우선 구간이 최소 실용 촬영시간보다 짧습니다.',
      );
    }

    return ShootingSuitability(
      eligible: true,
      observationWindow: observation,
      optimalWindow: optimal,
      framingWindow: framingWindow,
      recommendedWindow: recommended,
      hasFramingReference: hasFramingReference,
      framingAvailable: !hasFramingReference || framingMatch!.isAvailable,
      referenceBranch: framingMatch?.reference.referenceBranch,
    );
  }

  ShootingTimeWindow? _observationWindow(ScoredObservationTarget target) {
    final start = target.window.recommendStartTime;
    final end = target.window.observationEndTime;
    if (start == null || end == null || !end.isAfter(start)) return null;
    return ShootingTimeWindow(start: start, end: end);
  }

  ShootingTimeWindow? _optimalWindow(ScoredObservationTarget target) {
    final preferred = target.imagingAssessment?.preferredHaWindow;
    final preferredStart = preferred?.todayStartTime;
    final preferredEnd = preferred?.todayEndTime;
    if (preferredStart != null &&
        preferredEnd != null &&
        preferredEnd.isAfter(preferredStart)) {
      return ShootingTimeWindow(start: preferredStart, end: preferredEnd);
    }

    final start = target.window.optimalStartTime;
    final end = target.window.optimalEndTime;
    if (start == null || end == null || !end.isAfter(start)) return null;
    return ShootingTimeWindow(start: start, end: end);
  }
}

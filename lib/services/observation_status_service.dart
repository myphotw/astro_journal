import '../core/constants/observation_status_config.dart';
import '../data/models/observation_context.dart';
import '../data/models/observation_status.dart';
import 'observation_feasibility_policy.dart';
import 'observation_score_service.dart';
import 'rain_observation_policy.dart';
import 'recommendation/feasible_slot_continuity.dart';

class ObservationStatusResult {
  const ObservationStatusResult({
    required this.status,
    required this.oqi,
    required this.averageCloudCoverage,
    required this.longestContinuousMinutes,
    this.primaryReason,
    this.userMessage,
  });

  final ObservationStatus status;
  final double oqi;
  final double averageCloudCoverage;
  final int longestContinuousMinutes;
  final String? primaryReason;
  final String? userMessage;
}

/// SSOT for tonight's [ObservationStatus] from site slot analysis.
class ObservationStatusService {
  const ObservationStatusService({
    RainObservationPolicy? rainObservationPolicy,
  }) : _rainObservationPolicy =
            rainObservationPolicy ?? const RainObservationPolicy();

  final RainObservationPolicy _rainObservationPolicy;

  ObservationStatusResult evaluate({
    required ObservationContext context,
    TonightObservationSummary? summary,
  }) {
    final rainResult = _rainObservationPolicy.evaluate(
      observationStart: context.observationStart,
      observationEnd: context.observationEnd,
      forecasts: context.forecasts,
    );
    if (rainResult.isBlocked) {
      return _unavailable(
        oqi: 0,
        averageCloudCoverage: context.cloudCover.toDouble(),
        longestContinuousMinutes: 0,
        primaryReason: rainResult.primaryReason,
        userMessage: rainResult.userMessage,
      );
    }

    final feasibleStarts = context.siteSlotFeasibility.entries
        .where((entry) => entry.value.canObserve)
        .map((entry) => entry.key)
        .toList();

    if (feasibleStarts.isEmpty) {
      return _unavailable(
        oqi: 0,
        averageCloudCoverage: _averageCloud(context, feasibleStarts),
        longestContinuousMinutes: 0,
        primaryReason: _feasibilityPrimaryReason(context),
        userMessage: _feasibilityUserMessage(context),
      );
    }

    final longestContinuous =
        FeasibleSlotContinuity.longestContiguousMinutes(feasibleStarts);
    final averageCloud = _averageCloud(context, feasibleStarts);
    final oqi = _resolveOqi(context, feasibleStarts, summary);

    if (oqi <= ObservationStatusConfig.maxUnavailableOqi) {
      return _unavailable(
        oqi: oqi,
        averageCloudCoverage: averageCloud,
        longestContinuousMinutes: longestContinuous,
        primaryReason: '관측 지수 ${oqi.round()}점',
        userMessage: '관측 조건이 매우 좋지 않습니다.',
      );
    }

    if (averageCloud >= ObservationStatusConfig.minUnavailableAverageCloudPercent) {
      return _unavailable(
        oqi: oqi,
        averageCloudCoverage: averageCloud,
        longestContinuousMinutes: longestContinuous,
        primaryReason: '평균 구름 ${averageCloud.round()}%',
        userMessage: '구름이 너무 많습니다.',
      );
    }

    if (longestContinuous <
        ObservationStatusConfig.minUnavailableContinuousMinutes) {
      return _unavailable(
        oqi: oqi,
        averageCloudCoverage: averageCloud,
        longestContinuousMinutes: longestContinuous,
        primaryReason: '연속 촬영 가능 $longestContinuous분',
        userMessage: '촬영 가능한 연속 시간이 부족합니다.',
      );
    }

    if (oqi >= ObservationStatusConfig.minGoodOqi &&
        averageCloud < ObservationStatusConfig.maxGoodAverageCloudPercent &&
        longestContinuous >= ObservationStatusConfig.minGoodContinuousMinutes) {
      return ObservationStatusResult(
        status: ObservationStatus.good,
        oqi: oqi,
        averageCloudCoverage: averageCloud,
        longestContinuousMinutes: longestContinuous,
      );
    }

    return ObservationStatusResult(
      status: ObservationStatus.limited,
      oqi: oqi,
      averageCloudCoverage: averageCloud,
      longestContinuousMinutes: longestContinuous,
    );
  }

  static double _resolveOqi(
    ObservationContext context,
    List<DateTime> feasibleStarts,
    TonightObservationSummary? summary,
  ) {
    if (summary != null && !summary.isObservationFeasible) {
      return 0;
    }
    if (summary != null) {
      return summary.finalScore.toDouble();
    }

    final scores = feasibleStarts
        .map((start) => context.siteSlotScores[start])
        .whereType<double>()
        .toList();
    if (scores.isEmpty) {
      return ObservationScoreService.siteObservationScoreNeutral;
    }
    return scores.reduce((a, b) => a + b) / scores.length;
  }

  static double _averageCloud(
    ObservationContext context,
    Iterable<DateTime> feasibleStarts,
  ) {
    final starts = feasibleStarts.toList();
    if (starts.isEmpty) {
      return context.cloudCover.toDouble();
    }

    var sum = 0.0;
    for (final start in starts) {
      sum += context.sessionWeather?.weatherAt(start).cloudCover.toDouble() ??
          context.cloudCover.toDouble();
    }
    return sum / starts.length;
  }

  static String? _feasibilityPrimaryReason(ObservationContext context) {
    if (context.siteSlotFeasibility.isEmpty) return null;
    return ObservationFeasibilityPolicy.aggregatePrimaryReason(
      results: context.siteSlotFeasibility.values,
    );
  }

  static String? _feasibilityUserMessage(ObservationContext context) {
    final reason = _feasibilityPrimaryReason(context);
    if (reason == null) {
      return '오늘 밤은 촬영 가능한 시간이 없습니다.';
    }
    if (reason.contains('구름')) return '구름이 너무 많습니다.';
    if (reason.contains('강수량') || reason == RainObservationPolicy.reasonRain) {
      return RainObservationPolicy.rainUnavailableMessage;
    }
    if (reason.contains('강수')) return RainObservationPolicy.rainUnavailableMessage;
    if (reason.contains('가시거리')) return '가시거리가 부족합니다.';
    if (reason.contains('풍속')) return '바람이 너무 강합니다.';
    return reason;
  }

  ObservationStatusResult _unavailable({
    required double oqi,
    required double averageCloudCoverage,
    required int longestContinuousMinutes,
    String? primaryReason,
    String? userMessage,
  }) {
    return ObservationStatusResult(
      status: ObservationStatus.unavailable,
      oqi: oqi,
      averageCloudCoverage: averageCloudCoverage,
      longestContinuousMinutes: longestContinuousMinutes,
      primaryReason: primaryReason,
      userMessage: userMessage ?? ObservationStatus.unavailable.headline,
    );
  }
}

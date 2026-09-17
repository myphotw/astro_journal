import '../core/constants/observation_feasibility_config.dart';
import '../data/models/object_imaging_profile.dart';
import '../data/models/observation_context.dart';
import '../data/models/observation_feasibility_reason.dart';
import '../data/models/observation_feasibility_result.dart';
import '../data/models/weather_forecast_slot.dart';
import 'exposure_policy.dart';
import 'recommendation_settings_service.dart';

/// Single source of truth for whether a slot can be used for imaging.
class ObservationFeasibilityPolicy {
  const ObservationFeasibilityPolicy({
    ExposurePolicy? exposurePolicy,
  }) : _exposurePolicy = exposurePolicy ?? const ExposurePolicy();

  final ExposurePolicy _exposurePolicy;

  ObservationFeasibilityResult evaluateSiteSlot({
    required WeatherForecastSlot forecast,
  }) {
    return _evaluateWeather(forecast);
  }

  ObservationFeasibilityResult evaluateTargetSlot({
    required ObservationContext context,
    required WeatherForecastSlot forecast,
    required RecommendationSettings settings,
    required ObjectImagingProfile profile,
    required double altitude,
    required double azimuth,
  }) {
    final failed = <ObservationFeasibilityReason>[];

    failed.addAll(_weatherFailures(forecast));

    if (altitude < 0) {
      failed.add(ObservationFeasibilityReason.belowHorizon);
    } else {
      if (altitude < settings.minAltitude) {
        failed.add(ObservationFeasibilityReason.belowMinAltitude);
      }
      if (altitude > settings.maxAltitude) {
        failed.add(ObservationFeasibilityReason.aboveMaxAltitude);
      }
    }

    if (!settings.isAzimuthInRange(azimuth)) {
      failed.add(ObservationFeasibilityReason.outsideAzimuth);
    }

    if (!_exposurePolicy.isRecommended(
      bortle: context.bortle,
      brightness: context.brightness,
      profile: profile,
    )) {
      failed.add(ObservationFeasibilityReason.lightPollution);
    }

    if (failed.isEmpty) {
      return const ObservationFeasibilityResult.observable();
    }

    final primary = failed.first;
    return ObservationFeasibilityResult.infeasible(
      reason: formatReason(primary, forecast: forecast),
      failedConditions: failed,
    );
  }

  ObservationFeasibilityResult _evaluateWeather(WeatherForecastSlot forecast) {
    final failed = _weatherFailures(forecast);
    if (failed.isEmpty) {
      return const ObservationFeasibilityResult.observable();
    }

    final primary = failed.first;
    return ObservationFeasibilityResult.infeasible(
      reason: formatReason(primary, forecast: forecast),
      failedConditions: failed,
    );
  }

  List<ObservationFeasibilityReason> _weatherFailures(
    WeatherForecastSlot forecast,
  ) {
    final failed = <ObservationFeasibilityReason>[];

    if (forecast.rainVolumeMm != null && forecast.rainVolumeMm! > 0) {
      failed.add(ObservationFeasibilityReason.rainVolume);
    } else if (forecast.rainVolumeMm == null &&
        forecast.pop >=
            ObservationFeasibilityConfig.minInfeasibleRainProbabilityPercent) {
      failed.add(ObservationFeasibilityReason.rainProbability);
    }

    if (forecast.cloudCoverage >=
        ObservationFeasibilityConfig.minInfeasibleCloudCoveragePercent) {
      failed.add(ObservationFeasibilityReason.cloudTooHigh);
    }
    if (forecast.visibility <=
        ObservationFeasibilityConfig.maxInfeasibleVisibilityMeters) {
      failed.add(ObservationFeasibilityReason.visibilityTooLow);
    }
    if (forecast.windSpeed >=
        ObservationFeasibilityConfig.minInfeasibleWindSpeedMetersPerSecond) {
      failed.add(ObservationFeasibilityReason.windTooStrong);
    }

    return failed;
  }

  static String formatReason(
    ObservationFeasibilityReason reason, {
    WeatherForecastSlot? forecast,
    int? representativeCloudCoverage,
  }) {
    return switch (reason) {
      ObservationFeasibilityReason.rainVolume =>
        forecast?.rainVolumeMm == null
            ? '강수가 예보됨'
            : '강수량 ${forecast!.rainVolumeMm!.toStringAsFixed(1)}mm',
      ObservationFeasibilityReason.cloudTooHigh =>
        representativeCloudCoverage != null
            ? '구름량 $representativeCloudCoverage%'
            : forecast != null
            ? '구름량 ${forecast.cloudCoverage}%'
            : '구름량이 높음',
      ObservationFeasibilityReason.rainProbability =>
        forecast == null
            ? '강수 확률이 높음'
            : '강수 확률 ${forecast.pop.round()}%',
      ObservationFeasibilityReason.visibilityTooLow =>
        forecast == null
            ? '가시거리가 낮음'
            : '가시거리 ${(forecast.visibility / 1000).toStringAsFixed(1)}km',
      ObservationFeasibilityReason.windTooStrong =>
        forecast == null
            ? '바람이 강함'
            : '풍속 ${forecast.windSpeed.toStringAsFixed(1)}m/s',
      ObservationFeasibilityReason.belowMinAltitude => reason.label,
      ObservationFeasibilityReason.aboveMaxAltitude => reason.label,
      ObservationFeasibilityReason.outsideAzimuth => reason.label,
      ObservationFeasibilityReason.lightPollution => reason.label,
      ObservationFeasibilityReason.belowHorizon => reason.label,
    };
  }

  static String? aggregatePrimaryReason({
    required Iterable<ObservationFeasibilityResult> results,
    WeatherForecastSlot? sampleForecast,
    int? representativeCloudCoverage,
  }) {
    final infeasible = results.where((r) => !r.canObserve).toList();
    if (infeasible.isEmpty) return null;

    const weatherPriority = [
      ObservationFeasibilityReason.rainVolume,
      ObservationFeasibilityReason.rainProbability,
      ObservationFeasibilityReason.cloudTooHigh,
      ObservationFeasibilityReason.visibilityTooLow,
      ObservationFeasibilityReason.windTooStrong,
    ];

    final counts = <ObservationFeasibilityReason, int>{};
    for (final result in infeasible) {
      for (final reason in result.failedConditions) {
        counts[reason] = (counts[reason] ?? 0) + 1;
      }
    }

    for (final reason in weatherPriority) {
      if ((counts[reason] ?? 0) > 0) {
        return formatReason(
          reason,
          forecast: sampleForecast,
          representativeCloudCoverage: representativeCloudCoverage,
        );
      }
    }

    final top = counts.entries.reduce(
      (a, b) => a.value >= b.value ? a : b,
    );
    return formatReason(
      top.key,
      forecast: sampleForecast,
      representativeCloudCoverage: representativeCloudCoverage,
    );
  }

  static List<String> buildWeatherExclusionMessages({
    required Iterable<ObservationFeasibilityResult> results,
    WeatherForecastSlot? sampleForecast,
    int? representativeCloudCoverage,
  }) {
    final primary = aggregatePrimaryReason(
      results: results,
      sampleForecast: sampleForecast,
      representativeCloudCoverage: representativeCloudCoverage,
    );
    if (primary == null) {
      return const ['조건을 만족하는 추천 대상이 없습니다'];
    }
    return [
      '오늘 밤은 촬영 가능한 시간이 없습니다.',
      '대표 원인: $primary',
    ];
  }

  static String? buildWeatherAdvisory({
    required Iterable<ObservationFeasibilityResult> results,
    WeatherForecastSlot? sampleForecast,
    int? representativeCloudCoverage,
  }) {
    final primary = aggregatePrimaryReason(
      results: results,
      sampleForecast: sampleForecast,
      representativeCloudCoverage: representativeCloudCoverage,
    );
    if (primary == null) return null;
    if (primary == '구름량이 높음') {
      return '구름량이 높게 예보되었습니다. 실제 하늘 상태를 확인해 주세요.';
    }
    return '$primary 예보가 있습니다. 실제 하늘 상태를 확인해 주세요.';
  }

  static bool hasAnyFeasibleSiteSlot(
    Map<DateTime, ObservationFeasibilityResult> siteSlotFeasibility,
  ) {
    return siteSlotFeasibility.values.any((result) => result.canObserve);
  }
}

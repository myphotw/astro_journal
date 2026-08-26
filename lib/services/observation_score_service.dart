import 'dart:math' as math;
import 'dart:ui' show Color;

import '../core/constants/observation_score_weights.dart';
import '../core/theme/app_colors.dart';
import '../data/models/catalog_object.dart';
import '../data/models/object_imaging_profile.dart';
import '../data/models/observation_context.dart';
import '../data/models/observation_feasibility_result.dart';
import '../data/models/observation_quality_index.dart';
import '../data/models/observation_score_contribution.dart';
import '../data/models/observation_stability.dart';
import '../data/models/observation_weather.dart';
import '../data/models/tonight_observation_session.dart';
import '../data/models/weather_forecast_slot.dart';
import 'celestial_position_service.dart';
import 'scoring/light_pollution_score.dart';
import 'scoring/moon_score.dart';
import 'observation_feasibility_policy.dart';
import 'observation_quality_service.dart';
import 'scheduler_engine.dart';

enum CondensationRisk {
  low('낮음'),
  moderate('보통'),
  high('높음');

  const CondensationRisk(this.label);
  final String label;
}

class MoonPhaseInfo {
  const MoonPhaseInfo({
    required this.age,
    required this.illumination,
    required this.phaseName,
    required this.phaseEmoji,
  });

  final double age;
  final double illumination;
  final String phaseName;
  final String phaseEmoji;

  int get illuminationPercent => (illumination * 100).round();
}

class ObservationScoreBreakdown {
  const ObservationScoreBreakdown({
    required this.score,
    required this.cloudPenalty,
    required this.windPenalty,
    required this.moonPenalty,
    required this.visibilityPenalty,
    required this.condensationPenalty,
    required this.precipitationPenalty,
    required this.condensationRisk,
    required this.moonIllumination,
  });

  final int score;
  final int cloudPenalty;
  final int windPenalty;
  final int moonPenalty;
  final int visibilityPenalty;
  final int condensationPenalty;
  final int precipitationPenalty;
  final CondensationRisk condensationRisk;
  final double moonIllumination;

  int get starCount {
    if (score >= 80) return 5;
    if (score >= 60) return 4;
    if (score >= 40) return 3;
    if (score >= 20) return 2;
    return 1;
  }

  int get recommendationStarCount =>
      ObservationScoreService.recommendationStarCount(score);
}

class SlotScoreComponents {
  const SlotScoreComponents({
    required this.moon,
    required this.lightPollution,
    required this.weather,
    this.altitude,
  });

  final double moon;
  final double lightPollution;
  final double weather;
  final double? altitude;
}

class TonightObservationSlot {
  const TonightObservationSlot({
    required this.label,
    required this.targetTime,
    required this.forecast,
    required this.moon,
    required this.feasibility,
    required this.qualityIndex,
    this.components = const SlotScoreComponents(
      moon: 0,
      lightPollution: 0,
      weather: 0,
    ),
  });

  final String label;
  final DateTime targetTime;
  final WeatherForecastSlot forecast;
  final MoonPhaseInfo moon;
  final ObservationFeasibilityResult feasibility;
  final ObservationQualityIndex qualityIndex;
  final SlotScoreComponents components;

  bool get canObserve => feasibility.canObserve && qualityIndex.isObservable;

  double? get observationScore => qualityIndex.oqi;

  CondensationRisk get condensationRisk {
    final spread =
        forecast.temperature -
        ObservationScoreService.dewPointCelsius(
          forecast.temperature,
          forecast.humidity,
        );
    if (spread < 2) return CondensationRisk.high;
    if (spread <= 5) return CondensationRisk.moderate;
    return CondensationRisk.low;
  }

  int get score => qualityIndex.score;
  int get starCount => qualityIndex.starCount;
}

class TonightObservationSummary {
  const TonightObservationSummary({
    required this.finalScore,
    required this.averageScore,
    required this.averageQuality,
    required this.slots,
    required this.averageCloudCoverage,
    required this.averageWindSpeed,
    required this.averageTemperature,
    required this.averageMoonIllumination,
    required this.averagePrecipitationPop,
    required this.averageVisibilityMeters,
    this.observationWindow,
    this.isObservationFeasible = true,
    this.primaryInfeasibleReason,
    this.infeasibleUserMessage,
  });

  final int finalScore;
  final int averageScore;
  final ObservationQualityIndex averageQuality;
  final List<TonightObservationSlot> slots;
  final double averageCloudCoverage;
  final double averageWindSpeed;
  final double averageTemperature;
  final double averageMoonIllumination;
  final double averagePrecipitationPop;
  final int averageVisibilityMeters;
  final ObservationWindow? observationWindow;
  final bool isObservationFeasible;
  final String? primaryInfeasibleReason;
  final String? infeasibleUserMessage;

  TonightObservationSlot? get bestSlot => observationWindow?.peakSlot;
}

class SiteSlotData {
  const SiteSlotData({required this.scores, required this.feasibility});

  final Map<DateTime, double> scores;
  final Map<DateTime, ObservationFeasibilityResult> feasibility;
}

/// Unified recommended observation window for tonight.
class ObservationWindow {
  const ObservationWindow({
    required this.startTime,
    required this.endTime,
    required this.label,
    required this.averageScore,
    required this.starCount,
    required this.peakScore,
    required this.peakSlotTime,
    required this.stability,
    required this.contributions,
    required this.reasons,
    required this.slots,
    required this.peakSlot,
  });

  final DateTime startTime;
  final DateTime endTime;
  final String label;
  final int averageScore;
  final int starCount;
  final int peakScore;
  final DateTime peakSlotTime;
  final ObservationStability stability;
  final List<ObservationScoreContribution> contributions;
  final List<String> reasons;
  final List<TonightObservationSlot> slots;
  final TonightObservationSlot peakSlot;

  bool containsTime(DateTime time) {
    return !time.isBefore(startTime) && !time.isAfter(endTime);
  }
}

class ObservationScoreService {
  static const astronomicalTwilightMinutes = 80;
  static const siteObservationScoreNeutral = 50.0;
  static const _synodicPeriod = 29.53059;
  static final _referenceNewMoon = DateTime.utc(2019, 12, 26, 5, 13);

  static const _moonScore = MoonScore();
  static const _lightPollutionScore = LightPollutionScore();
  static const _feasibilityPolicy = ObservationFeasibilityPolicy();
  static const _qualityService = ObservationQualityService();

  // ── Site observation score (light pollution) ─────────────────────────────

  /// Maps atlas brightness to a site observation score (0–100).
  ///
  /// Replace via [computeSiteObservationScore] when SQM/Bortle are available.
  static double brightnessToObservationScore(double brightness) {
    if (brightness <= 0.2) return 100;
    if (brightness <= 0.5) return 98;
    if (brightness <= 1.0) return 95;
    if (brightness <= 2.0) return 90;
    if (brightness <= 3.0) return 80;
    if (brightness <= 4.0) return 70;
    if (brightness <= 5.0) return 60;
    if (brightness <= 6.0) return 50;
    if (brightness <= 7.0) return 40;
    if (brightness <= 8.0) return 30;
    if (brightness <= 9.0) return 20;
    return 10;
  }

  /// Site-level observation score from light-pollution inputs.
  ///
  /// Currently uses [brightness] only; [sqm] and [bortle] are reserved.
  static double? computeSiteObservationScore({
    double? brightness,
    double? sqm,
    int? bortle,
  }) {
    if (brightness == null) return null;
    return brightnessToObservationScore(brightness).clamp(0.0, 100.0);
  }

  // ── Unified observation score (single source of truth) ───────────────────

  static double siteMoonScore(double moonIllumination) {
    return ((1 - moonIllumination.clamp(0.0, 1.0)) * 100).clamp(0.0, 100.0);
  }

  static double siteLightPollutionScore(ObservationContext context) {
    return computeSiteObservationScore(
          brightness: context.brightness,
          bortle: context.bortle,
        ) ??
        siteObservationScoreNeutral;
  }

  static double siteWeatherScore({
    required WeatherForecastSlot forecast,
    required MoonPhaseInfo moon,
  }) {
    return _qualityService
            .computeSlotQuality(forecast: forecast, moon: moon)
            .oqi ??
        0;
  }

  static SlotScoreComponents siteComponents({
    required ObservationContext context,
    required WeatherForecastSlot forecast,
    required MoonPhaseInfo moon,
  }) {
    return SlotScoreComponents(
      moon: siteMoonScore(moon.illumination),
      lightPollution: siteLightPollutionScore(context),
      weather: siteWeatherScore(forecast: forecast, moon: moon),
    );
  }

  static double weightedSiteScore(SlotScoreComponents components) {
    return (components.moon * ObservationScoreWeights.siteMoon +
            components.lightPollution *
                ObservationScoreWeights.siteLightPollution +
            components.weather * ObservationScoreWeights.siteWeather)
        .clamp(0.0, 100.0);
  }

  static double calculateSiteSlotScore({
    required ObservationContext context,
    required DateTime time,
    WeatherForecastSlot? forecast,
    ObservationFeasibilityResult? feasibility,
  }) {
    final resolved =
        forecast ??
        (context.forecasts.isEmpty
            ? null
            : resolveForecastAt(time, context.forecasts));
    if (resolved == null) {
      final moon = computeMoonInfo(time);
      return _qualityService
              .computeSlotQuality(
                forecast: WeatherForecastSlot(
                  time: time,
                  temperature: context.weather?.temperature ?? 10,
                  humidity: context.weather?.humidity ?? 50,
                  windSpeed: context.weather?.windSpeed ?? 0,
                  cloudCoverage: context.cloudCover,
                  visibility: context.weather?.visibility ?? 10000,
                  pop: 0,
                  description: '',
                  icon: '',
                ),
                moon: moon,
                feasibility: feasibility,
              )
              .oqi ??
          0;
    }

    final moon = computeMoonInfo(time);
    return _qualityService
            .computeSlotQuality(
              forecast: resolved,
              moon: moon,
              feasibility: feasibility,
            )
            .oqi ??
        0;
  }

  static double calculateTargetSlotScore({
    required CatalogObject object,
    required ObjectImagingProfile profile,
    required ObservationContext context,
    required DateTime evaluationTime,
    required double altitude,
    required CelestialPositionService positionService,
    ObservationWeather? weather,
  }) {
    final slotWeather =
        weather ??
        context.sessionWeather?.weatherAt(
          _alignToTenMinuteSlot(evaluationTime),
        );

    final altitudeScore = _altitudeScore(altitude);
    final scoringContext = context.copyWith(currentTime: evaluationTime);
    final moon = _moonScore.calculate(
      object: object,
      context: scoringContext,
      positionService: positionService,
      evaluationTime: evaluationTime,
    );
    final lightPollution = _lightPollutionScore.calculate(
      context: context,
      profile: profile,
    );
    final weatherScore = slotWeather != null
        ? _qualityService
                  .computeSlotQuality(
                    forecast: slotWeather.toForecastSlot(),
                    moon: computeMoonInfo(evaluationTime),
                  )
                  .oqi ??
              0
        : _qualityService
                  .computeSlotQuality(
                    forecast: WeatherForecastSlot(
                      time: evaluationTime,
                      temperature: context.weather?.temperature ?? 10,
                      humidity: context.weather?.humidity ?? 50,
                      windSpeed: context.weather?.windSpeed ?? 0,
                      cloudCoverage: context.cloudCover,
                      visibility: context.weather?.visibility ?? 10000,
                      pop: 0,
                      description: '',
                      icon: '',
                    ),
                    moon: computeMoonInfo(evaluationTime),
                  )
                  .oqi ??
              0;

    return (altitudeScore * ObservationScoreWeights.altitude +
            moon * ObservationScoreWeights.moon +
            lightPollution * ObservationScoreWeights.lightPollution +
            weatherScore * ObservationScoreWeights.weather)
        .clamp(0.0, 100.0);
  }

  static Map<DateTime, double> buildSiteSlotIndex({
    required TonightObservationSession session,
    required ObservationContext context,
    ObservationFeasibilityPolicy? feasibilityPolicy,
  }) {
    return buildSiteSlotData(
      session: session,
      context: context,
      feasibilityPolicy: feasibilityPolicy,
    ).scores;
  }

  static SiteSlotData buildSiteSlotData({
    required TonightObservationSession session,
    required ObservationContext context,
    ObservationFeasibilityPolicy? feasibilityPolicy,
  }) {
    final policy = feasibilityPolicy ?? _feasibilityPolicy;
    final scores = <DateTime, double>{};
    final feasibility = <DateTime, ObservationFeasibilityResult>{};
    var cursor = _alignToTenMinuteSlot(session.start);

    while (cursor.isBefore(session.end)) {
      final end = cursor.add(SchedulerEngine.slotDuration);
      if (end.isAfter(session.end)) break;

      final forecast = context.forecasts.isEmpty
          ? null
          : resolveForecastAt(cursor, context.forecasts);
      final result = forecast == null
          ? const ObservationFeasibilityResult.observable()
          : policy.evaluateSiteSlot(forecast: forecast);
      feasibility[cursor] = result;

      if (result.canObserve) {
        scores[cursor] = calculateSiteSlotScore(
          context: context,
          time: cursor,
          forecast: forecast,
          feasibility: result,
        );
      }

      cursor = end;
    }

    return SiteSlotData(scores: scores, feasibility: feasibility);
  }

  static double _altitudeScore(double altitude) {
    if (altitude < 0) return 0;
    if (altitude >= 60) return 100;
    if (altitude >= 45) return 85;
    if (altitude >= 30) return 70;
    if (altitude >= 15) return 50;
    return 25;
  }

  static DateTime _alignToTenMinuteSlot(DateTime time) {
    const slotMinutes = 10;
    final remainder = time.minute % slotMinutes;
    if (remainder == 0 && time.second == 0 && time.millisecond == 0) {
      return time;
    }
    final addMinutes = remainder == 0 ? slotMinutes : slotMinutes - remainder;
    return time
        .add(Duration(minutes: addMinutes))
        .copyWith(second: 0, millisecond: 0, microsecond: 0);
  }

  static int componentStarCount(double score) {
    if (score >= 90) return 5;
    if (score >= 75) return 4;
    if (score >= 60) return 3;
    if (score >= 40) return 2;
    return 1;
  }

  static ObservationStability calculateStability(List<double> scores) {
    if (scores.isEmpty) {
      return const ObservationStability(
        score: 100,
        starCount: 5,
        label: '매우 안정적',
        description: '관측 조건이 시간대별로 매우 일정합니다.',
        standardDeviation: 0,
      );
    }

    if (scores.length == 1) {
      return const ObservationStability(
        score: 100,
        starCount: 5,
        label: '매우 안정적',
        description: '관측 조건이 안정적입니다.',
        standardDeviation: 0,
      );
    }

    final mean = _average(scores);
    final variance =
        scores
            .map((s) => math.pow(s - mean, 2).toDouble())
            .reduce((a, b) => a + b) /
        scores.length;
    final stdDev = math.sqrt(variance);
    final stabilityScore = (100 - stdDev * 5).clamp(0.0, 100.0).round();

    final starCount = switch (stdDev) {
      <= 3 => 5,
      <= 6 => 4,
      <= 10 => 3,
      _ => 2,
    };

    final label = switch (starCount) {
      5 => '매우 안정적',
      4 => '안정적',
      3 => '보통',
      _ => '변동 큼',
    };

    final description = switch (starCount) {
      5 => '관측 조건이 시간대별로 매우 일정합니다.',
      4 => '관측 조건이 비교적 안정적입니다.',
      3 => '시간대별 관측 조건에 다소 변동이 있습니다.',
      _ => '관측 조건 변동이 커 촬영 계획에 주의가 필요합니다.',
    };

    return ObservationStability(
      score: stabilityScore,
      starCount: starCount,
      label: label,
      description: description,
      standardDeviation: stdDev,
    );
  }

  static List<ObservationScoreContribution> calculateContributions({
    required List<TonightObservationSlot> windowSlots,
    required ObservationStability stability,
  }) {
    if (windowSlots.isEmpty) return const [];

    final averageQuality = computeAverageQuality(windowSlots);
    final contributions = averageQuality.components
        .map(
          (component) => ObservationScoreContribution(
            category: component.category,
            points: component.qualityPoints,
            starCount: component.starCount,
          ),
        )
        .toList();

    contributions.add(
      ObservationScoreContribution(
        category: '안정성',
        points: (stability.score * 0.15).round(),
        starCount: stability.starCount,
        label: stability.label,
      ),
    );

    return contributions;
  }

  static int recommendationStarCount(int score) {
    if (score >= 90) return 5;
    if (score >= 75) return 4;
    if (score >= 60) return 3;
    if (score >= 40) return 2;
    return 1;
  }

  static Color scoreColor(int score) {
    if (score >= 90) return AppColors.ic;
    if (score >= 75) return const Color(0xFF60A5FA);
    if (score >= 60) return AppColors.solar;
    if (score >= 40) return const Color(0xFFFB923C);
    return const Color(0xFFEF4444);
  }

  static MoonPhaseInfo computeMoonInfo(DateTime time) {
    final days =
        time.toUtc().difference(_referenceNewMoon).inMilliseconds / 86400000.0;
    final age = days % _synodicPeriod;
    final illumination = (1 - math.cos(2 * math.pi * age / _synodicPeriod)) / 2;

    String phaseName;
    String phaseEmoji;

    if (age < 1.85 || age >= 27.68) {
      phaseName = '삭 (New Moon)';
      phaseEmoji = '🌑';
    } else if (age < 7.38) {
      phaseName = '초승달';
      phaseEmoji = '🌒';
    } else if (age < 8.15) {
      phaseName = '상현달';
      phaseEmoji = '🌓';
    } else if (age < 14.76) {
      phaseName = '상현 (차오르는 달)';
      phaseEmoji = '🌔';
    } else if (age < 15.53) {
      phaseName = '망 (Full Moon)';
      phaseEmoji = '🌕';
    } else if (age < 22.15) {
      phaseName = '하현 (기우는 달)';
      phaseEmoji = '🌖';
    } else if (age < 22.92) {
      phaseName = '하현달';
      phaseEmoji = '🌗';
    } else {
      phaseName = '그믐달';
      phaseEmoji = '🌘';
    }

    return MoonPhaseInfo(
      age: age,
      illumination: illumination,
      phaseName: phaseName,
      phaseEmoji: phaseEmoji,
    );
  }

  static int cloudPenalty(int cloudCoverage) {
    final cloud = cloudCoverage.clamp(0, 100);
    if (cloud <= 20) return (cloud * 0.2).round();
    if (cloud <= 50) return 4 + ((cloud - 20) * 0.8).round();
    if (cloud <= 70) return 28 + ((cloud - 50) * 1.2).round();
    return 52 + ((cloud - 70) * 1.6).round();
  }

  static int windPenalty(double windSpeed) {
    return (math.max(0.0, windSpeed - 5) * 2.5).round();
  }

  static int moonPenalty(double moonIllumination) {
    return (moonIllumination.clamp(0.0, 1.0) * 32).round();
  }

  static int visibilityPenalty(int visibilityMeters) {
    final vis = visibilityMeters.clamp(0, 100000);
    if (vis >= 10000) return 0;
    if (vis >= 5000) return ((10000 - vis) / 500).round();
    if (vis >= 1000) return 10 + ((5000 - vis) / 100).round();
    return (50 + (1000 - vis) / 50).round().clamp(50, 80);
  }

  static int precipitationPenalty(double popPercent) {
    final pop = popPercent.clamp(0, 100);
    if (pop <= 10) return 0;
    if (pop <= 30) return ((pop - 10) * 0.3).round();
    if (pop <= 60) return 6 + ((pop - 30) * 0.4).round();
    return 18 + ((pop - 60) * 0.5).round();
  }

  static double dewPointCelsius(double temperature, int humidity) {
    final rh = humidity.clamp(1, 100);
    final alpha =
        (17.27 * temperature) / (237.7 + temperature) + math.log(rh / 100);
    return (237.7 * alpha) / (17.27 - alpha);
  }

  static CondensationRisk condensationRisk(double temperature, int humidity) {
    final spread = temperature - dewPointCelsius(temperature, humidity);
    if (spread < 2) return CondensationRisk.high;
    if (spread <= 5) return CondensationRisk.moderate;
    return CondensationRisk.low;
  }

  static int condensationPenalty(CondensationRisk risk) {
    return switch (risk) {
      CondensationRisk.high => 10,
      CondensationRisk.moderate => 5,
      CondensationRisk.low => 0,
    };
  }

  static ObservationScoreBreakdown computeBreakdown({
    required int cloudCoverage,
    required double windSpeed,
    required double moonIllumination,
    required int visibilityMeters,
    required double temperature,
    required int humidity,
    required double pop,
  }) {
    final risk = condensationRisk(temperature, humidity);
    final cp = cloudPenalty(cloudCoverage);
    final wp = windPenalty(windSpeed);
    final mp = moonPenalty(moonIllumination);
    final vp = visibilityPenalty(visibilityMeters);
    final dp = condensationPenalty(risk);
    final pp = precipitationPenalty(pop);
    final score = (100 - cp - wp - mp - vp - dp - pp).clamp(0, 100).round();

    return ObservationScoreBreakdown(
      score: score,
      cloudPenalty: cp,
      windPenalty: wp,
      moonPenalty: mp,
      visibilityPenalty: vp,
      condensationPenalty: dp,
      precipitationPenalty: pp,
      condensationRisk: risk,
      moonIllumination: moonIllumination,
    );
  }

  static String formatHourLabel(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:00';
  }

  static DateTime truncateToHour(DateTime time) {
    return DateTime(time.year, time.month, time.day, time.hour);
  }

  static DateTime observationStartTime(DateTime sunset) {
    return truncateToHour(
      sunset.toLocal().add(
        const Duration(minutes: astronomicalTwilightMinutes),
      ),
    );
  }

  static DateTime observationEndTime(DateTime sunrise) {
    return truncateToHour(
      sunrise.toLocal().subtract(
        const Duration(minutes: astronomicalTwilightMinutes),
      ),
    );
  }

  static ({DateTime nightStart, DateTime nightEnd}) estimatedNightWindow(
    DateTime now,
  ) {
    const sunsetHours = [17, 17, 18, 19, 19, 19, 19, 19, 18, 17, 17, 17];
    const sunriseHours = [7, 7, 6, 6, 5, 5, 5, 5, 6, 6, 7, 7];
    final monthIndex = now.month - 1;
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final sunset = DateTime(
      today.year,
      today.month,
      today.day,
      sunsetHours[monthIndex],
      30,
    );
    final sunrise = DateTime(
      tomorrow.year,
      tomorrow.month,
      tomorrow.day,
      sunriseHours[monthIndex],
      30,
    );
    return (
      nightStart: observationStartTime(sunset),
      nightEnd: observationEndTime(sunrise),
    );
  }

  static ({DateTime nightStart, DateTime nightEnd}) observationNightWindow({
    required DateTime now,
    required DateTime sunrise,
    required DateTime sunset,
  }) {
    final sr = sunrise.toLocal();
    final observationStart = observationStartTime(sunset);
    final today = DateTime(now.year, now.month, now.day);

    if (now.isBefore(sr)) {
      final yday = today.subtract(const Duration(days: 1));
      final nightStart = observationStartTime(
        DateTime(yday.year, yday.month, yday.day, sunset.hour, sunset.minute),
      );
      final sunriseForToday = DateTime(
        today.year,
        today.month,
        today.day,
        sr.hour,
        sr.minute,
      );
      final nightEnd = observationEndTime(sunriseForToday);
      return (nightStart: nightStart, nightEnd: nightEnd);
    }

    final nightStart = observationStart;
    final tomorrow = today.add(const Duration(days: 1));
    final sunriseTomorrow = DateTime(
      tomorrow.year,
      tomorrow.month,
      tomorrow.day,
      sr.hour,
      sr.minute,
    );
    final nightEnd = observationEndTime(sunriseTomorrow);
    return (nightStart: nightStart, nightEnd: nightEnd);
  }

  static List<DateTime> hourlyTargets({
    required DateTime nightStart,
    required DateTime nightEnd,
  }) {
    final targets = <DateTime>[];
    var cursor = nightStart;
    while (cursor.isBefore(nightEnd)) {
      targets.add(cursor);
      cursor = cursor.add(const Duration(hours: 1));
    }
    return targets;
  }

  static WeatherForecastSlot? findClosestForecast(
    List<WeatherForecastSlot> forecasts,
    DateTime target,
  ) {
    if (forecasts.isEmpty) return null;

    WeatherForecastSlot? closest;
    var minDiff = double.infinity;

    for (final slot in forecasts) {
      final diff = slot.time.difference(target).inMinutes.abs().toDouble();
      if (diff < minDiff) {
        minDiff = diff;
        closest = slot;
      }
    }
    return closest;
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  static int _lerpInt(int a, int b, double t) =>
      _lerp(a.toDouble(), b.toDouble(), t).round();

  static WeatherForecastSlot? resolveForecastAt(
    DateTime target,
    List<WeatherForecastSlot> forecasts,
  ) {
    if (forecasts.isEmpty) return null;

    final sorted = [...forecasts]..sort((a, b) => a.time.compareTo(b.time));
    if (sorted.length == 1) return sorted.first;

    if (target.isBefore(sorted.first.time) ||
        target.isAfter(sorted.last.time)) {
      return findClosestForecast(forecasts, target);
    }

    WeatherForecastSlot? before;
    WeatherForecastSlot? after;

    for (final slot in sorted) {
      if (!slot.time.isAfter(target)) {
        before = slot;
      }
      if (!slot.time.isBefore(target) && after == null) {
        after = slot;
        break;
      }
    }

    before ??= sorted.first;
    after ??= sorted.last;

    if (before.time == after.time) return before;

    final totalMs = after.time.difference(before.time).inMilliseconds;
    if (totalMs <= 0) return before;

    final t = target.difference(before.time).inMilliseconds / totalMs;
    final closer = t <= 0.5 ? before : after;

    return WeatherForecastSlot(
      time: target,
      temperature: _lerp(before.temperature, after.temperature, t),
      humidity: _lerpInt(before.humidity, after.humidity, t),
      windSpeed: _lerp(before.windSpeed, after.windSpeed, t),
      cloudCoverage: _lerpInt(before.cloudCoverage, after.cloudCoverage, t),
      visibility: _lerpInt(before.visibility, after.visibility, t),
      pop: _lerp(before.pop, after.pop, t),
      description: closer.description,
      icon: closer.icon,
    );
  }

  static TonightObservationSlot? buildSlot({
    required DateTime target,
    required List<WeatherForecastSlot> forecasts,
    required ObservationContext context,
    ObservationFeasibilityPolicy? feasibilityPolicy,
    ObservationQualityService? qualityService,
  }) {
    final forecast = resolveForecastAt(target, forecasts);
    if (forecast == null) return null;

    final policy = feasibilityPolicy ?? _feasibilityPolicy;
    final quality = qualityService ?? _qualityService;
    final feasibility = policy.evaluateSiteSlot(forecast: forecast);
    final moon = computeMoonInfo(target);
    final qualityIndex = quality.computeSlotQuality(
      forecast: forecast,
      moon: moon,
      feasibility: feasibility,
    );
    final components = siteComponents(
      context: context,
      forecast: forecast,
      moon: moon,
    );

    return TonightObservationSlot(
      label: formatHourLabel(target),
      targetTime: target,
      forecast: forecast,
      moon: moon,
      feasibility: feasibility,
      qualityIndex: qualityIndex,
      components: components,
    );
  }

  static ObservationQualityIndex computeAverageQuality(
    List<TonightObservationSlot> slots,
  ) {
    return _qualityService.averageQuality(
      slots.map((slot) => slot.qualityIndex),
    );
  }

  static TonightObservationSummary? buildTonightSummary({
    required ObservationContext context,
    required List<WeatherForecastSlot> forecasts,
    required DateTime sunrise,
    required DateTime sunset,
    required DateTime now,
    ObservationFeasibilityPolicy? feasibilityPolicy,
  }) {
    final slots = buildTonightHourlySlots(
      context: context,
      forecasts: forecasts,
      sunrise: sunrise,
      sunset: sunset,
      now: now,
      feasibilityPolicy: feasibilityPolicy,
    );
    if (slots.isEmpty) return null;

    final feasibleSlots = slots
        .where((s) => s.canObserve && s.observationScore != null)
        .toList();

    if (feasibleSlots.isEmpty) {
      final primaryReason = ObservationFeasibilityPolicy.aggregatePrimaryReason(
        results: slots.map((s) => s.feasibility),
        sampleForecast: slots.first.forecast,
      );
      final userMessage =
          ObservationQualityService.formatInfeasibleMessageFromReason(
            primaryReason,
          );

      return TonightObservationSummary(
        finalScore: 0,
        averageScore: 0,
        averageQuality: ObservationQualityIndex.infeasible(
          primaryInfeasibleReason: primaryReason,
          userMessage: userMessage,
        ),
        slots: slots,
        averageCloudCoverage: _average(
          slots.map((s) => s.forecast.cloudCoverage.toDouble()),
        ),
        averageWindSpeed: _average(slots.map((s) => s.forecast.windSpeed)),
        averageTemperature: _average(slots.map((s) => s.forecast.temperature)),
        averageMoonIllumination: _average(
          slots.map((s) => s.moon.illumination),
        ),
        averagePrecipitationPop: _average(slots.map((s) => s.forecast.pop)),
        averageVisibilityMeters: _average(
          slots.map((s) => s.forecast.visibility.toDouble()),
        ).round(),
        isObservationFeasible: false,
        primaryInfeasibleReason: primaryReason,
        infeasibleUserMessage: userMessage,
      );
    }

    final observationWindow = findObservationWindow(slots);
    if (observationWindow == null) return null;

    final nightAverage = _average(
      feasibleSlots.map((s) => s.observationScore!),
    );
    final finalScore =
        (nightAverage * ObservationScoreWeights.nightAverageWeight +
                observationWindow.averageScore *
                    ObservationScoreWeights.windowAverageWeight)
            .round()
            .clamp(0, 100);

    final averageQuality = computeAverageQuality(slots);

    return TonightObservationSummary(
      finalScore: finalScore,
      averageScore: nightAverage.round(),
      averageQuality: averageQuality,
      slots: slots,
      averageCloudCoverage: _average(
        feasibleSlots.map((s) => s.forecast.cloudCoverage.toDouble()),
      ),
      averageWindSpeed: _average(
        feasibleSlots.map((s) => s.forecast.windSpeed),
      ),
      averageTemperature: _average(
        feasibleSlots.map((s) => s.forecast.temperature),
      ),
      averageMoonIllumination: _average(
        feasibleSlots.map((s) => s.moon.illumination),
      ),
      averagePrecipitationPop: _average(
        feasibleSlots.map((s) => s.forecast.pop),
      ),
      averageVisibilityMeters: _average(
        feasibleSlots.map((s) => s.forecast.visibility.toDouble()),
      ).round(),
      observationWindow: observationWindow,
    );
  }

  static ObservationScoreBreakdown fallbackBreakdown({
    required double moonIllumination,
  }) {
    return computeBreakdown(
      cloudCoverage: 0,
      windSpeed: 0,
      moonIllumination: moonIllumination,
      visibilityMeters: 10000,
      temperature: 10,
      humidity: 50,
      pop: 0,
    );
  }

  static List<TonightObservationSlot> buildTonightHourlySlots({
    required ObservationContext context,
    required List<WeatherForecastSlot> forecasts,
    required DateTime sunrise,
    required DateTime sunset,
    required DateTime now,
    ObservationFeasibilityPolicy? feasibilityPolicy,
  }) {
    final window = observationNightWindow(
      now: now,
      sunrise: sunrise,
      sunset: sunset,
    );
    final targets = hourlyTargets(
      nightStart: window.nightStart,
      nightEnd: window.nightEnd,
    );

    return targets
        .map(
          (target) => buildSlot(
            target: target,
            forecasts: forecasts,
            context: context,
            feasibilityPolicy: feasibilityPolicy,
          ),
        )
        .whereType<TonightObservationSlot>()
        .toList();
  }

  static TonightObservationSlot? bestSlot(List<TonightObservationSlot> slots) {
    final feasible = slots
        .where((s) => s.canObserve && s.observationScore != null)
        .toList();
    if (feasible.isEmpty) return null;
    return feasible.reduce(
      (a, b) => a.observationScore! >= b.observationScore! ? a : b,
    );
  }

  static bool isContiguous(TonightObservationSlot a, TonightObservationSlot b) {
    return a.targetTime
            .add(const Duration(hours: 1))
            .difference(b.targetTime)
            .inMinutes
            .abs() <
        5;
  }

  static List<List<TonightObservationSlot>> contiguousGroups(
    List<TonightObservationSlot> slots,
  ) {
    if (slots.isEmpty) return [];

    final sorted = [...slots]
      ..sort((a, b) => a.targetTime.compareTo(b.targetTime));
    final groups = <List<TonightObservationSlot>>[];
    var current = <TonightObservationSlot>[sorted.first];

    for (var i = 1; i < sorted.length; i++) {
      if (isContiguous(current.last, sorted[i])) {
        current.add(sorted[i]);
      } else {
        groups.add(current);
        current = [sorted[i]];
      }
    }
    groups.add(current);
    return groups;
  }

  static double _average(Iterable<double> values) {
    final list = values.toList();
    if (list.isEmpty) return 0;
    return list.reduce((a, b) => a + b) / list.length;
  }

  static List<String> buildRecommendationReasons({
    required List<TonightObservationSlot> windowSlots,
    required List<TonightObservationSlot> allSlots,
  }) {
    if (windowSlots.isEmpty) return [];

    final reasons = <String>[];
    final windowCloud = _average(
      windowSlots.map((s) => s.forecast.cloudCoverage.toDouble()),
    );
    final allCloud = _average(
      allSlots.map((s) => s.forecast.cloudCoverage.toDouble()),
    );
    if (windowCloud <= allCloud - 5 || windowCloud <= 20) {
      reasons.add('구름 적음');
    }

    final windowWind = _average(windowSlots.map((s) => s.forecast.windSpeed));
    final allWind = _average(allSlots.map((s) => s.forecast.windSpeed));
    if (windowWind <= 3 || windowWind <= allWind - 0.5) {
      reasons.add('풍속 안정');
    }

    final windowMoon = _average(windowSlots.map((s) => s.moon.illumination));
    final allMoon = _average(allSlots.map((s) => s.moon.illumination));
    if (windowMoon <= allMoon - 0.05 || windowMoon <= 0.25) {
      reasons.add('달 영향 적음');
    }

    final windowVis = _average(
      windowSlots.map((s) => s.forecast.visibility.toDouble()),
    );
    final allVis = _average(
      allSlots.map((s) => s.forecast.visibility.toDouble()),
    );
    if (windowVis >= 8000 || windowVis >= allVis + 1000) {
      reasons.add('가시거리 우수');
    }

    final windowCondensation = windowSlots
        .where((s) => s.condensationRisk == CondensationRisk.low)
        .length;
    if (windowCondensation >= windowSlots.length * 0.7) {
      reasons.add('결로 위험 낮음');
    }

    return reasons;
  }

  static String formatWindow(DateTime start, DateTime endInclusive) {
    if (formatHourLabel(start) == formatHourLabel(endInclusive)) {
      return formatHourLabel(start);
    }
    return '${formatHourLabel(start)} ~ ${formatHourLabel(endInclusive)}';
  }

  static ObservationWindow? findObservationWindow(
    List<TonightObservationSlot> slots,
  ) {
    final feasible = slots
        .where((s) => s.canObserve && s.observationScore != null)
        .toList();
    if (feasible.isEmpty) return null;

    final sorted = [...feasible]
      ..sort((a, b) => a.targetTime.compareTo(b.targetTime));
    List<TonightObservationSlot>? bestGroup;
    var bestAverage = -1.0;

    for (var start = 0; start < sorted.length; start++) {
      final group = <TonightObservationSlot>[sorted[start]];

      for (var end = start; end < sorted.length; end++) {
        if (end > start) {
          if (!isContiguous(sorted[end - 1], sorted[end])) break;
          group.add(sorted[end]);
        }

        final average = _average(group.map((s) => s.observationScore!));
        if (average > bestAverage ||
            (average == bestAverage &&
                (bestGroup == null || group.length > bestGroup.length))) {
          bestAverage = average;
          bestGroup = List<TonightObservationSlot>.from(group);
        }
      }
    }

    if (bestGroup == null || bestGroup.isEmpty) return null;

    final averageScore = bestAverage.round();
    final peakSlot = bestGroup.reduce(
      (a, b) => a.observationScore! >= b.observationScore! ? a : b,
    );
    final start = bestGroup.first.targetTime;
    final end = bestGroup.last.targetTime;
    final stability = calculateStability(
      bestGroup.map((s) => s.observationScore!).toList(),
    );
    final contributions = calculateContributions(
      windowSlots: bestGroup,
      stability: stability,
    );
    final reasons = buildRecommendationReasons(
      windowSlots: bestGroup,
      allSlots: slots,
    );

    return ObservationWindow(
      startTime: start,
      endTime: end,
      label: formatWindow(start, end),
      averageScore: averageScore,
      starCount: recommendationStarCount(averageScore),
      peakScore: peakSlot.score,
      peakSlotTime: peakSlot.targetTime,
      stability: stability,
      contributions: contributions,
      reasons: reasons,
      slots: bestGroup,
      peakSlot: peakSlot,
    );
  }
}

import '../data/models/catalog_object.dart';
import '../data/models/equipment.dart';
import '../data/models/imaging_suitability_assessment.dart';
import '../data/models/observation_context.dart';
import '../data/models/observation_site.dart';
import '../data/models/site_horizon_profile.dart';
import '../data/models/shooting_time_window.dart';
import '../data/models/target_imaging_availability.dart';
import '../data/models/tonight_observation_session.dart';
import '../data/models/weather_data.dart';
import '../data/models/weather_forecast_slot.dart';
import '../data/repositories/multi_night_framing_reference_repository.dart';
import 'multi_night_framing_match_service.dart';
import 'observation_engine.dart';
import 'observation_feasibility_policy.dart';
import 'observation_score_service.dart';
import 'recommendation/catalog_recommendation_eligibility_policy.dart';
import 'recommendation/observation_window_calculator.dart';
import 'recommendation_engine.dart';
import 'recommendation_settings_service.dart';
import 'shooting_suitability_service.dart';
import 'weather_service.dart';

/// Adapts the existing recommendation pipeline to one target, site, and date.
/// No celestial, horizon, Moon, or exposure calculation is duplicated here.
class TargetImagingAvailabilityService {
  TargetImagingAvailabilityService(
    this._observationEngine,
    this._recommendationEngine, {
    WeatherService? weatherService,
    MultiNightFramingReferenceRepository? multiNightRepository,
    MultiNightFramingMatchService? multiNightMatchService,
  }) : _weatherService = weatherService,
       _multiNightRepository = multiNightRepository,
       _multiNightMatchService = multiNightMatchService;

  final ObservationEngine _observationEngine;
  final RecommendationEngine _recommendationEngine;
  final WeatherService? _weatherService;
  final MultiNightFramingReferenceRepository? _multiNightRepository;
  final MultiNightFramingMatchService? _multiNightMatchService;
  final ShootingSuitabilityService _shootingSuitabilityService =
      const ShootingSuitabilityService();
  final Map<String, TargetImagingAvailability> _dayCache = {};

  static const List<int> _seasonProbeMonths = [
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10,
    11,
    12,
  ];

  Future<TargetImagingAvailability> evaluate({
    required CatalogObject object,
    required ObservationSite site,
    DateTime? referenceDate,
    Equipment? equipment,
    ImagingEquipmentFit? equipmentFit,
  }) async {
    final today = referenceDate ?? DateTime.now();
    final weather = await _loadWeather(site);
    final current = await _evaluateDate(
      object: object,
      site: site,
      date: today,
      liveNow: today,
      weather: weather?.$1,
      forecasts: weather?.$2 ?? const [],
      equipment: equipment,
      equipmentFit: equipmentFit,
    );
    final tomorrowDate = DateTime(today.year, today.month, today.day + 1, 22);
    final tomorrow = await _evaluateDate(
      object: object,
      site: site,
      date: tomorrowDate,
      equipment: equipment,
      equipmentFit: equipmentFit,
      // Forecast data is intentionally not supplied. Tomorrow is presented as
      // a geometry/Moon/light-pollution estimate, not a weather forecast.
    );
    final season = await _summarizeSeason(
      object: object,
      site: site,
      year: today.year,
    );
    return TargetImagingAvailability(
      object: object,
      referenceDate: today,
      isAvailableTonight: current.isAvailableTonight,
      nightStart: current.nightStart,
      nightEnd: current.nightEnd,
      recommendation: current.recommendation,
      primaryReason: current.primaryReason,
      tomorrow: tomorrow,
      observableSeasonLabel: season.observable,
      optimalSeasonLabel: season.optimal,
      state: current.state,
      usableWindow: current.usableWindow,
      usableMinutes: current.usableMinutes,
      minimumMinutes: current.minimumMinutes,
      recommendedMinutes: current.recommendedMinutes,
      hasFramingReference: current.hasFramingReference,
      framingMatched: current.framingMatched,
      sameFramingMinutes: current.sameFramingMinutes,
      weatherAdvisory: current.weatherAdvisory,
    );
  }

  Future<TargetImagingAvailability> _evaluateDate({
    required CatalogObject object,
    required ObservationSite site,
    required DateTime date,
    DateTime? liveNow,
    WeatherData? weather,
    List<WeatherForecastSlot> forecasts = const [],
    Equipment? equipment,
    ImagingEquipmentFit? equipmentFit,
  }) async {
    final framingRepository = _multiNightRepository;
    final framingReference = framingRepository == null || equipment == null
        ? null
        : await framingRepository.find(
            catalogObjectId: object.effectivePrimaryId,
            equipmentId: equipment.id,
          );
    final referenceCacheKey = framingReference == null
        ? 'no-reference'
        : '${framingReference.revision}-${framingReference.updatedAt.toIso8601String()}';
    final cacheKey =
        '${object.id}:${site.id}:${site.updatedAt.toIso8601String()}:'
        '${date.year}-${date.month}-${date.day}:'
        '${liveNow == null
            ? 'date-estimate'
            : 'live-${liveNow.hour}-${liveNow.minute}'}:'
        '${_weatherCacheKey(weather, forecasts)}:'
        '${equipment?.id ?? 'no-equipment'}:'
        '$referenceCacheKey';
    final cached = _dayCache[cacheKey];
    if (cached != null) return cached;
    final night = weather == null
        ? ObservationScoreService.estimatedNightWindow(date)
        : ObservationScoreService.observationNightWindow(
            now: date,
            sunrise: weather.sunrise,
            sunset: weather.sunset,
          );
    final session = TonightObservationSession(
      start: night.nightStart,
      end: night.nightEnd,
    );
    final baseContext = await _observationEngine.buildContext(
      latitude: site.latitude,
      longitude: site.longitude,
      currentTime: date,
      session: session,
      catalog: [object],
      weather: weather,
      forecasts: forecasts,
    );
    final context = _siteContext(baseContext, site, session);
    final settings = RecommendationSettings.defaults.copyWith(
      // Explicit detail queries must not be hidden by the user's home filters.
      enabledCatalogs: {object.catalog},
      enabledObjectTypes: {object.resolvedObjectType},
      minAltitude: site.defaultMinAltitude.round(),
      maxAltitude: site.defaultMaxAltitude?.round() ?? 90,
    );
    final build = await _recommendationEngine.build(
      catalog: [object],
      settings: settings,
      context: context,
      session: session,
      limit: 1,
      referenceTime: date,
      trackingMode: site.trackingMode,
      candidateScope: RecommendationCandidateScope.directTarget,
      durationPolicy: ObservationWindowDurationPolicy.informational,
      enforceMeaningfulEquipmentResult: false,
      equipmentFitResolver: equipmentFit == null ? null : (_, _) => equipmentFit,
    );
    // The engine only receives one object; avoiding a second identity policy
    // keeps this adapter aligned with its candidate construction contract.
    final result = build.allRecommendations.isEmpty
        ? null
        : build.allRecommendations.first;
    final target = build.scoredTargets.isEmpty
        ? null
        : build.scoredTargets.first;
    var hasFramingReference = false;
    var framingMatched = false;
    int? sameFramingMinutes;
    var state = TargetImagingAvailabilityState.noObservableWindow;
    ShootingTimeWindow? usableWindow;
    int? usableMinutes;
    final minimumMinutes = result?.minimumExposure?.inMinutes;
    final recommendedMinutes = result?.recommendedDailyIntegration?.inMinutes;

    if (target != null) {
      final baseSuitability = _shootingSuitabilityService.evaluate(
        target: target,
        enforceMeaningfulEquipmentResult: false,
      );
      usableWindow =
          baseSuitability.recommendedWindow ?? baseSuitability.observationWindow;
      final matchService = _multiNightMatchService;
      if (matchService != null && equipment != null) {
        final reference = framingReference;
        hasFramingReference = reference != null;
        if (reference != null) {
          final match = matchService.findToday(
            object: object,
            reference: reference,
            site: site,
            equipment: equipment,
            today: date,
            now: liveNow,
            darkWindows: [(nightStart: session.start, nightEnd: session.end)],
          );
          final framingSuitability = _shootingSuitabilityService.evaluate(
            target: target,
            hasFramingReference: true,
            framingMatch: match,
            enforceMeaningfulEquipmentResult: false,
          );
          framingMatched =
              match.isAvailable && framingSuitability.hasUsableWindow;
          usableWindow = framingSuitability.recommendedWindow;
          if (usableWindow != null) {
            sameFramingMinutes = usableWindow.duration.inMinutes;
          }
        }
      }

      usableMinutes = usableWindow?.duration.inMinutes;
      if (usableMinutes != null && usableMinutes > 0) {
        final belowMinimum =
            minimumMinutes != null && usableMinutes < minimumMinutes;
        state = hasFramingReference && framingMatched && belowMinimum
            ? TargetImagingAvailabilityState.multiNightAccumulation
            : belowMinimum
            ? TargetImagingAvailabilityState.shortWindow
            : TargetImagingAvailabilityState.sufficientWindow;
      }
    }
    final availability = TargetImagingAvailability(
      object: object,
      referenceDate: date,
      isAvailableTonight: result != null,
      nightStart: night.nightStart,
      nightEnd: night.nightEnd,
      recommendation: result,
      primaryReason: result == null && build.exclusionReasons.isNotEmpty
          ? build.exclusionReasons.first
          : null,
      state: state,
      usableWindow: usableWindow,
      usableMinutes: usableMinutes,
      minimumMinutes: minimumMinutes,
      recommendedMinutes: recommendedMinutes,
      hasFramingReference: hasFramingReference,
      framingMatched: framingMatched,
      sameFramingMinutes: sameFramingMinutes,
      weatherAdvisory: _weatherAdvisory(context, weather),
    );
    _dayCache[cacheKey] = availability;
    return availability;
  }

  ObservationContext _siteContext(
    ObservationContext base,
    ObservationSite site,
    TonightObservationSession session,
  ) => base.copyWith(
    bortle: site.bortle,
    observationStart: session.start,
    observationEnd: session.end,
    horizonProfile: SiteHorizonProfile(
      points: site.horizonPoints,
      blockedRanges: site.blockedAzimuthRanges,
    ),
    trackingMode: site.trackingMode,
  );

  String? _weatherAdvisory(ObservationContext context, WeatherData? weather) {
    if (weather == null) return null;
    final representativeCloudCoverage =
        ObservationScoreService.averageNightlyCloudCoverage(
          nightStart: context.observationStart,
          nightEnd: context.observationEnd,
          forecasts: context.forecasts,
        )?.round();
    final advisory = ObservationFeasibilityPolicy.buildWeatherAdvisory(
      results: context.siteSlotFeasibility.values,
      representativeCloudCoverage: representativeCloudCoverage,
    );
    return advisory ?? '현재 예보상 촬영 조건이 양호합니다.';
  }

  String _weatherCacheKey(
    WeatherData? weather,
    List<WeatherForecastSlot> forecasts,
  ) {
    if (weather == null) return 'weather-excluded';
    final forecastSignature = Object.hashAll(
      forecasts.map(
        (slot) => Object.hash(
          slot.time.millisecondsSinceEpoch,
          slot.cloudCoverage,
          slot.pop,
          slot.rainVolumeMm,
          slot.visibility,
          slot.windSpeed,
        ),
      ),
    );
    return 'weather-${Object.hash(
      weather.cloudCoverage,
      weather.visibility,
      weather.windSpeed,
      weather.sunrise.millisecondsSinceEpoch,
      weather.sunset.millisecondsSinceEpoch,
      forecastSignature,
    )}';
  }

  Future<(WeatherData, List<WeatherForecastSlot>)?> _loadWeather(
    ObservationSite site,
  ) async {
    final service = _weatherService;
    if (service == null) return null;
    try {
      final values = await Future.wait([
        service.getCurrentWeather(site.latitude, site.longitude),
        service.getForecast(site.latitude, site.longitude),
      ]);
      return (values[0] as WeatherData, values[1] as List<WeatherForecastSlot>);
    } catch (_) {
      // Geometry, Horizon, Moon, and light-pollution checks still work when
      // the optional weather adapter is temporarily unavailable.
      return null;
    }
  }

  Future<({String? observable, String? optimal})> _summarizeSeason({
    required CatalogObject object,
    required ObservationSite site,
    required int year,
  }) async {
    final observable = <int>[];
    final optimal = <int>[];
    for (final month in _seasonProbeMonths) {
      final result = await _evaluateDate(
        object: object,
        site: site,
        date: DateTime(year, month, 15, 22),
      );
      if (!result.isAvailableTonight) continue;
      observable.add(month);
      if ((result.recommendation?.score ?? 0) >= 65) optimal.add(month);
    }
    return (
      observable: _monthRangeLabel(observable),
      optimal: _monthRangeLabel(optimal),
    );
  }

  String? _monthRangeLabel(List<int> months) {
    if (months.isEmpty) return null;
    if (months.length == 1) return '${months.first}월';
    return '${months.first}월 ~ ${months.last}월';
  }
}

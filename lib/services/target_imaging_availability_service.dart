import '../data/models/catalog_object.dart';
import '../data/models/observation_context.dart';
import '../data/models/observation_site.dart';
import '../data/models/site_horizon_profile.dart';
import '../data/models/target_imaging_availability.dart';
import '../data/models/tonight_observation_session.dart';
import '../data/models/weather_data.dart';
import '../data/models/weather_forecast_slot.dart';
import 'observation_engine.dart';
import 'observation_score_service.dart';
import 'recommendation_engine.dart';
import 'recommendation_settings_service.dart';
import 'weather_service.dart';

/// Adapts the existing recommendation pipeline to one target, site, and date.
/// No celestial, horizon, Moon, or exposure calculation is duplicated here.
class TargetImagingAvailabilityService {
  TargetImagingAvailabilityService(
    this._observationEngine,
    this._recommendationEngine, {
    WeatherService? weatherService,
  }) : _weatherService = weatherService;

  final ObservationEngine _observationEngine;
  final RecommendationEngine _recommendationEngine;
  final WeatherService? _weatherService;
  final Map<String, TargetImagingAvailability> _dayCache = {};

  static const List<int> _seasonProbeMonths = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];

  Future<TargetImagingAvailability> evaluate({
    required CatalogObject object,
    required ObservationSite site,
    DateTime? referenceDate,
  }) async {
    final today = referenceDate ?? DateTime.now();
    final weather = await _loadWeather(site);
    final current = await _evaluateDate(
      object: object,
      site: site,
      date: today,
      weather: weather?.$1,
      forecasts: weather?.$2 ?? const [],
    );
    final tomorrowDate = DateTime(today.year, today.month, today.day + 1, 22);
    final tomorrow = await _evaluateDate(
      object: object,
      site: site,
      date: tomorrowDate,
      // Forecast data is intentionally not supplied. Tomorrow is presented as
      // a geometry/Moon/light-pollution estimate, not a weather forecast.
    );
    final season = await _summarizeSeason(object: object, site: site, year: today.year);
    return TargetImagingAvailability(
      object: object,
      referenceDate: today,
      isAvailableTonight: current.isAvailableTonight,
      recommendation: current.recommendation,
      primaryReason: current.primaryReason,
      tomorrow: tomorrow,
      observableSeasonLabel: season.observable,
      optimalSeasonLabel: season.optimal,
    );
  }

  Future<TargetImagingAvailability> _evaluateDate({
    required CatalogObject object,
    required ObservationSite site,
    required DateTime date,
    WeatherData? weather,
    List<WeatherForecastSlot> forecasts = const [],
  }) async {
    final cacheKey = '${object.id}:${site.id}:${site.updatedAt.toIso8601String()}:'
        '${date.year}-${date.month}-${date.day}:'
        '${weather == null ? 'weather-excluded' : 'weather-included'}';
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
    );
    // The engine only receives one object; avoiding a second identity policy
    // keeps this adapter aligned with its candidate construction contract.
    final result = build.allRecommendations.isEmpty
        ? null
        : build.allRecommendations.first;
    final availability = TargetImagingAvailability(
      object: object,
      referenceDate: date,
      isAvailableTonight: result != null,
      recommendation: result,
      primaryReason: result == null && build.exclusionReasons.isNotEmpty
          ? build.exclusionReasons.first
          : null,
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
      return (
        values[0] as WeatherData,
        values[1] as List<WeatherForecastSlot>,
      );
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

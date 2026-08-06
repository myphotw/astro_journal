import '../data/models/catalog_object.dart';
import '../data/models/observation_context.dart';
import '../data/models/shooting_record.dart';
import '../data/models/tonight_observation_session.dart';
import '../data/models/weather_data.dart';
import '../data/models/weather_forecast_slot.dart';
import 'celestial_position_service.dart';
import 'observation_condition_service.dart';
import 'observation_score_service.dart';
import 'observation_status_service.dart';
import 'session_weather_index.dart';

/// Aggregates location, weather, moon, light pollution, catalog, and records
/// into a single [ObservationContext].
class ObservationEngine {
  ObservationEngine(
    this._observationConditionService,
    this._celestialPositionService, {
    ObservationStatusService? observationStatusService,
  }) : _observationStatusService =
            observationStatusService ?? const ObservationStatusService();

  final ObservationConditionService _observationConditionService;
  final CelestialPositionService _celestialPositionService;
  final ObservationStatusService _observationStatusService;

  Future<ObservationContext> buildContext({
    required double latitude,
    required double longitude,
    required DateTime currentTime,
    WeatherData? weather,
    List<WeatherForecastSlot> forecasts = const [],
    TonightObservationSession? session,
    List<CatalogObject>? catalog,
    List<ShootingRecord>? shootingRecords,
  }) async {
    final siteCondition = await _observationConditionService.getConditionAt(
      latitude,
      longitude,
    );

    final moonInfo = ObservationScoreService.computeMoonInfo(currentTime);
    final moonCoords = _celestialPositionService.getMoonEquatorial(currentTime);
    final moonAltAz = CelestialPositionService.computeAltAz(
      raHours: moonCoords.raHours,
      decDeg: moonCoords.decDeg,
      latDeg: latitude,
      lonDeg: longitude,
      time: currentTime,
    );

    final nightWindow = _resolveNightWindow(
      currentTime: currentTime,
      weather: weather,
      session: session,
    );

    final sessionWeather = SessionWeatherIndex.build(
      session: TonightObservationSession(
        start: nightWindow.observationStart,
        end: nightWindow.observationEnd,
      ),
      forecasts: forecasts,
      fallbackWeather: weather,
    );

    var context = ObservationContext(
      latitude: latitude,
      longitude: longitude,
      brightness: siteCondition.brightness,
      bortle: siteCondition.bortle,
      moonIllumination: moonInfo.illumination,
      moonAltitude: moonAltAz.altitude,
      moonAzimuth: moonAltAz.azimuth,
      cloudCover: weather?.cloudCoverage ?? 0,
      observationStart: nightWindow.observationStart,
      observationEnd: nightWindow.observationEnd,
      currentTime: currentTime,
      weather: weather,
      forecasts: forecasts,
      sessionWeather: sessionWeather,
      catalog: catalog ?? const [],
      shootingRecords: shootingRecords ?? const [],
    );

    final observationSession = TonightObservationSession(
      start: nightWindow.observationStart,
      end: nightWindow.observationEnd,
    );

    final slotData = ObservationScoreService.buildSiteSlotData(
      session: observationSession,
      context: context,
    );

    context = context.copyWith(
      siteSlotScores: slotData.scores,
      siteSlotFeasibility: slotData.feasibility,
    );

    TonightObservationSummary? summary;
    if (weather != null && forecasts.isNotEmpty) {
      summary = ObservationScoreService.buildTonightSummary(
        context: context,
        forecasts: forecasts,
        sunrise: weather.sunrise,
        sunset: weather.sunset,
        now: currentTime,
      );
    }

    final statusResult = _observationStatusService.evaluate(
      context: context,
      summary: summary,
    );

    return context.copyWith(
      observationWindow: summary?.observationWindow,
      observationStatus: statusResult.status,
      statusPrimaryReason: statusResult.primaryReason,
      statusUserMessage: statusResult.userMessage,
    );
  }

  ({DateTime observationStart, DateTime observationEnd}) _resolveNightWindow({
    required DateTime currentTime,
    WeatherData? weather,
    TonightObservationSession? session,
  }) {
    if (session != null) {
      return (
        observationStart: session.start,
        observationEnd: session.end,
      );
    }

    if (weather != null) {
      final window = ObservationScoreService.observationNightWindow(
        now: currentTime,
        sunrise: weather.sunrise,
        sunset: weather.sunset,
      );
      return (
        observationStart: window.nightStart,
        observationEnd: window.nightEnd,
      );
    }

    final estimated = _estimateNightWindow(currentTime);
    return (
      observationStart: estimated.nightStart,
      observationEnd: estimated.nightEnd,
    );
  }

  ({DateTime nightStart, DateTime nightEnd}) _estimateNightWindow(
    DateTime now,
  ) {
    const sunsetH = [17, 17, 18, 19, 19, 19, 19, 19, 18, 17, 17, 17];
    const sunriseH = [7, 7, 6, 6, 5, 5, 5, 5, 6, 6, 7, 7];

    final monthIndex = now.month - 1;
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    final sunset = DateTime(
      today.year,
      today.month,
      today.day,
      sunsetH[monthIndex],
      30,
    );
    final sunrise = DateTime(
      tomorrow.year,
      tomorrow.month,
      tomorrow.day,
      sunriseH[monthIndex],
      30,
    );

    final nightStart = sunset.add(
      const Duration(minutes: ObservationScoreService.astronomicalTwilightMinutes),
    );
    return (nightStart: nightStart, nightEnd: sunrise);
  }
}

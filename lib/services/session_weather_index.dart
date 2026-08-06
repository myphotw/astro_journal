import '../data/models/observation_weather.dart';
import '../data/models/tonight_observation_session.dart';
import '../data/models/weather_data.dart';
import '../data/models/weather_forecast_slot.dart';
import 'observation_score_service.dart';
import 'scheduler_engine.dart';

/// Maps each 10-minute session slot to the nearest hourly forecast weather.
class SessionWeatherIndex {
  const SessionWeatherIndex({
    required this.bySlotStart,
  });

  final Map<DateTime, ObservationWeather> bySlotStart;

  ObservationWeather weatherAt(DateTime slotStart) {
    return bySlotStart[slotStart] ??
        ObservationWeather.fallback(time: slotStart);
  }

  static SessionWeatherIndex build({
    required TonightObservationSession session,
    required List<WeatherForecastSlot> forecasts,
    WeatherData? fallbackWeather,
  }) {
    final bySlot = <DateTime, ObservationWeather>{};
    var cursor = _alignToSlot(session.start);

    while (cursor.isBefore(session.end)) {
      final end = cursor.add(SchedulerEngine.slotDuration);
      if (end.isAfter(session.end)) break;

      final forecast = forecasts.isEmpty
          ? null
          : ObservationScoreService.resolveForecastAt(cursor, forecasts);

      if (forecast != null) {
        bySlot[cursor] = ObservationWeather.fromForecast(forecast);
      } else if (fallbackWeather != null) {
        bySlot[cursor] = ObservationWeather.fallback(
          time: cursor,
          cloudCover: fallbackWeather.cloudCoverage,
          visibility: fallbackWeather.visibility,
          humidity: fallbackWeather.humidity,
          windSpeed: fallbackWeather.windSpeed,
          temperature: fallbackWeather.temperature,
        );
      } else {
        bySlot[cursor] = ObservationWeather.fallback(time: cursor);
      }

      cursor = end;
    }

    return SessionWeatherIndex(bySlotStart: bySlot);
  }

  static DateTime _alignToSlot(DateTime time) {
    const slotMinutes = 10;
    final remainder = time.minute % slotMinutes;
    if (remainder == 0 && time.second == 0 && time.millisecond == 0) {
      return time;
    }
    final addMinutes =
        remainder == 0 ? slotMinutes : slotMinutes - remainder;
    return time
        .add(Duration(minutes: addMinutes))
        .copyWith(second: 0, millisecond: 0, microsecond: 0);
  }
}

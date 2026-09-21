import '../data/models/observation_weather.dart';
import '../data/models/tonight_observation_session.dart';
import '../data/models/weather_forecast_slot.dart';
import 'observation_score_service.dart';
import 'scheduler_engine.dart';
import 'weather_slot_policy.dart';

/// Maps each 10-minute session slot to a cadence-bounded forecast value.
class SessionWeatherIndex {
  const SessionWeatherIndex({
    required this.bySlotStart,
  });

  final Map<DateTime, ObservationWeather> bySlotStart;

  ObservationWeather? weatherAt(DateTime time) {
    final slotStart = WeatherSlotPolicy.normalizeStart(time);
    return bySlotStart[slotStart];
  }

  static SessionWeatherIndex build({
    required TonightObservationSession session,
    required List<WeatherForecastSlot> forecasts,
  }) {
    final bySlot = <DateTime, ObservationWeather>{};
    var cursor = WeatherSlotPolicy.normalizeStart(session.start);

    while (cursor.isBefore(session.end)) {
      final end = cursor.add(SchedulerEngine.slotDuration);
      if (end.isAfter(session.end)) break;

      final forecast = forecasts.isEmpty
          ? null
          : ObservationScoreService.resolveForecastAt(cursor, forecasts);

      if (forecast != null) {
        bySlot[cursor] = ObservationWeather.fromForecast(forecast);
      }

      cursor = end;
    }

    return SessionWeatherIndex(bySlotStart: bySlot);
  }
}

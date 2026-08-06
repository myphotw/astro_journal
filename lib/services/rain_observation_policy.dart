import '../core/constants/observation_feasibility_config.dart';
import '../data/models/weather_forecast_slot.dart';

/// Result of rain-based observation blocking for tonight's window.
class RainObservationResult {
  const RainObservationResult({
    required this.isBlocked,
    this.primaryReason,
    this.userMessage,
  });

  const RainObservationResult.clear()
      : isBlocked = false,
        primaryReason = null,
        userMessage = null;

  final bool isBlocked;
  final String? primaryReason;
  final String? userMessage;
}

/// SSOT for rain/precipitation blocking observation tonight.
class RainObservationPolicy {
  const RainObservationPolicy();

  static const reasonRain = '비';
  static const reasonPop = '강수';
  static const rainUnavailableMessage =
      '오늘 밤은 비 예보로 인해 관측을 권장하지 않습니다.';

  RainObservationResult evaluate({
    required DateTime observationStart,
    required DateTime observationEnd,
    required List<WeatherForecastSlot> forecasts,
  }) {
    final slots = _slotsInWindow(
      forecasts: forecasts,
      start: observationStart,
      end: observationEnd,
    );
    if (slots.isEmpty) {
      return const RainObservationResult.clear();
    }

    for (final slot in slots) {
      final rain = slot.rainVolumeMm;
      if (rain != null && rain > 0) {
        return RainObservationResult(
          isBlocked: true,
          primaryReason: reasonRain,
          userMessage: rainUnavailableMessage,
        );
      }
    }

    for (final slot in slots) {
      if (slot.rainVolumeMm == null &&
          slot.pop >=
              ObservationFeasibilityConfig.minInfeasibleRainProbabilityPercent) {
        return RainObservationResult(
          isBlocked: true,
          primaryReason: reasonPop,
          userMessage: rainUnavailableMessage,
        );
      }
    }

    return const RainObservationResult.clear();
  }

  static List<WeatherForecastSlot> _slotsInWindow({
    required List<WeatherForecastSlot> forecasts,
    required DateTime start,
    required DateTime end,
  }) {
    return forecasts
        .where(
          (slot) =>
              !slot.time.isBefore(start) &&
              slot.time.isBefore(end.add(const Duration(hours: 3))),
        )
        .toList();
  }
}

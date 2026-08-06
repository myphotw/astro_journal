import 'package:astro_journal/core/constants/observation_feasibility_config.dart';
import 'package:astro_journal/data/models/weather_forecast_slot.dart';
import 'package:astro_journal/services/rain_observation_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const policy = RainObservationPolicy();

  WeatherForecastSlot slot({
    required DateTime time,
    double? rainVolumeMm,
    double pop = 0,
  }) {
    return WeatherForecastSlot(
      time: time,
      temperature: 18,
      humidity: 60,
      windSpeed: 2,
      cloudCoverage: 20,
      visibility: 10000,
      pop: pop,
      description: '맑음',
      icon: '01n',
      rainVolumeMm: rainVolumeMm,
    );
  }

  group('RainObservationPolicy', () {
    final start = DateTime(2026, 7, 20, 21, 0);
    final end = DateTime(2026, 7, 21, 5, 0);

    test('blocks when rain volume is greater than zero', () {
      final result = policy.evaluate(
        observationStart: start,
        observationEnd: end,
        forecasts: [
          slot(time: DateTime(2026, 7, 20, 22, 0), rainVolumeMm: 0.5),
        ],
      );

      expect(result.isBlocked, isTrue);
      expect(result.primaryReason, RainObservationPolicy.reasonRain);
      expect(result.userMessage, RainObservationPolicy.rainUnavailableMessage);
    });

    test('uses pop when rain volume is unavailable', () {
      final result = policy.evaluate(
        observationStart: start,
        observationEnd: end,
        forecasts: [
          slot(
            time: DateTime(2026, 7, 20, 22, 0),
            pop: ObservationFeasibilityConfig.minInfeasibleRainProbabilityPercent,
          ),
        ],
      );

      expect(result.isBlocked, isTrue);
      expect(result.primaryReason, RainObservationPolicy.reasonPop);
    });

    test('does not use pop when rain volume is zero', () {
      final result = policy.evaluate(
        observationStart: start,
        observationEnd: end,
        forecasts: [
          slot(
            time: DateTime(2026, 7, 20, 22, 0),
            rainVolumeMm: 0,
            pop: 90,
          ),
        ],
      );

      expect(result.isBlocked, isFalse);
    });

    test('allows clear weather without rain data', () {
      final result = policy.evaluate(
        observationStart: start,
        observationEnd: end,
        forecasts: [
          slot(time: DateTime(2026, 7, 20, 22, 0), pop: 10),
        ],
      );

      expect(result.isBlocked, isFalse);
    });
  });

  group('WeatherForecastSlot rain parsing', () {
    test('parses rain.3h from forecast json', () {
      final slot = WeatherForecastSlot.fromJson({
        'dt': 1_700_000_000,
        'main': {'temp': 20, 'humidity': 50},
        'wind': {'speed': 2},
        'clouds': {'all': 10},
        'visibility': 10000,
        'pop': 0.2,
        'weather': [
          {'description': 'rain', 'icon': '10n'},
        ],
        'rain': {'3h': 1.2},
      });

      expect(slot.rainVolumeMm, 1.2);
    });
  });
}

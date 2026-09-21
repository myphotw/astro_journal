import 'package:astro_journal/data/models/object_observation_window.dart';
import 'package:astro_journal/data/models/observation_context.dart';
import 'package:astro_journal/data/models/tonight_observation_session.dart';
import 'package:astro_journal/data/models/weather_forecast_slot.dart';
import 'package:astro_journal/services/observation_score_service.dart';
import 'package:astro_journal/services/scoring/weather_score.dart';
import 'package:astro_journal/services/session_weather_index.dart';
import 'package:astro_journal/services/weather_slot_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  WeatherForecastSlot forecast(DateTime time, {int cloud = 99}) {
    return WeatherForecastSlot(
      time: time,
      temperature: 18,
      humidity: 70,
      windSpeed: 1.5,
      cloudCoverage: cloud,
      visibility: 9000,
      pop: 20,
      description: '흐림',
      icon: '04n',
    );
  }

  SessionWeatherIndex buildIndex({
    required DateTime start,
    required DateTime end,
    required List<WeatherForecastSlot> forecasts,
  }) {
    return SessionWeatherIndex.build(
      session: TonightObservationSession(start: start, end: end),
      forecasts: forecasts,
    );
  }

  group('weather slot normalization and provenance', () {
    test('non-boundary session start preserves forecast cloud and wind', () {
      final start = DateTime(2026, 9, 21, 21, 3);
      final index = buildIndex(
        start: start,
        end: DateTime(2026, 9, 21, 22),
        forecasts: [forecast(DateTime(2026, 9, 21, 21))],
      );

      final weather = index.weatherAt(start);

      expect(
        WeatherSlotPolicy.normalizeStart(start),
        DateTime(2026, 9, 21, 21, 10),
      );
      expect(weather?.cloudCover, 99);
      expect(weather?.windSpeed, 1.5);
    });

    test('exact ten-minute boundary keeps the same slot', () {
      final boundary = DateTime(2026, 9, 21, 21, 10);
      final index = buildIndex(
        start: boundary,
        end: DateTime(2026, 9, 21, 21, 30),
        forecasts: [forecast(boundary)],
      );

      expect(WeatherSlotPolicy.normalizeStart(boundary), boundary);
      expect(index.weatherAt(boundary)?.cloudCover, 99);
    });

    test('first and last forecast boundaries work across midnight', () {
      final first = DateTime(2026, 9, 21, 23);
      final last = DateTime(2026, 9, 22, 2);
      final index = buildIndex(
        start: first,
        end: DateTime(2026, 9, 22, 2, 10),
        forecasts: [forecast(first, cloud: 99), forecast(last, cloud: 87)],
      );

      expect(index.weatherAt(first)?.cloudCover, 99);
      expect(index.weatherAt(last)?.cloudCover, 87);
    });

    test('forecast lookup outside one cadence is unknown', () {
      final slot = forecast(DateTime(2026, 9, 21, 21));

      expect(
        ObservationScoreService.resolveForecastAt(DateTime(2026, 9, 22, 0), [
          slot,
        ]),
        isNotNull,
      );
      expect(
        ObservationScoreService.resolveForecastAt(DateTime(2026, 9, 22, 0, 1), [
          slot,
        ]),
        isNull,
      );
    });

    test('missing forecast remains unknown instead of synthetic clear sky', () {
      final start = DateTime(2026, 9, 21, 21);
      final index = buildIndex(
        start: start,
        end: DateTime(2026, 9, 21, 22),
        forecasts: const [],
      );

      expect(index.weatherAt(start), isNull);
    });

    test('unknown weather receives no favorable weather score', () {
      final time = DateTime(2026, 9, 21, 21);
      final context = ObservationContext(
        latitude: 37.5,
        longitude: 127,
        moonIllumination: 0.2,
        moonAltitude: -10,
        moonAzimuth: 180,
        cloudCover: 0,
        observationStart: time,
        observationEnd: time.add(const Duration(hours: 8)),
        currentTime: time,
      );
      const window = ObjectObservationWindow(
        currentAltitude: 45,
        currentAzimuth: 180,
        isCurrentlyVisible: true,
        bestObservationScore: 95,
        hasWeatherData: false,
      );

      expect(
        ObservationScoreService.calculateTargetWeatherScore(
          context: context,
          evaluationTime: time,
        ),
        0,
      );
      expect(const WeatherScore().calculate(window: window), 0);
    });
  });
}

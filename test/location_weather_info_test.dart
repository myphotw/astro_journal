import 'package:astro_journal/data/models/observation_context.dart';
import 'package:astro_journal/data/models/observation_status.dart';
import 'package:astro_journal/data/models/weather_data.dart';
import 'package:astro_journal/data/models/weather_forecast_slot.dart';
import 'package:astro_journal/features/light_pollution_map/models/location_weather_info.dart';
import 'package:astro_journal/features/light_pollution_map/models/shooting_status.dart';
import 'package:astro_journal/services/observation_score_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  WeatherForecastSlot forecast({
    required DateTime time,
    int cloudCoverage = 10,
    double pop = 0,
    double? rainVolumeMm,
    double temperature = 18,
    double windSpeed = 1.8,
  }) {
    return WeatherForecastSlot(
      time: time,
      temperature: temperature,
      humidity: 50,
      windSpeed: windSpeed,
      cloudCoverage: cloudCoverage,
      visibility: 10000,
      pop: pop,
      description: '',
      icon: '01d',
      rainVolumeMm: rainVolumeMm,
    );
  }

  WeatherData currentWeather({
    double temperature = 18,
    int cloudCoverage = 12,
    double windSpeed = 1.8,
  }) {
    return WeatherData(
      temperature: temperature,
      feelsLike: temperature,
      humidity: 50,
      windSpeed: windSpeed,
      windDegree: 0,
      pressure: 1013,
      cloudCoverage: cloudCoverage,
      visibility: 10000,
      sunrise: DateTime(2026, 7, 6, 5, 30),
      sunset: DateTime(2026, 7, 6, 19, 30),
      description: '맑음',
      cityName: 'Test',
    );
  }

  ObservationContext urbanContext({
    required DateTime now,
    required DateTime nightStart,
    required DateTime nightEnd,
  }) {
    return ObservationContext(
      latitude: 35.1796,
      longitude: 129.0756,
      brightness: 15,
      bortle: 9,
      moonIllumination: 0.1,
      moonAltitude: 20,
      moonAzimuth: 180,
      cloudCover: 12,
      observationStart: nightStart,
      observationEnd: nightEnd,
      currentTime: now,
      observationStatus: ObservationStatus.limited,
      statusUserMessage: '오늘은 관측 조건이 좋지 않습니다.',
    );
  }

  group('ShootingStatus', () {
    test('maps observation status to shooting status', () {
      expect(
        ShootingStatus.fromObservationStatus(ObservationStatus.good),
        ShootingStatus.good,
      );
      expect(
        ShootingStatus.fromObservationStatus(ObservationStatus.limited),
        ShootingStatus.limited,
      );
      expect(
        ShootingStatus.fromObservationStatus(ObservationStatus.unavailable),
        ShootingStatus.notRecommended,
      );
    });

    test('returns notRecommended when rain is forecast', () {
      final status = ShootingStatus.evaluate(
        forecast: forecast(
          time: DateTime(2026, 7, 6, 14),
          pop: 80,
        ),
        starCount: 5,
      );

      expect(status, ShootingStatus.notRecommended);
    });
  });

  group('LocationWeatherInfo', () {
    final now = DateTime(2026, 7, 6, 14, 30);
    final nightStart = DateTime(2026, 7, 6, 20, 0);
    final nightEnd = DateTime(2026, 7, 7, 4, 0);

    test('uses main observation status and score from context summary', () {
      final forecasts = [
        forecast(time: DateTime(2026, 7, 6, 15)),
        forecast(time: DateTime(2026, 7, 6, 18)),
        forecast(time: DateTime(2026, 7, 6, 21)),
      ];
      final current = currentWeather();
      final context = urbanContext(
        now: now,
        nightStart: nightStart,
        nightEnd: nightEnd,
      );

      final slots = ObservationScoreService.buildTonightHourlySlots(
        context: context,
        forecasts: forecasts,
        sunrise: current.sunrise,
        sunset: current.sunset,
        now: now,
      );
      final summary = ObservationScoreService.buildTonightSummary(
        context: context,
        forecasts: forecasts,
        sunrise: current.sunrise,
        sunset: current.sunset,
        now: now,
      );

      final info = LocationWeatherInfo.fromContext(
        context: context,
        summary: summary,
        current: current,
        now: now,
      );

      expect(info.observationStatus, ObservationStatus.limited);
      expect(info.observationScore, summary?.finalScore);
      expect(info.starCount, ObservationStatus.limited.homeStarCount);
      expect(info.statusDisplayText, contains('관측 조건이 좋지 않습니다'));
      expect(info.shootingStatus, ShootingStatus.limited);
      expect(info.hourlySlots.length, lessThanOrEqualTo(slots.length));
      if (info.hourlySlots.isNotEmpty) {
        expect(info.hourlySlots.first.weatherEmoji, '☀');
      }
    });

    test('returns unavailable score zero and no stars', () {
      final current = currentWeather();
      final context = ObservationContext(
        latitude: 35.1796,
        longitude: 129.0756,
        brightness: 20,
        bortle: 9,
        moonIllumination: 0.8,
        moonAltitude: 45,
        moonAzimuth: 180,
        cloudCover: 90,
        observationStart: nightStart,
        observationEnd: nightEnd,
        currentTime: now,
        observationStatus: ObservationStatus.unavailable,
        statusPrimaryReason: '평균 구름 90%',
        statusUserMessage: '구름이 너무 많습니다.',
      );

      final info = LocationWeatherInfo.fromContext(
        context: context,
        summary: null,
        current: current,
        now: now,
      );

      expect(info.observationScore, 0);
      expect(info.starCount, 0);
      expect(info.isObservationFeasible, isFalse);
      expect(info.statusDisplayText, contains('구름이 너무 많습니다'));
    });
  });
}

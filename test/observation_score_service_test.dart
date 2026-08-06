import 'package:astro_journal/data/models/observation_context.dart';
import 'package:astro_journal/data/models/observation_feasibility_result.dart';
import 'package:astro_journal/data/models/observation_quality_index.dart';
import 'package:astro_journal/data/models/weather_forecast_slot.dart';
import 'package:astro_journal/services/observation_feasibility_policy.dart';
import 'package:astro_journal/services/observation_quality_service.dart';
import 'package:astro_journal/services/observation_score_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const qualityService = ObservationQualityService();

  WeatherForecastSlot buildForecast({
    int cloud = 10,
    double pop = 0,
    int visibility = 10000,
    double wind = 2,
    double temperature = 15,
    int humidity = 50,
    DateTime? time,
  }) {
    return WeatherForecastSlot(
      time: time ?? DateTime(2026, 6, 24, 22),
      temperature: temperature,
      humidity: humidity,
      windSpeed: wind,
      cloudCoverage: cloud,
      visibility: visibility,
      pop: pop,
      description: '맑음',
      icon: '01n',
    );
  }

  group('observationNightWindow', () {
    test('starts at observation start time after sunset plus 80 minutes', () {
      final now = DateTime(2026, 6, 24, 15);
      final sunrise = DateTime(2026, 6, 24, 5, 30);
      final sunset = DateTime(2026, 6, 24, 19, 30);
      final window = ObservationScoreService.observationNightWindow(
        now: now,
        sunrise: sunrise,
        sunset: sunset,
      );
      expect(window.nightStart.hour, 20);
      expect(window.nightStart.minute, 0);
    });
  });

  group('ObservationQualityService cloud quality', () {
    test('maps DSO cloud tiers at breakpoints', () {
      expect(ObservationQualityService.cloudQuality(0), 100);
      expect(ObservationQualityService.cloudQuality(10), 95);
      expect(ObservationQualityService.cloudQuality(20), 90);
      expect(ObservationQualityService.cloudQuality(30), 80);
      expect(ObservationQualityService.cloudQuality(70), 10);
      expect(ObservationQualityService.cloudQuality(80), 0);
      expect(ObservationQualityService.cloudQuality(85), 0);
    });

    test('heavily penalizes high cloud cover nonlinearly', () {
      final clear = qualityService.computeSlotQuality(
        forecast: buildForecast(cloud: 10),
        moon: ObservationScoreService.computeMoonInfo(DateTime(2026, 6, 24, 22)),
      );
      final cloudy = qualityService.computeSlotQuality(
        forecast: buildForecast(cloud: 75),
        moon: ObservationScoreService.computeMoonInfo(DateTime(2026, 6, 24, 22)),
      );

      expect(clear.oqi, greaterThan(80));
      expect(cloudy.oqi!, lessThan(20));
    });

    test('cloud at or above 80% is infeasible for OQI', () {
      final policy = const ObservationFeasibilityPolicy();
      final feasibility = policy.evaluateSiteSlot(
        forecast: buildForecast(cloud: 88),
      );
      final index = qualityService.computeSlotQuality(
        forecast: buildForecast(cloud: 88, wind: 1),
        moon: ObservationScoreService.computeMoonInfo(DateTime(2026, 6, 24, 22)),
        feasibility: feasibility,
      );

      expect(index.isObservable, isFalse);
      expect(index.oqi, isNull);
    });
  });

  ObservationContext buildContext() {
    return ObservationContext(
      latitude: 37.5,
      longitude: 127.0,
      brightness: 0.5,
      bortle: 3,
      moonIllumination: 0.1,
      moonAltitude: 10,
      moonAzimuth: 180,
      cloudCover: 0,
      observationStart: DateTime(2026, 6, 24, 21),
      observationEnd: DateTime(2026, 6, 25, 5),
      currentTime: DateTime(2026, 6, 24, 15),
    );
  }

  group('buildTonightSummary OQI', () {
    test('uses weighted OQI for final score', () {
      final now = DateTime(2026, 6, 24, 15);
      final sunrise = DateTime(2026, 6, 25, 5, 30);
      final sunset = DateTime(2026, 6, 24, 19, 30);
      final forecasts = List.generate(
        8,
        (i) => WeatherForecastSlot(
          time: DateTime(2026, 6, 24, 20 + i),
          temperature: (18 + i).toDouble(),
          humidity: 50,
          windSpeed: 2,
          cloudCoverage: 10 + i,
          visibility: 10000,
          pop: 0,
          description: '맑음',
          icon: '01n',
        ),
      );

      final summary = ObservationScoreService.buildTonightSummary(
        context: buildContext(),
        forecasts: forecasts,
        sunrise: sunrise,
        sunset: sunset,
        now: now,
      );

      expect(summary, isNotNull);
      expect(summary!.isObservationFeasible, isTrue);
      expect(summary.finalScore, greaterThan(0));
      expect(summary.averageQuality.components, isNotEmpty);
      expect(summary.observationWindow!.averageScore, greaterThan(0));
    });

    test('returns infeasible summary when all slots fail weather checks', () {
      final now = DateTime(2026, 6, 24, 15);
      final sunrise = DateTime(2026, 6, 25, 5, 30);
      final sunset = DateTime(2026, 6, 24, 19, 30);
      final forecasts = List.generate(
        8,
        (i) => WeatherForecastSlot(
          time: DateTime(2026, 6, 24, 20 + i),
          temperature: 18,
          humidity: 50,
          windSpeed: 2,
          cloudCoverage: 100,
          visibility: 10000,
          pop: 0,
          description: '흐림',
          icon: '04n',
        ),
      );

      final summary = ObservationScoreService.buildTonightSummary(
        context: buildContext(),
        forecasts: forecasts,
        sunrise: sunrise,
        sunset: sunset,
        now: now,
      );

      expect(summary, isNotNull);
      expect(summary!.isObservationFeasible, isFalse);
      expect(summary.infeasibleUserMessage, contains('구름'));
    });
  });

  group('findObservationWindow', () {
    TonightObservationSlot makeSlot({
      required DateTime target,
      required double oqi,
      required int cloud,
    }) {
      final slotForecast = buildForecast(cloud: cloud, time: target);
      final moon = ObservationScoreService.computeMoonInfo(target);
      final baseQuality = qualityService.computeSlotQuality(
        forecast: slotForecast,
        moon: moon,
      );

      return TonightObservationSlot(
        label: ObservationScoreService.formatHourLabel(target),
        targetTime: target,
        forecast: slotForecast,
        moon: moon,
        feasibility: const ObservationFeasibilityResult.observable(),
        qualityIndex: ObservationQualityIndex(
          oqi: oqi,
          components: baseQuality.components,
        ),
      );
    }

    test('selects highest average OQI window', () {
      final slots = [
        makeSlot(
          target: DateTime(2026, 6, 24, 21),
          cloud: 90,
          oqi: 12,
        ),
        makeSlot(
          target: DateTime(2026, 6, 24, 22),
          cloud: 10,
          oqi: 85,
        ),
        makeSlot(
          target: DateTime(2026, 6, 24, 23),
          cloud: 15,
          oqi: 88,
        ),
      ];

      final window = ObservationScoreService.findObservationWindow(slots);
      expect(window?.label, '23:00');
      expect(window!.averageScore, 88);
    });
  });

  group('calculateStability', () {
    test('rewards low score variance', () {
      final stable = ObservationScoreService.calculateStability([90, 91, 89, 90]);
      final volatile = ObservationScoreService.calculateStability([95, 30, 98, 20]);

      expect(stable.starCount, greaterThan(volatile.starCount));
      expect(stable.score, greaterThan(volatile.score));
    });
  });
}

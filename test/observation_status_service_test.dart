import 'package:astro_journal/core/constants/observation_status_config.dart';
import 'package:astro_journal/data/models/observation_context.dart';
import 'package:astro_journal/data/models/observation_feasibility_reason.dart';
import 'package:astro_journal/data/models/observation_feasibility_result.dart';
import 'package:astro_journal/data/models/observation_quality_index.dart';
import 'package:astro_journal/data/models/observation_status.dart';
import 'package:astro_journal/data/models/weather_forecast_slot.dart';
import 'package:astro_journal/services/observation_score_service.dart';
import 'package:astro_journal/services/observation_status_service.dart';
import 'package:astro_journal/services/rain_observation_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = ObservationStatusService();

  ObservationContext buildContext({
    required Map<DateTime, ObservationFeasibilityResult> feasibility,
    Map<DateTime, double>? scores,
    int cloudCover = 10,
    List<WeatherForecastSlot> forecasts = const [],
  }) {
    return ObservationContext(
      latitude: 37.5,
      longitude: 127.0,
      moonIllumination: 0.1,
      moonAltitude: -10,
      moonAzimuth: 180,
      cloudCover: cloudCover,
      observationStart: DateTime(2026, 7, 20, 21, 0),
      observationEnd: DateTime(2026, 7, 21, 5, 0),
      currentTime: DateTime(2026, 7, 20, 22, 0),
      siteSlotFeasibility: feasibility,
      siteSlotScores: scores ?? const {},
      forecasts: forecasts,
    );
  }

  List<DateTime> contiguousSlots(DateTime start, int count) {
    return List.generate(
      count,
      (index) => start.add(Duration(minutes: 10 * index)),
    );
  }

  Map<DateTime, ObservationFeasibilityResult> feasibleMap(
    Iterable<DateTime> slots,
  ) {
    return {
      for (final slot in slots)
        slot: const ObservationFeasibilityResult.observable(),
    };
  }

  TonightObservationSummary summaryWithScore(int finalScore) {
    return TonightObservationSummary(
      finalScore: finalScore,
      averageScore: finalScore,
      averageQuality: ObservationQualityIndex(
        oqi: finalScore.toDouble(),
        components: const [],
      ),
      slots: const [],
      averageCloudCoverage: 20,
      averageWindSpeed: 2,
      averageTemperature: 15,
      averageMoonIllumination: 0.1,
      averagePrecipitationPop: 0,
      averageVisibilityMeters: 10000,
    );
  }

  group('ObservationStatusService', () {
    test('returns UNAVAILABLE when rain volume is forecast tonight', () {
      final slots = contiguousSlots(DateTime(2026, 7, 20, 22, 0), 6);
      final result = service.evaluate(
        context: buildContext(
          feasibility: feasibleMap(slots),
          forecasts: [
            WeatherForecastSlot(
              time: DateTime(2026, 7, 20, 22, 0),
              temperature: 18,
              humidity: 60,
              windSpeed: 2,
              cloudCoverage: 10,
              visibility: 10000,
              pop: 10,
              description: 'rain',
              icon: '10n',
              rainVolumeMm: 0.3,
            ),
          ],
        ),
        summary: summaryWithScore(80),
      );

      expect(result.status, ObservationStatus.unavailable);
      expect(result.primaryReason, RainObservationPolicy.reasonRain);
      expect(result.userMessage, RainObservationPolicy.rainUnavailableMessage);
    });

    test('returns UNAVAILABLE when no feasible slots exist', () {
      final slots = contiguousSlots(DateTime(2026, 7, 20, 22, 0), 6);
      final result = service.evaluate(
        context: buildContext(
          feasibility: {
            for (final slot in slots)
              slot: const ObservationFeasibilityResult.infeasible(
                reason: '구름량 85%',
                failedConditions: [ObservationFeasibilityReason.cloudTooHigh],
              ),
          },
        ),
      );

      expect(result.status, ObservationStatus.unavailable);
      expect(result.userMessage, contains('구름'));
    });

    test('returns UNAVAILABLE when OQI is below 45', () {
      final slots = contiguousSlots(DateTime(2026, 7, 20, 22, 0), 12);
      final result = service.evaluate(
        context: buildContext(feasibility: feasibleMap(slots)),
        summary: summaryWithScore(40),
      );

      expect(result.status, ObservationStatus.unavailable);
      expect(result.primaryReason, contains('40'));
    });

    test('returns UNAVAILABLE when continuous shooting is under 30 minutes', () {
      final slots = contiguousSlots(DateTime(2026, 7, 20, 22, 0), 2);
      final result = service.evaluate(
        context: buildContext(feasibility: feasibleMap(slots)),
        summary: summaryWithScore(60),
      );

      expect(result.status, ObservationStatus.unavailable);
      expect(result.longestContinuousMinutes, 20);
    });

    test('returns GOOD when all good thresholds are met', () {
      final slots = contiguousSlots(DateTime(2026, 7, 20, 22, 0), 10);
      final result = service.evaluate(
        context: buildContext(
          feasibility: feasibleMap(slots),
          cloudCover: 20,
        ),
        summary: summaryWithScore(80),
      );

      expect(result.status, ObservationStatus.good);
      expect(result.longestContinuousMinutes, 100);
    });

    test('returns LIMITED for mid-range OQI and shooting window', () {
      final slots = contiguousSlots(DateTime(2026, 7, 20, 22, 0), 5);
      final result = service.evaluate(
        context: buildContext(
          feasibility: feasibleMap(slots),
          cloudCover: 55,
        ),
        summary: summaryWithScore(55),
      );

      expect(result.status, ObservationStatus.limited);
      expect(result.oqi, 55);
      expect(
        result.longestContinuousMinutes,
        greaterThanOrEqualTo(
          ObservationStatusConfig.minLimitedContinuousMinutes,
        ),
      );
      expect(
        result.longestContinuousMinutes,
        lessThan(ObservationStatusConfig.minGoodContinuousMinutes),
      );
    });
  });
}

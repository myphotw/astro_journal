import 'package:astro_journal/core/constants/angular_size_class.dart';
import 'package:astro_journal/core/constants/imaging_difficulty.dart';
import 'package:astro_journal/core/constants/object_type.dart';
import 'package:astro_journal/core/constants/surface_brightness_class.dart';
import 'package:astro_journal/data/models/object_imaging_profile.dart';
import 'package:astro_journal/data/models/observation_context.dart';
import 'package:astro_journal/data/models/observation_feasibility_reason.dart';
import 'package:astro_journal/data/models/weather_forecast_slot.dart';
import 'package:astro_journal/services/observation_feasibility_policy.dart';
import 'package:astro_journal/services/recommendation_settings_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const policy = ObservationFeasibilityPolicy();

  WeatherForecastSlot forecast({
    int cloud = 10,
    double pop = 0,
    int visibility = 10000,
    double wind = 2,
    double? rainVolumeMm,
  }) {
    return WeatherForecastSlot(
      time: DateTime(2026, 6, 24, 22),
      temperature: 18,
      humidity: 50,
      windSpeed: wind,
      cloudCoverage: cloud,
      visibility: visibility,
      pop: pop,
      description: '맑음',
      icon: '01n',
      rainVolumeMm: rainVolumeMm,
    );
  }

  ObservationContext context({int? bortle}) {
    return ObservationContext(
      latitude: 37.5,
      longitude: 127.0,
      bortle: bortle ?? 3,
      brightness: 0.5,
      moonIllumination: 0.1,
      moonAltitude: 10,
      moonAzimuth: 180,
      cloudCover: 0,
      observationStart: DateTime(2026, 6, 24, 21),
      observationEnd: DateTime(2026, 6, 25, 5),
      currentTime: DateTime(2026, 6, 24, 22),
    );
  }

  final profile = ObjectImagingProfile(
    objectType: ObjectType.emissionNebula,
    imagingDifficulty: ImagingDifficulty.easy,
    surfaceBrightnessClass: SurfaceBrightnessClass.bright,
    angularSizeClass: AngularSizeClass.large,
    recommendedBortle: 5,
    minimumRecommendedBortle: 7,
    baseExposureMinutes: 30,
    supportsNarrowband: true,
    recommendedFilters: const [],
  );

  final settings = RecommendationSettings.defaults;

  group('evaluateSiteSlot', () {
    test('rejects cloud at or above 80%', () {
      final result = policy.evaluateSiteSlot(forecast: forecast(cloud: 80));
      expect(result.canObserve, isFalse);
      expect(
        result.failedConditions,
        contains(ObservationFeasibilityReason.cloudTooHigh),
      );
    });

    test('accepts cloud below 80%', () {
      final result = policy.evaluateSiteSlot(forecast: forecast(cloud: 79));
      expect(result.canObserve, isTrue);
    });

    test('rejects high cloud cover', () {
      final result = policy.evaluateSiteSlot(forecast: forecast(cloud: 100));
      expect(result.canObserve, isFalse);
      expect(
        result.failedConditions,
        contains(ObservationFeasibilityReason.cloudTooHigh),
      );
    });

    test('rejects rain probability at or above 60%', () {
      final result = policy.evaluateSiteSlot(forecast: forecast(pop: 60));
      expect(result.canObserve, isFalse);
      expect(
        result.failedConditions,
        contains(ObservationFeasibilityReason.rainProbability),
      );
    });

    test('rejects actual rain volume greater than zero', () {
      final result = policy.evaluateSiteSlot(
        forecast: forecast(rainVolumeMm: 0.1, pop: 10),
      );
      expect(result.canObserve, isFalse);
      expect(
        result.failedConditions,
        contains(ObservationFeasibilityReason.rainVolume),
      );
    });

    test('ignores pop when rain volume is zero', () {
      final result = policy.evaluateSiteSlot(
        forecast: forecast(rainVolumeMm: 0, pop: 90),
      );
      expect(result.canObserve, isTrue);
    });

    test('rejects visibility at or below 3km', () {
      final result = policy.evaluateSiteSlot(
        forecast: forecast(visibility: 3000),
      );
      expect(result.canObserve, isFalse);
      expect(
        result.failedConditions,
        contains(ObservationFeasibilityReason.visibilityTooLow),
      );
    });

    test('rejects wind at or above 15 m/s', () {
      final result = policy.evaluateSiteSlot(forecast: forecast(wind: 15));
      expect(result.canObserve, isFalse);
      expect(
        result.failedConditions,
        contains(ObservationFeasibilityReason.windTooStrong),
      );
    });

    test('accepts good weather', () {
      final result = policy.evaluateSiteSlot(forecast: forecast());
      expect(result.canObserve, isTrue);
    });
  });

  group('evaluateTargetSlot', () {
    test('rejects target below horizon', () {
      final result = policy.evaluateTargetSlot(
        context: context(),
        forecast: forecast(),
        settings: settings,
        profile: profile,
        altitude: -5,
        azimuth: 180,
      );

      expect(result.canObserve, isFalse);
      expect(
        result.failedConditions,
        contains(ObservationFeasibilityReason.belowHorizon),
      );
    });

    test('rejects target when bortle is too bright', () {
      final brightSkyProfile = ObjectImagingProfile(
        objectType: ObjectType.emissionNebula,
        imagingDifficulty: ImagingDifficulty.easy,
        surfaceBrightnessClass: SurfaceBrightnessClass.bright,
        angularSizeClass: AngularSizeClass.large,
        recommendedBortle: 5,
        minimumRecommendedBortle: 7,
        baseExposureMinutes: 30,
        supportsNarrowband: false,
        recommendedFilters: const [],
      );

      final result = policy.evaluateTargetSlot(
        context: context(bortle: 9),
        forecast: forecast(),
        settings: settings,
        profile: brightSkyProfile,
        altitude: 45,
        azimuth: 180,
      );

      expect(result.canObserve, isFalse);
      expect(
        result.failedConditions,
        contains(ObservationFeasibilityReason.lightPollution),
      );
    });
  });
}

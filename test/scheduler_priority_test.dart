import 'package:astro_journal/core/constants/angular_size_class.dart';
import 'package:astro_journal/core/constants/imaging_difficulty.dart';
import 'package:astro_journal/core/constants/object_type.dart';
import 'package:astro_journal/core/constants/surface_brightness_class.dart';
import 'package:astro_journal/data/models/object_imaging_profile.dart';
import 'package:astro_journal/data/models/object_observation_window.dart';
import 'package:astro_journal/services/scheduler/scoring/moon_priority.dart';
import 'package:astro_journal/services/scheduler/scoring/urgency_score.dart';
import 'package:astro_journal/services/scoring/weather_observation_score.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WeatherObservationScoreCalculator', () {
    test('visibility reduces score similarly to cloud cover', () {
      final clear = WeatherObservationScoreCalculator.totalScore(
        cloudCover: 10,
        visibilityMeters: 30000,
        humidity: 50,
        windSpeed: 2,
        precipitationProbability: 0,
        temperature: 10,
      );
      final poor = WeatherObservationScoreCalculator.totalScore(
        cloudCover: 5,
        visibilityMeters: 1000,
        humidity: 50,
        windSpeed: 2,
        precipitationProbability: 0,
        temperature: 10,
      );

      expect(clear, greaterThan(poor));
    });

    test('high precipitation probability heavily reduces score', () {
      final dry = WeatherObservationScoreCalculator.totalScore(
        cloudCover: 10,
        visibilityMeters: 20000,
        humidity: 50,
        windSpeed: 2,
        precipitationProbability: 5,
        temperature: 10,
      );
      final rainy = WeatherObservationScoreCalculator.totalScore(
        cloudCover: 10,
        visibilityMeters: 20000,
        humidity: 50,
        windSpeed: 2,
        precipitationProbability: 80,
        temperature: 10,
      );

      expect(dry, greaterThan(rainy));
    });
  });

  group('UrgencyScore', () {
    const scorer = UrgencyScore();

    test('increases when current time passes latestStartTime', () {
      final window = ObjectObservationWindow(
        currentAltitude: 40,
        currentAzimuth: 180,
        isCurrentlyVisible: true,
        recommendStartTime: DateTime(2026, 7, 1, 21, 0),
        observationEndTime: DateTime(2026, 7, 2, 2, 0),
        totalObservableMinutes: 120,
        remainingVisibleMinutes: 60,
        latestStartTime: DateTime(2026, 7, 2, 0, 0),
      );

      final before = scorer.calculate(
        window: window,
        recommendedExposure: const Duration(hours: 2),
        referenceTime: DateTime(2026, 7, 1, 23, 0),
      );
      final after = scorer.calculate(
        window: window,
        recommendedExposure: const Duration(hours: 2),
        referenceTime: DateTime(2026, 7, 2, 0, 30),
      );

      expect(after, greaterThan(before));
    });
  });

  group('MoonPriority', () {
    const scorer = MoonPriority();

    test('ranks galaxy above emission nebula', () {
      final galaxy = scorer.calculate(
        profile: const ObjectImagingProfile(
          objectType: ObjectType.galaxy,
          imagingDifficulty: ImagingDifficulty.normal,
          surfaceBrightnessClass: SurfaceBrightnessClass.dim,
          angularSizeClass: AngularSizeClass.large,
          baseExposureMinutes: 120,
          minimumRecommendedBortle: 4,
          recommendedBortle: 3,
          supportsNarrowband: false,
          recommendedFilters: ['L'],
        ),
        moonSafeMinutes: 90,
      );
      final nebula = scorer.calculate(
        profile: const ObjectImagingProfile(
          objectType: ObjectType.emissionNebula,
          imagingDifficulty: ImagingDifficulty.easy,
          surfaceBrightnessClass: SurfaceBrightnessClass.bright,
          angularSizeClass: AngularSizeClass.medium,
          baseExposureMinutes: 30,
          minimumRecommendedBortle: 9,
          recommendedBortle: 4,
          supportsNarrowband: true,
          recommendedFilters: ['Ha'],
        ),
        moonSafeMinutes: 90,
      );

      expect(galaxy, greaterThan(nebula));
    });
  });
}

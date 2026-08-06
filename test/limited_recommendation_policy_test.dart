import 'package:astro_journal/core/constants/imaging_difficulty.dart';
import 'package:astro_journal/core/constants/object_type.dart';
import 'package:astro_journal/core/constants/surface_brightness_class.dart';
import 'package:astro_journal/core/constants/angular_size_class.dart';
import 'package:astro_journal/data/models/object_imaging_profile.dart';
import 'package:astro_journal/services/recommendation/limited_recommendation_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ObjectImagingProfile profile(ImagingDifficulty difficulty) {
    return ObjectImagingProfile(
      objectType: ObjectType.emissionNebula,
      imagingDifficulty: difficulty,
      surfaceBrightnessClass: SurfaceBrightnessClass.normal,
      angularSizeClass: AngularSizeClass.large,
      baseExposureMinutes: 30,
      minimumRecommendedBortle: 7,
      recommendedBortle: 4,
      supportsNarrowband: true,
      recommendedFilters: const [],
    );
  }

  group('LimitedRecommendationPolicy', () {
    test('allows very easy, easy, and normal targets', () {
      expect(
        LimitedRecommendationPolicy.allowsTarget(
          profile(ImagingDifficulty.veryEasy),
        ),
        isTrue,
      );
      expect(
        LimitedRecommendationPolicy.allowsTarget(profile(ImagingDifficulty.easy)),
        isTrue,
      );
      expect(
        LimitedRecommendationPolicy.allowsTarget(
          profile(ImagingDifficulty.normal),
        ),
        isTrue,
      );
    });

    test('excludes hard and above', () {
      expect(
        LimitedRecommendationPolicy.allowsTarget(profile(ImagingDifficulty.hard)),
        isFalse,
      );
      expect(
        LimitedRecommendationPolicy.allowsTarget(
          profile(ImagingDifficulty.veryHard),
        ),
        isFalse,
      );
      expect(
        LimitedRecommendationPolicy.allowsTarget(
          profile(ImagingDifficulty.extreme),
        ),
        isFalse,
      );
    });
  });
}

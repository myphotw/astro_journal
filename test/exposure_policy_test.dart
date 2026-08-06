import 'package:astro_journal/core/constants/exposure_policy_config.dart';
import 'package:astro_journal/core/constants/imaging_recommendation_rules.dart';
import 'package:astro_journal/core/constants/object_imaging_profile_defaults.dart';
import 'package:astro_journal/core/constants/object_type.dart';
import 'package:astro_journal/data/models/object_imaging_profile.dart';
import 'package:astro_journal/services/exposure_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ExposurePolicy', () {
    const policy = ExposurePolicy();
    const seoulBortle = ImagingRecommendationRules.seoulBortle;

    ObjectImagingProfile typeProfile(ObjectType type) {
      return ObjectImagingProfileDefaults.forType(type);
    }

    test('minimum exposure increases with bortle for default profile', () {
      final defaultProfile = typeProfile(ObjectType.other);
      final bortle2 = policy.calculateMinimumExposure(
        bortle: 2,
        profile: defaultProfile,
      );
      final bortle5 = policy.calculateMinimumExposure(
        bortle: 5,
        profile: defaultProfile,
      );

      expect(bortle5.inMinutes, greaterThan(bortle2.inMinutes));
    });

    test('emission nebula remains recommended in seoul-like bortle', () {
      expect(
        policy.isRecommended(
          bortle: seoulBortle,
          profile: typeProfile(ObjectType.emissionNebula),
        ),
        isTrue,
      );
    });

    test('galaxy is not recommended in seoul but needs more exposure', () {
      final galaxy = typeProfile(ObjectType.galaxy);
      expect(
        policy.isRecommended(bortle: seoulBortle, profile: galaxy),
        isFalse,
      );

      final seoulMinimum = policy.calculateMinimumExposure(
        bortle: seoulBortle,
        profile: galaxy,
      );
      final darkSkyMinimum = policy.calculateMinimumExposure(
        bortle: 2,
        profile: galaxy,
      );

      expect(seoulMinimum.inMinutes, greaterThan(darkSkyMinimum.inMinutes));
    });

    test('milky way type is excluded in seoul-like bortle', () {
      expect(
        policy.isRecommended(
          bortle: seoulBortle,
          profile: typeProfile(ObjectType.milkyWay),
        ),
        isFalse,
      );
    });

    test('dark nebula type is excluded in seoul-like bortle', () {
      expect(
        policy.isRecommended(
          bortle: seoulBortle,
          profile: typeProfile(ObjectType.darkNebula),
        ),
        isFalse,
      );
    });

    test('recommended exposure uses galaxy multiplier in light pollution', () {
      final galaxy = typeProfile(ObjectType.galaxy);
      final minimum = policy.calculateMinimumExposure(
        bortle: seoulBortle,
        profile: galaxy,
      );
      final recommended = policy.calculateRecommendedExposure(
        bortle: seoulBortle,
        profile: galaxy,
      );

      expect(
        recommended.inMinutes,
        (minimum.inMinutes *
                ExposurePolicyConfig.galaxyHighBortleRecommendedMultiplier)
            .round(),
      );
    });
  });
}

import 'package:astro_journal/core/constants/imaging_recommendation_rules.dart';
import 'package:astro_journal/core/constants/object_imaging_profile_defaults.dart';
import 'package:astro_journal/core/constants/object_type.dart';
import 'package:astro_journal/data/models/observation_context.dart';
import 'package:astro_journal/services/scoring/light_pollution_score.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LightPollutionScore', () {
    const scorer = LightPollutionScore();

    ObservationContext buildContext({int? bortle}) {
      return ObservationContext(
        latitude: 37.5,
        longitude: 127.0,
        bortle: bortle ?? ImagingRecommendationRules.seoulBortle,
        brightness: 8.5,
        moonIllumination: 0.1,
        moonAltitude: 10,
        moonAzimuth: 180,
        cloudCover: 0,
        observationStart: DateTime(2026, 7, 1, 21, 0),
        observationEnd: DateTime(2026, 7, 2, 5, 0),
        currentTime: DateTime(2026, 7, 1, 22, 0),
      );
    }

    test('accepts ObjectImagingProfile parameter', () {
      final brightProfile =
          ObjectImagingProfileDefaults.forType(ObjectType.emissionNebula);
      final dimProfile =
          ObjectImagingProfileDefaults.forType(ObjectType.darkNebula);

      final brightScore = scorer.calculate(
        context: buildContext(),
        profile: brightProfile,
      );
      final dimScore = scorer.calculate(
        context: buildContext(),
        profile: dimProfile,
      );

      expect(brightScore, greaterThan(dimScore));
    });
  });
}

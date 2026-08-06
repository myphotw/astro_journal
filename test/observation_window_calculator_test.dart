import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/observation_context.dart';
import 'package:astro_journal/data/models/tonight_observation_session.dart';
import 'package:astro_journal/services/celestial_position_service.dart';
import 'package:astro_journal/services/exposure_policy.dart';
import 'package:astro_journal/services/object_imaging_profile_provider.dart';
import 'package:astro_journal/services/recommendation/observation_window_calculator.dart';
import 'package:astro_journal/services/recommendation_settings_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ObservationWindowCalculator', () {
    final calculator = ObservationWindowCalculator(CelestialPositionService());
    const profileProvider = ObjectImagingProfileProvider();
    const exposurePolicy = ExposurePolicy();

    CatalogObject buildObject({
      required String id,
      required String ra,
      required String dec,
    }) {
      return CatalogObject(
        id: id,
        number: 42,
        catalog: CatalogType.messier,
        name: id.toUpperCase(),
        type: '발광성운',
        constellation: 'Test',
        ra: ra,
        dec: dec,
        magnitude: '5.0',
      );
    }

    test('uses quality-based optimal time within altitude constraints', () {
      final object = buildObject(
        id: 'm8',
        ra: '18h 03m',
        dec: '-24° 23m',
      );
      final profile = profileProvider.profileFor(object);
      final minimum = exposurePolicy.calculateMinimumExposure(
        bortle: 2,
        profile: profile,
      );
      final recommended = exposurePolicy.calculateRecommendedExposure(
        bortle: 2,
        profile: profile,
      );
      final session = TonightObservationSession(
        start: DateTime(2026, 7, 20, 21, 0),
        end: DateTime(2026, 7, 21, 5, 0),
      );
      final context = ObservationContext(
        latitude: 37.5,
        longitude: 127.0,
        bortle: 2,
        moonIllumination: 0.1,
        moonAltitude: -10,
        moonAzimuth: 180,
        cloudCover: 0,
        observationStart: session.start,
        observationEnd: session.end,
        currentTime: session.start,
      );
      final settings = RecommendationSettings.defaults.copyWith(maxAltitude: 75);

      final result = calculator.calculate(
        object: object,
        profile: profile,
        context: context,
        settings: settings,
        session: session,
        referenceTime: session.start,
        minimumExposure: minimum,
        recommendedExposure: recommended,
      );

      expect(result.exclusion, ObservationWindowExclusion.none);
      expect(result.window?.optimalTime, isNotNull);
      expect(result.window?.optimalStartTime, isNotNull);
      expect(result.window?.optimalEndTime, isNotNull);
      expect(result.window?.optimalAltitude, lessThanOrEqualTo(75));
      expect(result.window?.meridianPassTime, isNotNull);
      expect(result.window?.latestStartTime, isNotNull);
      expect(result.window?.slotObservationScores, isNotEmpty);
    });

    test('excludes target when observable window is shorter than minimum exposure', () {
      final object = buildObject(
        id: 'm8',
        ra: '18h 03m',
        dec: '-24° 23m',
      );
      final profile = profileProvider.profileFor(object);
      final session = TonightObservationSession(
        start: DateTime(2026, 7, 20, 21, 0),
        end: DateTime(2026, 7, 20, 21, 20),
      );
      final context = ObservationContext(
        latitude: 37.5,
        longitude: 127.0,
        bortle: 2,
        moonIllumination: 0.1,
        moonAltitude: -10,
        moonAzimuth: 180,
        cloudCover: 0,
        observationStart: session.start,
        observationEnd: session.end,
        currentTime: session.start,
      );

      final result = calculator.calculate(
        object: object,
        profile: profile,
        context: context,
        settings: RecommendationSettings.defaults,
        session: session,
        referenceTime: session.start,
        minimumExposure: const Duration(hours: 2),
        recommendedExposure: const Duration(hours: 3),
      );

      expect(result.exclusion, ObservationWindowExclusion.insufficientDuration);
    });
  });
}

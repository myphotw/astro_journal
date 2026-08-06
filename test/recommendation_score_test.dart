import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/object_imaging_profile.dart';
import 'package:astro_journal/data/models/object_observation_window.dart';
import 'package:astro_journal/data/models/observation_context.dart';
import 'package:astro_journal/core/constants/object_type.dart';
import 'package:astro_journal/core/constants/imaging_difficulty.dart';
import 'package:astro_journal/core/constants/surface_brightness_class.dart';
import 'package:astro_journal/core/constants/angular_size_class.dart';
import 'package:astro_journal/services/celestial_position_service.dart';
import 'package:astro_journal/services/object_imaging_profile_provider.dart';
import 'package:astro_journal/services/scoring/recommendation_score.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RecommendationScore', () {
    const scorer = RecommendationScore();
    const profileProvider = ObjectImagingProfileProvider();
    final positionService = CelestialPositionService();

    ObservationContext buildContext({
      required DateTime currentTime,
      double moonIllumination = 0.1,
      int cloudCover = 0,
      int? bortle = 2,
    }) {
      return ObservationContext(
        latitude: 37.5,
        longitude: 127.0,
        bortle: bortle,
        brightness: 0.5,
        moonIllumination: moonIllumination,
        moonAltitude: 10,
        moonAzimuth: 180,
        cloudCover: cloudCover,
        observationStart: DateTime(2026, 7, 1, 21, 0),
        observationEnd: DateTime(2026, 7, 2, 5, 0),
        currentTime: currentTime,
      );
    }

    ObjectObservationWindow buildWindow({double bestObservationScore = 80}) {
      return ObjectObservationWindow(
        currentAltitude: 40,
        currentAzimuth: 180,
        isCurrentlyVisible: true,
        recommendStartTime: DateTime(2026, 7, 1, 21, 0),
        optimalStartTime: DateTime(2026, 7, 1, 22, 0),
        optimalEndTime: DateTime(2026, 7, 1, 23, 0),
        peakAltitude: 55,
        peakAltitudeTime: DateTime(2026, 7, 1, 22, 18),
        observationEndTime: DateTime(2026, 7, 2, 1, 0),
        totalObservableMinutes: 120,
        bestObservationScore: bestObservationScore,
      );
    }

    CatalogObject buildObject({required String id, required bool captured}) {
      return CatalogObject(
        id: id,
        number: 42,
        catalog: CatalogType.messier,
        name: 'M42',
        type: '발광성운',
        constellation: 'Orion',
        ra: '5h 35m',
        dec: '-05° 23m',
        magnitude: '4.0',
        captured: captured,
      );
    }

    ObjectImagingProfile buildProfile() {
      return const ObjectImagingProfile(
        objectType: ObjectType.emissionNebula,
        imagingDifficulty: ImagingDifficulty.easy,
        surfaceBrightnessClass: SurfaceBrightnessClass.bright,
        angularSizeClass: AngularSizeClass.medium,
        baseExposureMinutes: 30,
        minimumRecommendedBortle: 8,
        recommendedBortle: 4,
        supportsNarrowband: true,
        recommendedFilters: ['Ha'],
      );
    }

    test('uncaptured target scores higher than captured target', () {
      final context = buildContext(currentTime: DateTime(2026, 1, 15, 22, 0));
      final window = buildWindow();
      final evaluationTime = window.peakAltitudeTime!;
      final uncaptured = buildObject(id: 'm42', captured: false);
      final captured = buildObject(id: 'm42-c', captured: true);
      final profile = buildProfile();

      final uncapturedScore = scorer.calculate(
        object: uncaptured,
        context: context,
        profile: profile,
        window: window,
        evaluationTime: evaluationTime,
        positionService: positionService,
      );
      final capturedScore = scorer.calculate(
        object: captured,
        context: context,
        profile: profile,
        window: window,
        evaluationTime: evaluationTime,
        positionService: positionService,
      );

      expect(uncapturedScore, greaterThan(capturedScore));
    });

    test('lower feasible observation quality lowers score', () {
      final evaluationTime = DateTime(2026, 6, 15, 22, 18);
      final goodWindow = buildWindow(bestObservationScore: 90);
      final poorWindow = buildWindow(bestObservationScore: 20);
      final context = buildContext(currentTime: DateTime(2026, 6, 15, 22, 0));
      final object = buildObject(id: 'm42', captured: false);
      final profile = profileProvider.profileFor(object);

      final goodScore = scorer.calculate(
        object: object,
        context: context,
        profile: profile,
        window: goodWindow,
        evaluationTime: evaluationTime,
        positionService: positionService,
      );
      final poorScore = scorer.calculate(
        object: object,
        context: context,
        profile: profile,
        window: poorWindow,
        evaluationTime: evaluationTime,
        positionService: positionService,
      );

      expect(poorScore, lessThan(goodScore));
    });
  });
}

import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/core/constants/imaging_difficulty.dart';
import 'package:astro_journal/core/constants/object_type.dart';
import 'package:astro_journal/core/constants/surface_brightness_class.dart';
import 'package:astro_journal/core/constants/angular_size_class.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/object_imaging_profile.dart';
import 'package:astro_journal/data/models/object_observation_window.dart';
import 'package:astro_journal/data/models/observation_context.dart';
import 'package:astro_journal/data/models/recommendation_result.dart';
import 'package:astro_journal/data/models/scored_observation_target.dart';
import 'package:astro_journal/data/models/tonight_observation_session.dart';
import 'package:astro_journal/services/scheduler_engine.dart';
import 'package:astro_journal/data/models/scheduler_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SchedulerEngine', () {
    const engine = SchedulerEngine();

    TonightObservationSession buildSession({
      required DateTime start,
      required DateTime end,
    }) {
      return TonightObservationSession(start: start, end: end);
    }

    ObservationContext buildContext({
      required DateTime start,
      required DateTime end,
    }) {
      return ObservationContext(
        latitude: 37.5,
        longitude: 127.0,
        moonIllumination: 0.1,
        moonAltitude: 10,
        moonAzimuth: 180,
        cloudCover: 0,
        observationStart: start,
        observationEnd: end,
        currentTime: start,
      );
    }

    ScoredObservationTarget buildTarget({
      DateTime? optimalTime,
      int windowMinutes = 180,
      Duration minimumExposure = const Duration(minutes: 30),
      Duration recommendedExposure = const Duration(minutes: 90),
    }) {
      const object = CatalogObject(
        id: 'm42',
        number: 42,
        catalog: CatalogType.messier,
        name: 'M42',
        type: '발광성운',
        constellation: 'Orion',
        ra: '5h 35m',
        dec: '-05° 23m',
        magnitude: '4.0',
      );
      final start = DateTime(2026, 7, 1, 21, 0);
      final optimal = optimalTime ?? DateTime(2026, 7, 1, 22, 20);
      return ScoredObservationTarget(
        object: object,
        window: ObjectObservationWindow(
          currentAltitude: 45,
          currentAzimuth: 180,
          isCurrentlyVisible: true,
          recommendStartTime: start,
          optimalTime: optimal,
          optimalAltitude: 60,
          peakAltitude: 60,
          peakAltitudeTime: optimal,
          observationEndTime: start.add(Duration(minutes: windowMinutes - 10)),
          totalObservableMinutes: windowMinutes,
        ),
        profile: ObjectImagingProfile(
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
        score: 80,
        moonSeparation: 90,
        minimumExposure: minimumExposure,
        recommendedExposure: recommendedExposure,
      );
    }

    RecommendationResult buildResult(ScoredObservationTarget target) {
      return RecommendationResult(
        object: target.object,
        reasons: const [],
        season: '여름',
        score: target.score,
        moonSeparation: target.moonSeparation,
        observationWindow: target.window,
      );
    }

    test('generates 10-minute slots within observation session', () {
      final session = buildSession(
        start: DateTime(2026, 7, 1, 20, 0),
        end: DateTime(2026, 7, 2, 1, 0),
      );

      final slots = engine.generateSlots(session);

      expect(slots, isNotEmpty);
      for (final slot in slots) {
        expect(slot.end.difference(slot.start), SchedulerEngine.slotDuration);
        expect(slot.start.isBefore(session.end), isTrue);
        expect(slot.end.isAfter(session.start), isTrue);
      }
    });

    test('buildSchedule assigns targets with optimal time included', () {
      final start = DateTime(2026, 7, 1, 20, 0);
      final end = DateTime(2026, 7, 2, 0, 30);
      final session = buildSession(start: start, end: end);
      final context = buildContext(start: start, end: end);
      final target = buildTarget();

      final result = engine.buildSchedule(
        SchedulerInput(
          context: context,
          session: session,
          targets: [target],
          resultsById: {target.object.id: buildResult(target)},
          referenceTime: start,
        ),
      );

      expect(result.slots, isNotEmpty);
      expect(result.items, hasLength(1));
      expect(result.items.first.status, isNot(ScheduleItemStatus.excluded));
      expect(
        !result.items.first.optimalTime.isBefore(result.items.first.startTime),
        isTrue,
      );
      expect(
        result.items.first.optimalTime.isBefore(result.items.first.endTime),
        isTrue,
      );
    });

    test('skips assignment when window is shorter than minimum exposure', () {
      final start = DateTime(2026, 7, 1, 20, 0);
      final end = DateTime(2026, 7, 2, 0, 30);
      final session = buildSession(start: start, end: end);
      final context = buildContext(start: start, end: end);
      final target = buildTarget(
        windowMinutes: 20,
        minimumExposure: const Duration(minutes: 30),
      );

      final result = engine.buildSchedule(
        SchedulerInput(
          context: context,
          session: session,
          targets: [target],
          resultsById: {target.object.id: buildResult(target)},
          referenceTime: start,
        ),
      );

      expect(result.items, isEmpty);
    });

    test('does not overlap assignments for two targets', () {
      final start = DateTime(2026, 7, 1, 20, 0);
      final end = DateTime(2026, 7, 2, 2, 0);
      final session = buildSession(start: start, end: end);
      final context = buildContext(start: start, end: end);
      final target1 = buildTarget(
        optimalTime: DateTime(2026, 7, 1, 21, 0),
      );
      const object2 = CatalogObject(
        id: 'm8',
        number: 8,
        catalog: CatalogType.messier,
        name: 'M8',
        type: '발광성운',
        constellation: 'Sagittarius',
        ra: '18h 03m',
        dec: '-24° 23m',
        magnitude: '5.0',
      );
      final target2b = ScoredObservationTarget(
        object: object2,
        window: ObjectObservationWindow(
          currentAltitude: 40,
          currentAzimuth: 180,
          isCurrentlyVisible: true,
          recommendStartTime: DateTime(2026, 7, 1, 21, 0),
          optimalTime: DateTime(2026, 7, 1, 23, 0),
          optimalAltitude: 55,
          peakAltitude: 55,
          peakAltitudeTime: DateTime(2026, 7, 1, 23, 0),
          observationEndTime: DateTime(2026, 7, 2, 1, 0),
          totalObservableMinutes: 240,
        ),
        profile: target1.profile,
        score: 75,
        moonSeparation: 80,
        minimumExposure: const Duration(minutes: 30),
        recommendedExposure: const Duration(minutes: 90),
      );

      final result = engine.buildSchedule(
        SchedulerInput(
          context: context,
          session: session,
          targets: [target1, target2b],
          resultsById: {
            target1.object.id: buildResult(target1),
            target2b.object.id: buildResult(target2b),
          },
          referenceTime: start,
        ),
      );

      expect(result.items.length, greaterThanOrEqualTo(1));
      if (result.items.length == 2) {
        final first = result.items.first;
        final second = result.items.last;
        final overlaps = first.startTime.isBefore(second.endTime) &&
            second.startTime.isBefore(first.endTime);
        expect(overlaps, isFalse);
      }
    });
  });
}

import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/core/constants/imaging_difficulty.dart';
import 'package:astro_journal/core/constants/object_type.dart';
import 'package:astro_journal/core/constants/surface_brightness_class.dart';
import 'package:astro_journal/core/constants/angular_size_class.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/imaging_suitability_assessment.dart';
import 'package:astro_journal/data/models/object_imaging_profile.dart';
import 'package:astro_journal/data/models/object_observation_window.dart';
import 'package:astro_journal/data/models/observation_context.dart';
import 'package:astro_journal/data/models/recommendation_result.dart';
import 'package:astro_journal/data/models/scored_observation_target.dart';
import 'package:astro_journal/data/models/tonight_observation_session.dart';
import 'package:astro_journal/services/equipment/field_orientation_calculator.dart';
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
      Map<DateTime, double> slotObservationScores = const {},
      ImagingSuitabilityAssessment? imagingAssessment,
      DateTime? windowStart,
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
      final start = windowStart ?? DateTime(2026, 7, 1, 21, 0);
      final optimal = optimalTime ?? start.add(const Duration(minutes: 80));
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
          slotObservationScores: slotObservationScores,
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
        imagingAssessment: imagingAssessment,
      );
    }

    ImagingSuitabilityAssessment assessment({
      required TrackingMode trackingMode,
      required Duration dailyDuration,
      TargetPreferredHaWindow? preferredHaWindow,
    }) {
      return ImagingSuitabilityAssessment(
        quality: ExpectedResultQuality.mainStructure,
        filterMode: FilterMode.on,
        trackingMode: trackingMode,
        suitabilityScore: 80,
        scoreMultiplier: 1,
        reason: 'test',
        hasReliableSurfaceBrightness: true,
        recommendedDailyExposure: dailyDuration,
        preferredHaWindow: preferredHaWindow,
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
      final target1 = buildTarget(optimalTime: DateTime(2026, 7, 1, 21, 0));
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
        final overlaps =
            first.startTime.isBefore(second.endTime) &&
            second.startTime.isBefore(first.endTime);
        expect(overlaps, isFalse);
      }
    });

    test('uses only target-visible horizon slots and never bridges a gap', () {
      final start = DateTime(2026, 7, 1, 20);
      final end = DateTime(2026, 7, 2, 0, 30);
      final session = buildSession(start: start, end: end);
      final context = buildContext(start: start, end: end);
      final allowed = <DateTime, double>{
        DateTime(2026, 7, 1, 21, 0): 60,
        DateTime(2026, 7, 1, 21, 10): 65,
        DateTime(2026, 7, 1, 21, 20): 70,
        DateTime(2026, 7, 1, 22, 0): 80,
        DateTime(2026, 7, 1, 22, 10): 90,
        DateTime(2026, 7, 1, 22, 20): 85,
      };
      final target = buildTarget(
        optimalTime: DateTime(2026, 7, 1, 22, 10),
        minimumExposure: const Duration(minutes: 30),
        recommendedExposure: const Duration(minutes: 30),
        slotObservationScores: allowed,
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

      expect(result.items, hasLength(1));
      final item = result.items.single;
      for (
        var slot = item.startTime;
        slot.isBefore(item.endTime);
        slot = slot.add(SchedulerEngine.slotDuration)
      ) {
        expect(allowed, contains(slot));
      }
    });

    test('excludes target when horizon leaves too little usable time', () {
      final start = DateTime(2026, 7, 1, 20);
      final end = DateTime(2026, 7, 2, 0, 30);
      final session = buildSession(start: start, end: end);
      final context = buildContext(start: start, end: end);
      final target = buildTarget(
        minimumExposure: const Duration(minutes: 30),
        recommendedExposure: const Duration(minutes: 30),
        slotObservationScores: {
          DateTime(2026, 7, 1, 22, 0): 80,
          DateTime(2026, 7, 1, 22, 10): 90,
        },
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

    test('Alt-Az uses daily duration and preserves 10-minute slots', () {
      final start = DateTime(2026, 7, 1, 20);
      final end = DateTime(2026, 7, 2, 0, 30);
      final session = buildSession(start: start, end: end);
      final context = buildContext(start: start, end: end);
      final target = buildTarget(
        imagingAssessment: assessment(
          trackingMode: TrackingMode.altAz,
          dailyDuration: const Duration(minutes: 40),
        ),
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

      expect(result.items, hasLength(1));
      expect(
        result.items.single.recommendedDuration,
        const Duration(minutes: 40),
      );
      expect(result.items.single.shootingDuration.inMinutes % 10, 0);
    });

    test('EQ ignores an injected daily limit and keeps total duration', () {
      final start = DateTime(2026, 7, 1, 20);
      final end = DateTime(2026, 7, 2, 0, 30);
      final session = buildSession(start: start, end: end);
      final context = buildContext(start: start, end: end);
      final target = buildTarget(
        imagingAssessment: assessment(
          trackingMode: TrackingMode.eq,
          dailyDuration: const Duration(minutes: 30),
        ),
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

      expect(result.items, hasLength(1));
      expect(
        result.items.single.recommendedDuration,
        const Duration(minutes: 90),
      );
      expect(result.items.single.haMatchQuality, isNull);
    });

    test('Alt-Az prefers matching HA only among feasible target slots', () {
      final start = DateTime(2026, 7, 1, 20);
      final end = DateTime(2026, 7, 2, 0, 30);
      final session = buildSession(start: start, end: end);
      final context = buildContext(start: start, end: end);
      final preferredCenter = DateTime(2026, 7, 1, 22, 10);
      final preferredHa = FieldOrientationCalculator.signedHourAngleHours(
        longitudeDeg: context.longitude,
        time: preferredCenter,
        raHours: 5 + 35 / 60,
      );
      final feasible = <DateTime, double>{
        for (var minute = 0; minute < 60; minute += 10)
          DateTime(2026, 7, 1, 22).add(Duration(minutes: minute)): 70,
      };
      final target = buildTarget(
        optimalTime: DateTime(2026, 7, 1, 21),
        minimumExposure: const Duration(minutes: 30),
        recommendedExposure: const Duration(minutes: 30),
        slotObservationScores: feasible,
        imagingAssessment: assessment(
          trackingMode: TrackingMode.altAz,
          dailyDuration: const Duration(minutes: 30),
          preferredHaWindow: TargetPreferredHaWindow(
            startHours: preferredHa - 0.25,
            endHours: preferredHa + 0.25,
            centerHours: preferredHa,
            durationMinutes: 30,
          ),
        ),
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

      expect(result.items, hasLength(1));
      final item = result.items.single;
      expect(item.haMatchQuality, isNotNull);
      expect(item.haMatchQuality!, greaterThan(90));
      for (
        var slot = item.startTime;
        slot.isBefore(item.endTime);
        slot = slot.add(SchedulerEngine.slotDuration)
      ) {
        expect(feasible, contains(slot));
      }
    });

    test('nearby dates schedule the same target at a similar HA', () {
      final firstSession = buildSession(
        start: DateTime(2026, 7, 1, 20),
        end: DateTime(2026, 7, 2, 0, 30),
      );
      final secondSession = buildSession(
        start: DateTime(2026, 7, 2, 19, 50),
        end: DateTime(2026, 7, 3, 0, 20),
      );
      final firstContext = buildContext(
        start: firstSession.start,
        end: firstSession.end,
      );
      final secondContext = buildContext(
        start: secondSession.start,
        end: secondSession.end,
      );
      final preferredCenter = DateTime(2026, 7, 1, 22, 10);
      final preferredHa = FieldOrientationCalculator.signedHourAngleHours(
        longitudeDeg: firstContext.longitude,
        time: preferredCenter,
        raHours: 5 + 35 / 60,
      );
      final preferredWindow = TargetPreferredHaWindow(
        startHours: preferredHa - 0.25,
        endHours: preferredHa + 0.25,
        centerHours: preferredHa,
        durationMinutes: 30,
      );

      ScoredObservationTarget targetFor(DateTime dayStart) => buildTarget(
            windowStart: dayStart,
            minimumExposure: const Duration(minutes: 30),
            recommendedExposure: const Duration(minutes: 30),
            imagingAssessment: assessment(
              trackingMode: TrackingMode.altAz,
              dailyDuration: const Duration(minutes: 30),
              preferredHaWindow: preferredWindow,
            ),
          );

      final firstTarget = targetFor(DateTime(2026, 7, 1, 21));
      final secondTarget = targetFor(DateTime(2026, 7, 2, 20, 50));
      final first = engine.buildSchedule(
        SchedulerInput(
          context: firstContext,
          session: firstSession,
          targets: [firstTarget],
          resultsById: {
            firstTarget.object.id: buildResult(firstTarget),
          },
          referenceTime: firstSession.start,
        ),
      );
      final second = engine.buildSchedule(
        SchedulerInput(
          context: secondContext,
          session: secondSession,
          targets: [secondTarget],
          resultsById: {
            secondTarget.object.id: buildResult(secondTarget),
          },
          referenceTime: secondSession.start,
        ),
      );

      expect(first.items, hasLength(1));
      expect(second.items, hasLength(1));
      double scheduledHa(ScheduleItem item, ObservationContext context) {
        final center = item.startTime.add(
          Duration(minutes: item.shootingDuration.inMinutes ~/ 2),
        );
        return FieldOrientationCalculator.signedHourAngleHours(
          longitudeDeg: context.longitude,
          time: center,
          raHours: 5 + 35 / 60,
        );
      }

      expect(
        FieldOrientationCalculator.hourAngleDistanceHours(
          scheduledHa(first.items.single, firstContext),
          scheduledHa(second.items.single, secondContext),
        ),
        lessThanOrEqualTo(0.2),
      );
    });
  });
}

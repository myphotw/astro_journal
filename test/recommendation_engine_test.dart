import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/core/constants/imaging_recommendation_rules.dart';
import 'package:astro_journal/core/constants/recommendation_priority_mode.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/observation_context.dart';
import 'package:astro_journal/data/models/observation_feasibility_reason.dart';
import 'package:astro_journal/data/models/observation_feasibility_result.dart';
import 'package:astro_journal/data/models/observation_status.dart';
import 'package:astro_journal/data/models/tonight_observation_session.dart';
import 'package:astro_journal/services/celestial_position_service.dart';
import 'package:astro_journal/services/exposure_policy.dart';
import 'package:astro_journal/services/object_imaging_profile_provider.dart';
import 'package:astro_journal/services/recommendation_engine.dart';
import 'package:astro_journal/services/recommendation_settings_service.dart';
import 'package:astro_journal/services/scheduler_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RecommendationEngine', () {
    late RecommendationEngine engine;

    setUp(() {
      engine = RecommendationEngine(
        CelestialPositionService(),
        const ExposurePolicy(),
        const ObjectImagingProfileProvider(),
        const SchedulerEngine(),
      );
    });

    ObservationContext buildContext({int? bortle}) {
      return ObservationContext(
        latitude: 37.5,
        longitude: 127.0,
        bortle: bortle ?? 2,
        brightness: 0.5,
        moonIllumination: 0.1,
        moonAltitude: -10,
        moonAzimuth: 180,
        cloudCover: 0,
        observationStart: DateTime(2026, 7, 20, 21, 0),
        observationEnd: DateTime(2026, 7, 21, 5, 0),
        currentTime: DateTime(2026, 7, 20, 22, 0),
      );
    }

    TonightObservationSession buildSession() {
      return TonightObservationSession(
        start: DateTime(2026, 7, 20, 21, 0),
        end: DateTime(2026, 7, 21, 5, 0),
      );
    }

    CatalogObject buildObject({
      required String id,
      required int number,
      required String ra,
      required String dec,
      required String type,
      bool captured = false,
    }) {
      return CatalogObject(
        id: id,
        number: number,
        catalog: CatalogType.messier,
        name: 'M$number',
        type: type,
        constellation: 'Test',
        ra: ra,
        dec: dec,
        magnitude: '5.0',
        captured: captured,
      );
    }

    test('still recommends when observation status is unavailable', () async {
      final session = buildSession();

      final result = await engine.build(
        catalog: [
          buildObject(
            id: 'm8',
            number: 8,
            ra: '18h 03m',
            dec: '-24° 23m',
            type: '발광성운',
          ),
        ],
        settings: RecommendationSettings.defaults,
        context: buildContext().copyWith(
          observationStatus: ObservationStatus.unavailable,
          statusUserMessage: '구름이 너무 많습니다.',
        ),
        session: session,
        limit: 10,
      );

      // 기상 관측 불가여도 천체 기준 추천은 계속 제공한다.
      expect(result.recommendations, isNotEmpty);
      expect(result.recommendations.first.object.id, 'm8');
    });

    test('ignores infeasible weather slots when unavailable', () async {
      final session = buildSession();
      final infeasibleSlots = <DateTime, ObservationFeasibilityResult>{
        for (var hour = 21; hour <= 23; hour++)
          DateTime(2026, 7, 20, hour, 0): const ObservationFeasibilityResult.infeasible(
            reason: '구름량 85%',
            failedConditions: [ObservationFeasibilityReason.cloudTooHigh],
          ),
        for (var hour = 0; hour <= 4; hour++)
          DateTime(2026, 7, 21, hour, 0): const ObservationFeasibilityResult.infeasible(
            reason: '구름량 85%',
            failedConditions: [ObservationFeasibilityReason.cloudTooHigh],
          ),
      };

      final result = await engine.build(
        catalog: [
          buildObject(
            id: 'm8',
            number: 8,
            ra: '18h 03m',
            dec: '-24° 23m',
            type: '발광성운',
          ),
        ],
        settings: RecommendationSettings.defaults,
        context: buildContext().copyWith(
          siteSlotFeasibility: infeasibleSlots,
          observationStatus: ObservationStatus.unavailable,
          statusUserMessage: '구름이 너무 많습니다.',
        ),
        session: session,
        limit: 10,
      );

      expect(result.recommendations, isNotEmpty);
      expect(result.recommendations.first.object.id, 'm8');
    });

    test('returns recommendations with observation windows for session', () async {
      final result = await engine.build(
        catalog: [
          buildObject(
            id: 'm8',
            number: 8,
            ra: '18h 03m',
            dec: '-24° 23m',
            type: '발광성운',
          ),
        ],
        settings: RecommendationSettings.defaults,
        context: buildContext(),
        session: buildSession(),
        limit: 4,
      );

      expect(result.recommendations, isNotEmpty);
      expect(result.recommendations.first.observationWindow, isNotNull);
      expect(result.scheduleResult.slots, isNotEmpty);
    });

    test('uncaptured-first mode ranks uncaptured targets ahead', () async {
      final catalog = [
        buildObject(
          id: 'm8',
          number: 8,
          ra: '18h 03m',
          dec: '-24° 23m',
          type: '발광성운',
          captured: true,
        ),
        buildObject(
          id: 'm20',
          number: 20,
          ra: '18h 02m',
          dec: '-23° 02m',
          type: '발광성운',
          captured: false,
        ),
      ];

      final result = await engine.build(
        catalog: catalog,
        settings: RecommendationSettings.defaults.copyWith(
          priorityMode: RecommendationPriorityMode.uncapturedFirst,
        ),
        context: buildContext(),
        session: buildSession(),
        limit: 10,
      );

      expect(result.allRecommendations.length, greaterThanOrEqualTo(2));
      expect(result.allRecommendations.first.object.captured, isFalse);
    });

    test('keeps IC1396 when bortle is seoul-like (type default)', () async {
      final result = await engine.build(
        catalog: [
          buildObject(
            id: 'ic1396',
            number: 1396,
            ra: '20h 22m',
            dec: '+57° 30m',
            type: '발광성운',
          ),
        ],
        settings: RecommendationSettings.defaults,
        context: buildContext(bortle: ImagingRecommendationRules.seoulBortle),
        session: buildSession(),
        limit: 4,
      );

      expect(result.recommendations, hasLength(1));
    });

    test('M42 remains recommended at seoul-like bortle', () async {
      final winterContext = ObservationContext(
        latitude: 37.5,
        longitude: 127.0,
        bortle: ImagingRecommendationRules.seoulBortle,
        brightness: 8.5,
        moonIllumination: 0.1,
        moonAltitude: -10,
        moonAzimuth: 180,
        cloudCover: 0,
        observationStart: DateTime(2026, 1, 15, 21, 0),
        observationEnd: DateTime(2026, 1, 16, 5, 0),
        currentTime: DateTime(2026, 1, 15, 22, 0),
      );
      final winterSession = TonightObservationSession(
        start: DateTime(2026, 1, 15, 21, 0),
        end: DateTime(2026, 1, 16, 5, 0),
      );

      final result = await engine.build(
        catalog: [
          buildObject(
            id: 'm42',
            number: 42,
            ra: '5h 35m',
            dec: '-05° 23m',
            type: '발광성운',
          ),
        ],
        settings: RecommendationSettings.defaults,
        context: winterContext,
        session: winterSession,
        limit: 1,
      );

      expect(result.recommendations, hasLength(1));
    });

    test('schedule items stay sorted by start time', () async {
      final result = await engine.build(
        catalog: [
          buildObject(
            id: 'm8',
            number: 8,
            ra: '18h 03m',
            dec: '-24° 23m',
            type: '발광성운',
          ),
          buildObject(
            id: 'm20',
            number: 20,
            ra: '18h 02m',
            dec: '-23° 02m',
            type: '발광성운',
          ),
        ],
        settings: RecommendationSettings.defaults,
        context: buildContext(),
        session: buildSession(),
        limit: 10,
      );

      if (result.scheduleItems.length >= 2) {
        for (var i = 1; i < result.scheduleItems.length; i++) {
          expect(
            result.scheduleItems[i].startTime.isAfter(
                  result.scheduleItems[i - 1].startTime,
                ) ||
                result.scheduleItems[i].startTime.isAtSameMomentAs(
                  result.scheduleItems[i - 1].startTime,
                ),
            isTrue,
          );
        }
      }
    });

    test('observation window includes optimalTime from quality scoring', () async {
      final result = await engine.build(
        catalog: [
          buildObject(
            id: 'm8',
            number: 8,
            ra: '18h 03m',
            dec: '-24° 23m',
            type: '발광성운',
          ),
        ],
        settings: RecommendationSettings.defaults,
        context: buildContext(),
        session: buildSession(),
        limit: 1,
      );

      expect(result.recommendations, isNotEmpty);
      final window = result.recommendations.first.observationWindow;
      expect(window?.optimalTime, isNotNull);
      expect(window?.optimalAltitude, isNotNull);
    });
  });
}

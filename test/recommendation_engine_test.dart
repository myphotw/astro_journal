import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/core/constants/imaging_recommendation_rules.dart';
import 'package:astro_journal/core/constants/recommendation_priority_mode.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/imaging_suitability_assessment.dart';
import 'package:astro_journal/data/models/observation_context.dart';
import 'package:astro_journal/data/models/observation_feasibility_reason.dart';
import 'package:astro_journal/data/models/observation_feasibility_result.dart';
import 'package:astro_journal/data/models/observation_quality_index.dart';
import 'package:astro_journal/data/models/observation_status.dart';
import 'package:astro_journal/data/models/recommendation_build_result.dart';
import 'package:astro_journal/data/models/recommendation_result.dart';
import 'package:astro_journal/data/models/horizon_point.dart';
import 'package:astro_journal/data/models/site_horizon_profile.dart';
import 'package:astro_journal/data/models/shooting_record.dart';
import 'package:astro_journal/data/models/tonight_observation_session.dart';
import 'package:astro_journal/data/models/weather_forecast_slot.dart';
import 'package:astro_journal/services/celestial_position_service.dart';
import 'package:astro_journal/services/exposure_policy.dart';
import 'package:astro_journal/services/object_imaging_profile_provider.dart';
import 'package:astro_journal/services/observation_score_service.dart';
import 'package:astro_journal/services/recommendation_engine.dart';
import 'package:astro_journal/services/recommendation_settings_service.dart';
import 'package:astro_journal/services/scheduler_engine.dart';
import 'package:astro_journal/services/session_weather_index.dart';
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

    ObservationWindow buildSiteWeatherWindow(DateTime time) {
      final forecast = WeatherForecastSlot(
        time: time,
        temperature: 20,
        humidity: 50,
        windSpeed: 1,
        cloudCoverage: 0,
        visibility: 10000,
        pop: 0,
        description: '맑음',
        icon: '01n',
      );
      final slot = TonightObservationSlot(
        label: ObservationScoreService.formatHourLabel(time),
        targetTime: time,
        forecast: forecast,
        moon: ObservationScoreService.computeMoonInfo(time),
        feasibility: const ObservationFeasibilityResult.observable(),
        qualityIndex: const ObservationQualityIndex(oqi: 90, components: []),
      );
      return ObservationScoreService.findObservationWindow([slot])!;
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
      final catalog = [
        buildObject(
          id: 'm8',
          number: 8,
          ra: '18h 03m',
          dec: '-24° 23m',
          type: '발광성운',
        ),
      ];

      final clearResult = await engine.build(
        catalog: catalog,
        settings: RecommendationSettings.defaults,
        context: buildContext(),
        session: session,
        limit: 10,
      );

      final result = await engine.build(
        catalog: catalog,
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
      expect(
        result.recommendations.first.score,
        clearResult.recommendations.first.score,
      );
    });

    test('ignores infeasible weather slots when unavailable', () async {
      final session = buildSession();
      final infeasibleSlots = <DateTime, ObservationFeasibilityResult>{
        for (var hour = 21; hour <= 23; hour++)
          DateTime(
            2026,
            7,
            20,
            hour,
            0,
          ): const ObservationFeasibilityResult.infeasible(
            reason: '구름량 85%',
            failedConditions: [ObservationFeasibilityReason.cloudTooHigh],
          ),
        for (var hour = 0; hour <= 4; hour++)
          DateTime(
            2026,
            7,
            21,
            hour,
            0,
          ): const ObservationFeasibilityResult.infeasible(
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

    test(
      'bad weather remains reference data without removing a target',
      () async {
        final session = buildSession();
        final forecast = WeatherForecastSlot(
          time: session.start,
          temperature: 20,
          humidity: 95,
          windSpeed: 18,
          cloudCoverage: 100,
          visibility: 1000,
          pop: 90,
          rainVolumeMm: 2,
          description: '비',
          icon: '10n',
        );

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
            cloudCover: 100,
            observationStatus: ObservationStatus.limited,
            sessionWeather: SessionWeatherIndex.build(
              session: session,
              forecasts: [forecast],
            ),
          ),
          session: session,
          limit: 10,
        );

        expect(result.recommendations, isNotEmpty);
        expect(result.recommendations.first.object.id, 'm8');
        expect(result.recommendations.first.observationWindow, isNotNull);
      },
    );

    test(
      'site weather window does not remove evening or post-midnight targets',
      () async {
        final session = buildSession();
        final catalog = [
          buildObject(
            id: 'evening-target',
            number: 8,
            ra: '18h 03m',
            dec: '-24° 23m',
            type: '발광성운',
          ),
          buildObject(
            id: 'post-midnight-target',
            number: 42,
            ra: '05h 35m',
            dec: '-05° 23m',
            type: '발광성운',
          ),
        ];

        final withoutWeatherWindow = await engine.build(
          catalog: catalog,
          settings: RecommendationSettings.defaults,
          context: buildContext(),
          session: session,
          limit: 10,
        );
        final withWeatherWindow = await engine.build(
          catalog: catalog,
          settings: RecommendationSettings.defaults,
          context: buildContext().copyWith(
            observationWindow: buildSiteWeatherWindow(session.start),
          ),
          session: session,
          limit: 10,
        );

        List<String> ids(RecommendationBuildResult result) => result
            .allRecommendations
            .map((recommendation) => recommendation.object.id)
            .toList();

        expect(ids(withoutWeatherWindow), containsAll(ids(withWeatherWindow)));
        expect(ids(withWeatherWindow), contains('evening-target'));
        expect(ids(withWeatherWindow), contains('post-midnight-target'));
      },
    );

    test(
      'shooting fit and tonight recommendation both ignore weather',
      () async {
        final session = buildSession();
        final object = buildObject(
          id: 'm8-weather-separation',
          number: 8,
          ra: '18h 03m',
          dec: '-24° 23m',
          type: '발광성운',
        );
        List<WeatherForecastSlot> forecasts({required int cloud}) => [
          for (var offset = 0; offset <= 6; offset += 3)
            WeatherForecastSlot(
              time: session.start.add(Duration(hours: offset)),
              temperature: 20,
              humidity: cloud == 0 ? 50 : 95,
              windSpeed: cloud == 0 ? 1.5 : 18,
              cloudCoverage: cloud,
              visibility: cloud == 0 ? 10000 : 1000,
              pop: cloud == 0 ? 0 : 90,
              description: cloud == 0 ? '맑음' : '비',
              icon: cloud == 0 ? '01n' : '10n',
            ),
        ];

        Future<RecommendationResult> buildWith(
          List<WeatherForecastSlot>? weather,
        ) async {
          final result = await engine.build(
            catalog: [object],
            settings: RecommendationSettings.defaults,
            context: buildContext().copyWith(
              sessionWeather: weather == null
                  ? null
                  : SessionWeatherIndex.build(
                      session: session,
                      forecasts: weather,
                    ),
            ),
            session: session,
            limit: 10,
          );
          return result.recommendations.single;
        }

        final clear = await buildWith(forecasts(cloud: 0));
        final overcast = await buildWith(forecasts(cloud: 99));
        final unknown = await buildWith(null);

        for (final result in [overcast, unknown]) {
          expect(
            result.imagingAssessment?.quality,
            clear.imagingAssessment?.quality,
          );
          expect(
            result.imagingAssessment?.suitabilityScore,
            clear.imagingAssessment?.suitabilityScore,
          );
          expect(
            result.imagingAssessment?.scoreMultiplier,
            clear.imagingAssessment?.scoreMultiplier,
          );
        }
        expect(overcast.score, clear.score);
        expect(unknown.score, clear.score);
        expect(unknown.observationWindow?.hasWeatherData, isFalse);
        expect(unknown.observationWindow?.optimalWeatherScore, isNull);
      },
    );

    test(
      'returns recommendations with observation windows for session',
      () async {
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
      },
    );

    test(
      'capture history does not change candidates scores order or schedule',
      () async {
        final uncapturedCatalog = [
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
        ];
        final capturedCatalog = [
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
          ),
        ];
        final capturedAt = DateTime(2026, 7, 19, 22);
        final settings = RecommendationSettings.defaults.copyWith(
          priorityMode: RecommendationPriorityMode.uncapturedFirst,
        );

        final uncapturedResult = await engine.build(
          catalog: uncapturedCatalog,
          settings: settings,
          context: buildContext(),
          session: buildSession(),
          limit: 10,
        );
        final capturedResult = await engine.build(
          catalog: capturedCatalog,
          settings: settings,
          context: buildContext().copyWith(
            shootingRecords: [
              ShootingRecord(
                id: 'record-m8',
                celestialObjectId: 'm8',
                capturedAt: capturedAt,
                createdAt: capturedAt,
              ),
            ],
          ),
          session: buildSession(),
          limit: 10,
        );

        List<String> recommendationIds(RecommendationBuildResult result) =>
            result.allRecommendations
                .map<String>((item) => item.object.id)
                .toList();
        List<String> scheduleIds(RecommendationBuildResult result) => result
            .scheduleItems
            .map<String>((item) => item.catalogObject.id)
            .toList();
        Map<String, double> scores(RecommendationBuildResult result) => {
          for (final item in result.allRecommendations)
            item.object.id: item.score,
        };

        expect(
          recommendationIds(capturedResult),
          recommendationIds(uncapturedResult),
        );
        expect(scores(capturedResult), scores(uncapturedResult));
        expect(scheduleIds(capturedResult), scheduleIds(uncapturedResult));
        expect(
          capturedResult.allRecommendations
              .expand((item) => item.reasons)
              .map((reason) => reason.label),
          isNot(contains('✓ 미촬영 대상')),
        );
      },
    );

    test(
      'weather and capture history matrix keeps ranking schedule and windows',
      () async {
        final session = buildSession();
        final catalog = [
          buildObject(
            id: 'm8-matrix',
            number: 8,
            ra: '18h 03m',
            dec: '-24° 23m',
            type: '발광성운',
            captured: true,
          ),
          buildObject(
            id: 'm20-matrix',
            number: 20,
            ra: '18h 02m',
            dec: '-23° 02m',
            type: '발광성운',
          ),
        ];
        final capturedAt = DateTime(2026, 7, 19, 22);

        List<WeatherForecastSlot> forecasts({required int cloud}) => [
          for (var offset = 0; offset <= 6; offset += 3)
            WeatherForecastSlot(
              time: session.start.add(Duration(hours: offset)),
              temperature: 20,
              humidity: cloud == 0 ? 50 : 95,
              windSpeed: cloud == 0 ? 1.5 : 18,
              cloudCoverage: cloud,
              visibility: cloud == 0 ? 10000 : 1000,
              pop: cloud == 0 ? 0 : 90,
              description: cloud == 0 ? '맑음' : '비',
              icon: cloud == 0 ? '01n' : '10n',
            ),
        ];

        Future<RecommendationBuildResult> buildWith(
          List<WeatherForecastSlot>? weather,
        ) {
          return engine.build(
            catalog: catalog,
            settings: RecommendationSettings.defaults,
            context: buildContext().copyWith(
              cloudCover: weather == null ? 0 : weather.first.cloudCoverage,
              sessionWeather: weather == null
                  ? null
                  : SessionWeatherIndex.build(
                      session: session,
                      forecasts: weather,
                    ),
              shootingRecords: [
                ShootingRecord(
                  id: 'record-m8-matrix',
                  celestialObjectId: 'm8-matrix',
                  capturedAt: capturedAt,
                  createdAt: capturedAt,
                ),
              ],
            ),
            session: session,
            limit: 10,
          );
        }

        final clear = await buildWith(forecasts(cloud: 0));
        final overcast = await buildWith(forecasts(cloud: 100));
        final unknown = await buildWith(null);

        List<Object?> recommendationSnapshot(
          RecommendationBuildResult result,
        ) => result.allRecommendations
            .map(
              (item) => (
                item.object.id,
                item.score,
                item.observationWindow?.optimalStartTime,
                item.observationWindow?.optimalEndTime,
                item.starCount,
              ),
            )
            .toList();
        List<Object?> scheduleSnapshot(RecommendationBuildResult result) =>
            result.scheduleItems
                .map(
                  (item) =>
                      (item.catalogObject.id, item.startTime, item.endTime),
                )
                .toList();

        expect(clear.allRecommendations, isNotEmpty);
        for (final result in [overcast, unknown]) {
          expect(recommendationSnapshot(result), recommendationSnapshot(clear));
          expect(scheduleSnapshot(result), scheduleSnapshot(clear));
        }
      },
    );

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

    test(
      'observation window includes optimalTime from quality scoring',
      () async {
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
        expect(result.recommendations.first.imagingAssessment, isNotNull);
        expect(result.recommendations.first.recommendedExposure, isNotNull);
      },
    );

    test('equipment fit resolver downrates a poorly framed target', () async {
      final baseline = await engine.build(
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
      final poorFit = await engine.build(
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
        equipmentFitResolver: (_, _) =>
            const ImagingEquipmentFit(score: 15, screenFillPercent: 2),
      );

      expect(
        poorFit.recommendations.single.score,
        lessThan(baseline.recommendations.single.score),
      );
    });

    test(
      'extremely tiny equipment fit is excluded from imaging recommendations',
      () async {
        final result = await engine.build(
          catalog: [
            buildObject(
              id: 'ngc7009',
              number: 7009,
              ra: '21h 04m',
              dec: '-11° 22m',
              type: '행성상성운',
              captured: true,
            ),
          ],
          settings: RecommendationSettings.defaults,
          context: buildContext(),
          session: buildSession(),
          limit: 1,
          equipmentFitResolver: (_, _) => const ImagingEquipmentFit(
            score: 5,
            screenFillPercent: 1,
            equipmentId: 's30-pro',
            equipmentName: 'S30 Pro',
          ),
        );

        expect(result.recommendations, isEmpty);
        expect(result.scheduleItems, isEmpty);
        expect(
          result.exclusionReasons,
          contains('현재 장비에서 의미 있는 결과를 얻기 어려운 대상 1개를 제외했습니다'),
        );
      },
    );

    test('site horizon applies equally to Alt-Az and EQ planning', () async {
      final context = buildContext().copyWith(
        horizonProfile: const SiteHorizonProfile(
          points: [
            HorizonPoint(
              id: 'closed-horizon',
              observationSiteId: 'site',
              azimuth: 0,
              minAltitude: 90,
            ),
          ],
        ),
      );
      final catalog = [
        buildObject(
          id: 'm8',
          number: 8,
          ra: '18h 03m',
          dec: '-24° 23m',
          type: '발광성운',
          captured: true,
        ),
      ];

      for (final trackingMode in [TrackingMode.altAz, TrackingMode.eq]) {
        final result = await engine.build(
          catalog: catalog,
          settings: RecommendationSettings.defaults,
          context: context,
          session: buildSession(),
          trackingMode: trackingMode,
        );
        expect(result.recommendations, isEmpty);
        expect(result.scheduleItems, isEmpty);
      }
    });

    test(
      'captured target still requires valid astronomical coordinates',
      () async {
        final result = await engine.build(
          catalog: [
            buildObject(
              id: 'captured-invalid-position',
              number: 999,
              ra: 'invalid',
              dec: '-24° 23m',
              type: '발광성운',
              captured: true,
            ),
          ],
          settings: RecommendationSettings.defaults,
          context: buildContext(),
          session: buildSession(),
        );

        expect(result.recommendations, isEmpty);
        expect(result.scheduleItems, isEmpty);
      },
    );
  });
}

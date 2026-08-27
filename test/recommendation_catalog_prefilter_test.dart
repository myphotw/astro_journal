import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/object_imaging_profile.dart';
import 'package:astro_journal/data/models/object_observation_window.dart';
import 'package:astro_journal/data/models/observation_context.dart';
import 'package:astro_journal/data/models/tonight_observation_session.dart';
import 'package:astro_journal/services/celestial_position_service.dart';
import 'package:astro_journal/services/exposure_policy.dart';
import 'package:astro_journal/services/object_imaging_profile_provider.dart';
import 'package:astro_journal/services/recommendation/observation_window_calculator.dart';
import 'package:astro_journal/services/recommendation_engine.dart';
import 'package:astro_journal/services/recommendation_settings_service.dart';
import 'package:astro_journal/services/scheduler_engine.dart';
import 'package:flutter_test/flutter_test.dart';

class _CountingWindowCalculator extends ObservationWindowCalculator {
  _CountingWindowCalculator() : super(CelestialPositionService());

  final List<CatalogType> calls = [];

  @override
  ObservationWindowCalculation calculate({
    required CatalogObject object,
    required ObjectImagingProfile profile,
    required ObservationContext context,
    required RecommendationSettings settings,
    required TonightObservationSession session,
    required DateTime referenceTime,
    required Duration minimumExposure,
    required Duration recommendedExposure,
    ObservationWindowPerformance? performance,
    ObservationWindowSharedCache? sharedCache,
  }) {
    calls.add(object.catalog);
    return ObservationWindowCalculation(
      exclusion: ObservationWindowExclusion.none,
      moonSeparation: 120,
      window: ObjectObservationWindow(
        currentAltitude: 55,
        currentAzimuth: 180,
        isCurrentlyVisible: true,
        recommendStartTime: session.start,
        optimalStartTime: session.start,
        optimalEndTime: session.start.add(const Duration(hours: 1)),
        optimalTime: session.start,
        optimalAltitude: 55,
        peakAltitude: 55,
        peakAltitudeTime: session.start,
        observationEndTime: session.start.add(const Duration(hours: 1)),
        totalObservableMinutes: 60,
        remainingVisibleMinutes: 60,
        moonSafeMinutes: 60,
        bestObservationScore: 80,
        slotObservationScores: {
          for (var index = 0; index < 6; index++)
            session.start.add(Duration(minutes: index * 10)): 80,
        },
      ),
    );
  }
}

void main() {
  final session = TonightObservationSession(
    start: DateTime(2026, 8, 27, 20),
    end: DateTime(2026, 8, 28, 5),
  );
  final context = ObservationContext(
    latitude: 37.5,
    longitude: 127,
    brightness: 0.5,
    bortle: 2,
    moonIllumination: 0,
    moonAltitude: -10,
    moonAzimuth: 180,
    cloudCover: 0,
    observationStart: session.start,
    observationEnd: session.end,
    currentTime: session.start,
  );
  final catalog = <CatalogObject>[
    _object('M1', CatalogType.messier, 1),
    _object('NGC1', CatalogType.ngc, 1),
    _object('IC1', CatalogType.ic, 1),
    _object('C1', CatalogType.caldwell, 1),
    _object('solar_8', CatalogType.solar, 8),
    _object(
      'solar_11',
      CatalogType.solar,
      11,
      type: '혜성',
      tags: const ['record_only', 'dynamic_ephemeris'],
    ),
  ];

  Future<({List<CatalogType> calls, List<CatalogType> scheduled})> run(
    Set<CatalogType> enabled,
  ) async {
    final calculator = _CountingWindowCalculator();
    final engine = RecommendationEngine(
      CelestialPositionService(),
      const ExposurePolicy(),
      const ObjectImagingProfileProvider(),
      const SchedulerEngine(),
      windowCalculator: calculator,
    );
    final result = await engine.build(
      catalog: catalog,
      settings: RecommendationSettings(
        enabledCatalogs: enabled,
        azimuthStart: 0,
        azimuthEnd: 359,
        minAltitude: 0,
        maxAltitude: 90,
      ),
      context: context,
      session: session,
      referenceTime: session.start,
    );
    return (
      calls: calculator.calls,
      scheduled: result.scheduleResult.targets
          .map((target) => target.object.catalog)
          .toList(),
    );
  }

  test(
    'Messier only excludes every other catalog before window calculation',
    () async {
      final result = await run({CatalogType.messier});

      expect(result.calls, [CatalogType.messier]);
      expect(result.scheduled, everyElement(CatalogType.messier));
    },
  );

  test('NGC only calculates NGC windows', () async {
    final result = await run({CatalogType.ngc});

    expect(result.calls, [CatalogType.ngc]);
    expect(result.scheduled, everyElement(CatalogType.ngc));
  });

  test('Messier and Caldwell calculate only the selected groups', () async {
    final result = await run({CatalogType.messier, CatalogType.caldwell});

    expect(result.calls, [CatalogType.messier, CatalogType.caldwell]);
    expect(
      result.scheduled,
      everyElement(isIn({CatalogType.messier, CatalogType.caldwell})),
    );
  });

  test('all selected preserves every eligible catalog', () async {
    final result = await run({
      CatalogType.messier,
      CatalogType.ngc,
      CatalogType.ic,
      CatalogType.caldwell,
    });

    expect(result.calls, [
      CatalogType.messier,
      CatalogType.ngc,
      CatalogType.ic,
      CatalogType.caldwell,
    ]);
  });

  test(
    'Solar planets and record-only comets never enter recommendation',
    () async {
      final result = await run({CatalogType.solar});

      expect(result.calls, isEmpty);
      expect(result.scheduled, isEmpty);
    },
  );
}

CatalogObject _object(
  String id,
  CatalogType catalog,
  int number, {
  String type = '발광성운',
  List<String> tags = const [],
}) {
  return CatalogObject(
    id: id,
    number: number,
    catalog: catalog,
    name: id,
    type: type,
    constellation: 'Test',
    ra: '18h 03m',
    dec: '-24° 23m',
    magnitude: '5.0',
    tags: tags,
  );
}

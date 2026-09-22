import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/data/models/blocked_azimuth_range.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/horizon_point.dart';
import 'package:astro_journal/data/models/object_imaging_profile.dart';
import 'package:astro_journal/data/models/observation_context.dart';
import 'package:astro_journal/data/models/observation_site.dart';
import 'package:astro_journal/data/models/shooting_record.dart';
import 'package:astro_journal/data/models/tonight_observation_session.dart';
import 'package:astro_journal/data/models/weather_data.dart';
import 'package:astro_journal/data/models/weather_forecast_slot.dart';
import 'package:astro_journal/data/repositories/bortle_repository.dart';
import 'package:astro_journal/services/celestial_position_service.dart';
import 'package:astro_journal/services/exposure_policy.dart';
import 'package:astro_journal/services/location_service.dart';
import 'package:astro_journal/services/object_imaging_profile_provider.dart';
import 'package:astro_journal/services/observation_condition_service.dart';
import 'package:astro_journal/services/observation_engine.dart';
import 'package:astro_journal/services/recommendation/observation_window_calculator.dart';
import 'package:astro_journal/services/recommendation_engine.dart';
import 'package:astro_journal/services/recommendation_settings_service.dart';
import 'package:astro_journal/services/scheduler_engine.dart';
import 'package:astro_journal/services/target_imaging_availability_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _UnusedBortleRepository implements BortleRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ObservationEngine extends ObservationEngine {
  _ObservationEngine()
    : super(
        ObservationConditionService(
          LocationService(),
          _UnusedBortleRepository(),
        ),
        CelestialPositionService(),
      );

  @override
  Future<ObservationContext> buildContext({
    required double latitude,
    required double longitude,
    required DateTime currentTime,
    WeatherData? weather,
    List<WeatherForecastSlot> forecasts = const [],
    TonightObservationSession? session,
    List<CatalogObject>? catalog,
    List<ShootingRecord>? shootingRecords,
  }) async {
    final resolvedSession =
        session ??
        TonightObservationSession(
          start: currentTime,
          end: currentTime.add(const Duration(hours: 8)),
        );
    return ObservationContext(
      latitude: latitude,
      longitude: longitude,
      bortle: 8,
      moonIllumination: 0,
      moonAltitude: -10,
      moonAzimuth: 180,
      cloudCover: 0,
      observationStart: resolvedSession.start,
      observationEnd: resolvedSession.end,
      currentTime: currentTime,
      catalog: catalog ?? const [],
    );
  }
}

class _CapturingWindowCalculator extends ObservationWindowCalculator {
  _CapturingWindowCalculator() : super(CelestialPositionService());

  final List<RecommendationSettings> settings = [];
  final List<ObservationContext> contexts = [];

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
    ObservationWindowDurationPolicy durationPolicy =
        ObservationWindowDurationPolicy.strict,
    ObservationWindowPerformance? performance,
    ObservationWindowSharedCache? sharedCache,
  }) {
    this.settings.add(settings);
    contexts.add(context);
    return const ObservationWindowCalculation(
      window: null,
      exclusion: ObservationWindowExclusion.noWindow,
      moonSeparation: 90,
    );
  }
}

void main() {
  const object = CatalogObject(
    id: 'm42',
    number: 42,
    catalog: CatalogType.messier,
    name: 'M42',
    type: '발광성운',
    constellation: 'Orion',
    ra: '05h 35m',
    dec: '-05° 23m',
    magnitude: '4.0',
  );

  TargetImagingAvailabilityService buildService(
    _CapturingWindowCalculator calculator,
  ) {
    final positions = CelestialPositionService();
    final recommendation = RecommendationEngine(
      positions,
      ExposurePolicy(),
      const ObjectImagingProfileProvider(),
      const SchedulerEngine(),
      windowCalculator: calculator,
    );
    return TargetImagingAvailabilityService(
      _ObservationEngine(),
      recommendation,
    );
  }

  ObservationSite site({
    List<HorizonPoint> points = const [],
    List<BlockedAzimuthRange> blocked = const [],
  }) => ObservationSite(
    id: 'home',
    name: '집',
    latitude: 37.5,
    longitude: 127,
    defaultMinAltitude: 20,
    defaultMaxAltitude: 64,
    createdAt: DateTime(2026, 9, 3),
    updatedAt: DateTime(2026, 9, 3),
    horizonPoints: points,
    blockedAzimuthRanges: blocked,
  );

  test('directional Horizon replaces legacy Catalog altitude bounds', () async {
    final calculator = _CapturingWindowCalculator();
    await buildService(calculator).evaluate(
      object: object,
      site: site(
        points: const [
          HorizonPoint(
            id: 'south-east',
            observationSiteId: 'home',
            azimuth: 135,
            minAltitude: 7,
            maxAltitude: 65,
          ),
        ],
      ),
      referenceDate: DateTime(2026, 9, 3, 22),
    );

    expect(calculator.settings, isNotEmpty);
    expect(
      calculator.settings,
      everyElement(
        predicate<RecommendationSettings>(
          (value) => value.minAltitude == 0 && value.maxAltitude == 90,
        ),
      ),
    );
    expect(
      calculator.contexts,
      everyElement(
        predicate<ObservationContext>(
          (value) => value.horizonProfile.points.single.minAltitude == 7,
        ),
      ),
    );
  });

  test('legacy Catalog altitude bounds remain when Horizon is empty', () async {
    final calculator = _CapturingWindowCalculator();
    await buildService(calculator).evaluate(
      object: object,
      site: site(),
      referenceDate: DateTime(2026, 9, 3, 22),
    );

    expect(calculator.settings, isNotEmpty);
    expect(
      calculator.settings,
      everyElement(
        predicate<RecommendationSettings>(
          (value) => value.minAltitude == 20 && value.maxAltitude == 64,
        ),
      ),
    );
  });

  test('blocked-only Horizon also replaces legacy Catalog bounds', () async {
    final calculator = _CapturingWindowCalculator();
    await buildService(calculator).evaluate(
      object: object,
      site: site(
        blocked: const [
          BlockedAzimuthRange(
            id: 'west-blocked',
            observationSiteId: 'home',
            startAzimuth: 220,
            endAzimuth: 90,
          ),
        ],
      ),
      referenceDate: DateTime(2026, 9, 3, 22),
    );

    expect(calculator.settings, isNotEmpty);
    expect(calculator.settings.first.minAltitude, 0);
    expect(calculator.settings.first.maxAltitude, 90);
    expect(
      calculator.contexts.first.horizonProfile.blockedRanges,
      hasLength(1),
    );
  });
}

import 'dart:typed_data';

import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/core/constants/equipment_kind.dart';
import 'package:astro_journal/core/constants/equipment_purpose.dart';
import 'package:astro_journal/core/services/observation_context_invalidator.dart';
import 'package:astro_journal/core/services/performance_probe.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/equipment.dart';
import 'package:astro_journal/data/models/imaging_suitability_assessment.dart';
import 'package:astro_journal/data/models/object_observation_window.dart';
import 'package:astro_journal/data/models/observation_context.dart';
import 'package:astro_journal/data/models/observation_site.dart';
import 'package:astro_journal/data/models/recommendation_build_result.dart';
import 'package:astro_journal/data/models/scheduler_models.dart';
import 'package:astro_journal/data/models/shooting_record.dart';
import 'package:astro_journal/data/models/tonight_observation_session.dart';
import 'package:astro_journal/data/models/weather_data.dart';
import 'package:astro_journal/data/models/weather_forecast_slot.dart';
import 'package:astro_journal/data/repositories/bortle_repository.dart';
import 'package:astro_journal/data/repositories/catalog_repository.dart';
import 'package:astro_journal/data/repositories/equipment_repository.dart';
import 'package:astro_journal/data/repositories/observation_site_repository.dart';
import 'package:astro_journal/features/home/viewmodel/home_view_model.dart';
import 'package:astro_journal/features/horizon_scan/models/horizon_scan_sample.dart';
import 'package:astro_journal/features/horizon_scan/models/horizon_scan_session.dart';
import 'package:astro_journal/features/horizon_scan/services/horizon_scan_processor.dart';
import 'package:astro_journal/features/observation_site/viewmodel/active_observation_site_view_model.dart';
import 'package:astro_journal/services/api_key_service.dart';
import 'package:astro_journal/services/celestial_position_service.dart';
import 'package:astro_journal/services/equipment/equipment_recommendation_service.dart';
import 'package:astro_journal/services/exposure_policy.dart';
import 'package:astro_journal/services/location_service.dart';
import 'package:astro_journal/services/object_imaging_profile_provider.dart';
import 'package:astro_journal/services/observation_condition_service.dart';
import 'package:astro_journal/services/observation_engine.dart';
import 'package:astro_journal/services/recommendation_engine.dart';
import 'package:astro_journal/services/recommendation_settings_service.dart';
import 'package:astro_journal/services/scheduler_engine.dart';
import 'package:astro_journal/services/tonight_shooting_plan_service.dart';
import 'package:astro_journal/services/weather_cache_service.dart';
import 'package:astro_journal/services/weather_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _CatalogRepository implements CatalogRepository {
  static const object = CatalogObject(
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

  @override
  Future<List<CatalogObject>> getAll({bool listOnly = true}) async => const [
    object,
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _EquipmentRepository implements EquipmentRepository {
  _EquipmentRepository(this.invalidator);

  final ObservationContextInvalidator invalidator;
  final List<Equipment> items = [];

  @override
  Future<void> save(Equipment equipment) async {
    items.removeWhere((item) => item.id == equipment.id);
    items.add(equipment);
    await invalidator.invalidate(ObservationContextChange.equipment);
  }

  @override
  Future<void> delete(String id) async {
    items.removeWhere((item) => item.id == id);
    await invalidator.invalidate(ObservationContextChange.equipment);
  }

  @override
  Future<List<Equipment>> getAll({bool activeOnly = false}) async => items
      .where((item) => !activeOnly || item.isActive)
      .toList(growable: false);

  @override
  Future<Equipment?> getById(String id) async =>
      items.where((item) => item.id == id).firstOrNull;
}

class _SiteRepository implements ObservationSiteRepository {
  _SiteRepository(this.invalidator, ObservationSite initial)
    : sites = [initial];

  final ObservationContextInvalidator invalidator;
  final List<ObservationSite> sites;

  @override
  Future<List<ObservationSite>> list({bool includeDeleted = false}) async =>
      List.of(sites);

  @override
  Future<void> update(ObservationSite site) async {
    final index = sites.indexWhere((item) => item.id == site.id);
    sites[index] = site;
    await invalidator.invalidate(
      site.horizonPoints.isNotEmpty || sites[index].horizonPoints.isNotEmpty
          ? ObservationContextChange.horizon
          : ObservationContextChange.observationSite,
    );
  }

  @override
  Future<void> markLastUsed(String id, DateTime usedAt) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Settings extends RecommendationSettingsService {
  @override
  Future<RecommendationSettings> load() async =>
      RecommendationSettings.defaults;
}

class _Location extends LocationService {
  @override
  Future<LocationData> getCurrentLocation({
    bool preferLastKnown = false,
    Duration timeLimit = const Duration(seconds: 12),
  }) async => LocationData(
    latitude: 37.5,
    longitude: 127,
    accuracy: 1,
    timestamp: DateTime.now(),
  );
}

class _Weather extends WeatherService {
  _Weather() : super(ApiKeyService());

  @override
  Future<WeatherData> getCurrentWeather(double lat, double lng) async =>
      throw StateError('offline in workflow test');

  @override
  Future<List<WeatherForecastSlot>> getForecast(double lat, double lng) async =>
      const [];
}

class _WeatherCache extends WeatherCacheService {
  @override
  Future<WeatherCacheEntry?> load({
    double? latitude,
    double? longitude,
  }) async => null;
}

class _Plan extends TonightShootingPlanService {
  @override
  Future<TonightShootingPlanSnapshot> loadSnapshotForDate(
    DateTime planDate,
  ) async => const TonightShootingPlanSnapshot(orderedObjectIds: []);
}

class _UnusedBortleRepository implements BortleRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ObservationEngine extends ObservationEngine {
  _ObservationEngine(this.positionService)
    : super(
        ObservationConditionService(
          LocationService(),
          _UnusedBortleRepository(),
        ),
        positionService,
      );

  final CelestialPositionService positionService;
  int builds = 0;

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
    builds += 1;
    final window =
        session ??
        TonightObservationSession(
          start: currentTime,
          end: currentTime.add(const Duration(hours: 1)),
        );
    return ObservationContext(
      latitude: latitude,
      longitude: longitude,
      bortle: latitude > 38 ? 4 : 8,
      moonIllumination: 0.2,
      moonAltitude: -10,
      moonAzimuth: 180,
      cloudCover: 0,
      observationStart: window.start,
      observationEnd: window.end,
      currentTime: currentTime,
      catalog: catalog ?? const [],
    );
  }
}

class _Scheduler extends SchedulerEngine {
  int builds = 0;

  @override
  ScheduleResult buildSchedule(SchedulerInput input) {
    builds += 1;
    return ScheduleResult(slots: generateSlots(input.session));
  }
}

class _RecommendationEngine extends RecommendationEngine {
  _RecommendationEngine(this.scheduler, CelestialPositionService positions)
    : super(
        positions,
        ExposurePolicy(),
        const ObjectImagingProfileProvider(),
        scheduler,
      );

  final _Scheduler scheduler;
  final List<TrackingMode> trackingModes = [];
  final List<int> horizonPointCounts = [];

  @override
  Future<RecommendationBuildResult> build({
    required List<CatalogObject> catalog,
    required RecommendationSettings settings,
    required ObservationContext context,
    required TonightObservationSession session,
    int limit = 20,
    double windSpeed = 0,
    DateTime? referenceTime,
    TrackingMode trackingMode = TrackingMode.altAz,
    ImagingEquipmentFit? Function(
      CatalogObject object,
      ObjectObservationWindow window,
    )?
    equipmentFitResolver,
  }) async {
    trackingModes.add(trackingMode);
    horizonPointCounts.add(context.horizonProfile.points.length);
    final schedule = scheduler.buildSchedule(
      SchedulerInput(
        context: context,
        session: session,
        targets: const [],
        resultsById: const {},
        referenceTime: referenceTime ?? context.currentTime,
      ),
    );
    return RecommendationBuildResult(
      session: session,
      recommendations: const [],
      allRecommendations: const [],
      scheduleItems: schedule.items,
      exclusionReasons: [
        'tracking:${trackingMode.name}',
        'horizon:${context.horizonProfile.points.length}',
      ],
      scheduleResult: schedule,
      scoredTargets: const [],
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'equipment, tracking, site and camera Horizon changes rebuild Home',
    () async {
      PerformanceProbe.reset();
      final invalidator = ObservationContextInvalidator();
      final now = DateTime(2026, 8, 26);
      final initialSite = ObservationSite(
        id: 'site-1',
        name: 'Initial',
        latitude: 37.5,
        longitude: 127,
        bortle: 8,
        trackingMode: TrackingMode.altAz,
        defaultMinAltitude: 20,
        createdAt: now,
        updatedAt: now,
      );
      final sites = _SiteRepository(invalidator, initialSite);
      final active = ActiveObservationSiteViewModel(
        sites,
        contextInvalidator: invalidator,
      );
      await active.load();
      await active.selectSavedSite(initialSite);

      final equipment = _EquipmentRepository(invalidator);
      final positions = CelestialPositionService();
      final observation = _ObservationEngine(positions);
      final scheduler = _Scheduler();
      final recommendation = _RecommendationEngine(scheduler, positions);
      final home = HomeViewModel(
        _CatalogRepository(),
        _Weather(),
        _Location(),
        _Settings(),
        observation,
        recommendation,
        positions,
        _WeatherCache(),
        _Plan(),
        equipment,
        const EquipmentRecommendationService(),
        scheduler,
        active,
        invalidator,
      );
      addTearDown(home.dispose);
      await home.load();

      final initialRecommendationBuilds = recommendation.trackingModes.length;
      final initialScheduleBuilds = scheduler.builds;
      final initialInvalidations = PerformanceProbe.count(
        'observation_context.invalidate',
      );
      final initialReloads = PerformanceProbe.count(
        'observation_context.reload',
      );
      final initialMeasuredRecommendations = PerformanceProbe.count(
        'recommendation.build',
      );
      const telescope = Equipment(
        id: 'scope-1',
        name: 'Workflow scope',
        kind: EquipmentKind.smartTelescope,
        purpose: EquipmentPurpose.imaging,
        fovWidthDegrees: 2,
        fovHeightDegrees: 1,
      );
      await equipment.save(telescope);
      expect(home.activeEquipment, contains(telescope));
      expect(
        recommendation.trackingModes.length,
        initialRecommendationBuilds + 1,
      );
      expect(scheduler.builds, initialScheduleBuilds + 1);
      expect(
        PerformanceProbe.count('observation_context.invalidate'),
        initialInvalidations + 1,
      );
      expect(
        PerformanceProbe.count('observation_context.reload'),
        initialReloads + 1,
      );
      expect(
        PerformanceProbe.count('recommendation.build'),
        initialMeasuredRecommendations + 1,
      );

      final trackingRecommendationBuilds = recommendation.trackingModes.length;
      final trackingScheduleBuilds = scheduler.builds;
      await home.setTrackingMode(TrackingMode.eq);
      expect(home.trackingMode, TrackingMode.eq);
      expect(home.lastSessionContext?.trackingMode, TrackingMode.eq);
      expect(recommendation.trackingModes.last, TrackingMode.eq);
      expect(home.exclusionReasons, contains('tracking:eq'));
      expect(
        recommendation.trackingModes.length,
        trackingRecommendationBuilds + 1,
      );
      expect(scheduler.builds, trackingScheduleBuilds + 1);

      final siteRecommendationBuilds = recommendation.trackingModes.length;
      final siteScheduleBuilds = scheduler.builds;
      final movedSite = initialSite.copyWith(
        name: 'Moved',
        latitude: 38.5,
        longitude: 128,
        bortle: 4,
        updatedAt: now.add(const Duration(minutes: 1)),
      );
      await sites.update(movedSite);
      expect(active.active.displayName, 'Moved');
      expect(home.lastSessionContext?.latitude, 38.5);
      expect(home.lastSessionContext?.bortle, 4);
      expect(recommendation.trackingModes.length, siteRecommendationBuilds + 1);
      expect(scheduler.builds, siteScheduleBuilds + 1);

      final session =
          HorizonScanSession(
              id: 'scan',
              observationSiteId: movedSite.id,
              startedAt: now,
            )
            ..cameraInformation = const HorizonScanCameraInformation(
              cameraName: 'test',
              previewWidth: 20,
              previewHeight: 20,
              sensorOrientation: 90,
              horizontalFov: 60,
              verticalFov: 40,
              intrinsicsSource: 'estimated',
              intrinsicsConfidence: 'medium',
            );
      for (var index = 0; index < 72; index++) {
        final luma = Uint8List(400);
        for (var pixel = 0; pixel < luma.length; pixel++) {
          luma[pixel] = pixel ~/ 20 < 10 ? 220 : 30;
        }
        session.samples.add(
          HorizonScanSample(
            timestamp: now,
            sensorTimestampNanos: index,
            azimuth: index * 5,
            pitch: 5,
            roll: 0,
            coverageBin: index,
            sensorAccuracy: HorizonSensorAccuracy.good,
            trueNorthApplied: true,
            frame: HorizonFrameReference(
              capturedAt: now,
              width: 20,
              height: 20,
              lumaBytes: luma,
            ),
          ),
        );
      }
      final points = const HorizonScanProcessor().process(session);
      final horizonRecommendationBuilds = recommendation.trackingModes.length;
      final horizonScheduleBuilds = scheduler.builds;
      await sites.update(movedSite.copyWith(horizonPoints: points));
      expect(home.lastSessionContext?.horizonProfile.points, hasLength(36));
      expect(recommendation.horizonPointCounts.last, 36);
      expect(
        recommendation.trackingModes.length,
        horizonRecommendationBuilds + 1,
      );
      expect(scheduler.builds, horizonScheduleBuilds + 1);

      await sites.update(movedSite.copyWith(horizonPoints: const []));
      expect(home.lastSessionContext?.horizonProfile.hasRestrictions, isFalse);
      expect(recommendation.horizonPointCounts.last, 0);
    },
  );
}

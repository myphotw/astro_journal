import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../../data/repositories/bortle_repository.dart';
import '../../data/repositories/bortle_repository_impl.dart';
import '../../data/repositories/equipment_repository.dart';
import '../../data/repositories/equipment_repository_impl.dart';
import '../../data/datasources/gallery_cache_local_datasource.dart';
import '../../data/datasources/common_file_link_datasource.dart';
import '../../data/datasources/gallery_record_link_datasource.dart';
import '../../data/datasources/sync_checkpoint_datasource.dart';
import '../../data/repositories/gallery_repository.dart';
import '../../data/repositories/gallery_shooting_record_repository_adapter.dart';
import '../../data/repositories/hybrid_gallery_repository.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/repositories/catalog_repository_impl.dart';
import '../../data/repositories/observation_site_repository.dart';
import '../../data/repositories/observation_site_repository_impl.dart';
import '../../data/repositories/photo_object_repository.dart';
import '../../data/repositories/photo_object_repository_impl.dart';
import '../../data/repositories/photo_repository.dart';
import '../../data/repositories/photo_repository_impl.dart';
import '../../data/repositories/shooting_record_repository.dart';
import '../../data/repositories/shooting_record_repository_impl.dart';
import '../../data/repositories/sync_outbox_repository.dart';
import '../../data/repositories/sync_outbox_repository_impl.dart';
import '../../features/catalog/viewmodel/catalog_view_model.dart';
import '../../features/gallery/viewmodel/gallery_view_model.dart';
import '../../features/gallery/viewmodel/plate_solve_view_model.dart';
import '../../features/photo_first/viewmodel/photo_first_registration_view_model.dart';
import '../../features/home/viewmodel/home_view_model.dart';
import '../../features/light_pollution_map/viewmodel/light_pollution_map_view_model.dart';
import '../../features/main/viewmodel/main_back_navigation_view_model.dart';
import '../../features/horizon_scan/services/device_orientation_service.dart';
import '../../features/observation_site/viewmodel/active_observation_site_view_model.dart';
import '../../features/settings/viewmodel/equipment_view_model.dart';
import '../../features/settings/viewmodel/settings_view_model.dart';
import '../../features/settings/viewmodel/tc_backend_view_model.dart';
import '../../services/stats_analytics_service.dart';
import '../../features/sky_map/viewmodel/sky_map_view_model.dart';
import '../../features/stats/viewmodel/stats_view_model.dart';
import '../../services/api_key_service.dart';
import '../../services/backup_service.dart';
import '../../services/celestial_object_search_service.dart';
import '../../services/celestial_position_service.dart';
import '../../services/exif_service.dart';
import '../../services/geocoding_service.dart';
import '../../services/location_service.dart';
import '../../services/metadata_service.dart';
import '../../services/catalog_search_service.dart';
import '../../services/catalog_capture_projection_service.dart';
import '../../services/photo_metadata_pipeline.dart';
import '../../services/photo_overlay_service.dart';
import '../../services/photo_registration_service.dart';
import '../../services/photo_service.dart';
import '../../services/exposure_policy.dart';
import '../../services/observation_condition_service.dart';
import '../../services/observation_engine.dart';
import '../../services/object_imaging_profile_provider.dart';
import '../../services/light_pollution_tile_preload_service.dart';
import '../../services/plate_solve/backend_only_plate_solve_provider.dart';
import '../../services/plate_solve/plate_solve_provider.dart';
import '../../services/plate_solve_service.dart';
import '../../services/plate_solve_settings_service.dart';
import '../../services/equipment/equipment_recommendation_service.dart';
import '../../services/recommendation_engine.dart';
import '../../services/scheduler_engine.dart';
import '../../services/recommendation_settings_service.dart';
import '../../services/base_exposure_settings_service.dart';
import '../../services/season_planner_filter_service.dart';
import '../../services/tonight_shooting_plan_service.dart';
import '../../services/splash_image_service.dart';
import '../../services/weather_cache_service.dart';
import '../../services/weather_service.dart';
import '../../services/tc_backend_settings_service.dart';
import '../../services/tc_backend_upload_service.dart';
import '../../services/tc_backend_record_service.dart';
import '../../services/tc_backend_sync_coordinator.dart';
import '../../services/tc_backend_startup_resume_service.dart';
import '../../services/tc_backend_changes_service.dart';
import '../../services/tc_backend_external_api_client.dart';
import '../../services/tc_backend_plate_solve_service.dart';
import '../../services/tc_backend_pull_sync_coordinator.dart';
import '../../services/tc_backend_sync_gate.dart';
import '../../services/tc_backend_auth_service.dart';
import '../../services/tc_backend_astrojournal_reset_service.dart';
import '../../services/astrojournal_capture_reset_coordinator.dart';
import '../../services/astrojournal_local_capture_reset_service.dart';
import '../navigation/app_navigation_notifier.dart';

class AppProviders {
  AppProviders._();

  static List<SingleChildWidget> build(BuildContext context) {
    final bortleRepository = BortleRepositoryImpl();
    final catalogRepository = CatalogRepositoryImpl();
    final equipmentRepository = EquipmentRepositoryImpl();
    final shootingRecordRepository = ShootingRecordRepositoryImpl();
    final photoRepository = PhotoRepositoryImpl();
    final observationSiteRepository = ObservationSiteRepositoryImpl();
    final photoObjectRepository = PhotoObjectRepositoryImpl();
    final exifService = ExifService();
    final photoService = PhotoService(photoRepository, exifService);
    final apiKeyService = ApiKeyService();
    final tcBackendSettingsService = TcBackendSettingsService.autoConfigured();
    const tcBackendTokenStore = BuildConfiguredTcBackendTokenStore();
    final tcBackendAuthHeaders = TcBackendAuthHeaders(tcBackendTokenStore);
    final tcBackendMediaAuthService = TcBackendMediaAuthService(
      tcBackendSettingsService,
      tcBackendAuthHeaders,
    );
    final externalApiClient = TcBackendExternalApiClient(
      settingsService: tcBackendSettingsService,
      authHeaders: tcBackendAuthHeaders,
    );
    final geocodingService = GeocodingService(backendClient: externalApiClient);
    final galleryCache = GalleryCacheLocalDataSource();
    final galleryRecordLinks = SyncOutboxGalleryRecordLinkDataSource();
    final commonFileLinks = SyncOutboxCommonFileLinkDataSource();
    final galleryRepository = HybridGalleryRepository(
      settingsService: tcBackendSettingsService,
      cache: galleryCache,
      authHeaders: tcBackendAuthHeaders,
    );
    final catalogCaptureProjection = CatalogCaptureProjectionService(
      catalogRepository: catalogRepository,
      localRecords: shootingRecordRepository,
      galleryRepository: galleryRepository,
      recordLinks: galleryRecordLinks,
    );
    final tcBackendUploadService = TcBackendUploadService(
      settingsService: tcBackendSettingsService,
      authHeaders: tcBackendAuthHeaders,
    );
    final tcBackendRecordService = TcBackendRecordService(
      settingsService: tcBackendSettingsService,
      authHeaders: tcBackendAuthHeaders,
    );
    final syncOutboxRepository = SyncOutboxRepositoryImpl();
    final syncGate = TcBackendSyncGate();
    late Future<void> Function() refreshAfterCaptureReset;
    late PhotoFirstRegistrationViewModel photoFirstViewModel;
    final localCaptureReset = AstroJournalLocalCaptureResetService(
      onDataChanged: () => refreshAfterCaptureReset(),
    );
    final resetApi = TcBackendAstroJournalResetService(
      settingsService: tcBackendSettingsService,
      authHeaders: tcBackendAuthHeaders,
    );
    final captureResetCoordinator = AstroJournalCaptureResetCoordinator(
      resetApi,
      localCaptureReset,
      syncGate,
    );
    final syncCoordinator = TcBackendSyncCoordinator(
      syncOutboxRepository,
      shootingRecordRepository,
      tcBackendSettingsService,
      tcBackendUploadService,
      recordService: tcBackendRecordService,
      galleryRepository: galleryRepository,
      catalogCaptureReconciler: (catalogObjectId) => catalogCaptureProjection
          .reconcileObject(catalogObjectId, includeRemote: false),
      syncGate: syncGate,
    );
    final syncCheckpoints = GalleryCacheSyncCheckpointDataSource(galleryCache);
    final changesService = TcBackendChangesService(
      settingsService: tcBackendSettingsService,
      authHeaders: tcBackendAuthHeaders,
    );
    final pullSyncCoordinator = TcBackendPullSyncCoordinator(
      changesApi: changesService,
      checkpoints: syncCheckpoints,
      galleryRepository: galleryRepository,
      shootingRecordRepository: shootingRecordRepository,
      recordLinks: galleryRecordLinks,
      settingsService: tcBackendSettingsService,
      syncGate: syncGate,
      catalogCaptureProjection: catalogCaptureProjection,
      localCaptureReset: localCaptureReset,
    );
    final startupResumeService = TcBackendStartupResumeService(
      tcBackendSettingsService,
      TcBackendCompositeSyncRunner([syncCoordinator, pullSyncCoordinator]),
      reconcileCatalog: () async {
        await catalogCaptureProjection.reconcileAll();
      },
    );
    final metadataService = MetadataService();
    final catalogSearchService = CatalogSearchService();
    final galleryShootingRecordRepository =
        GalleryShootingRecordRepositoryAdapter(
          galleryRepository: galleryRepository,
          localRepository: shootingRecordRepository,
          catalogRepository: catalogRepository,
          projectionMapper: GalleryObservationProjectionMapper(
            catalogSearchService,
          ),
          linkDataSource: galleryRecordLinks,
          syncOutboxRepository: syncOutboxRepository,
          syncCoordinator: syncCoordinator,
          catalogCaptureProjection: catalogCaptureProjection,
        );
    final metadataPipeline = PhotoMetadataPipeline(
      metadataService: metadataService,
      exifService: exifService,
    );
    final registrationService = PhotoRegistrationService(
      photoService: photoService,
      geocodingService: geocodingService,
      apiKeyService: apiKeyService,
      exifService: exifService,
      shootingRecordRepository: shootingRecordRepository,
      catalogRepository: catalogRepository,
      metadataPipeline: metadataPipeline,
      tcBackendUploadService: tcBackendUploadService,
      syncOutboxRepository: syncOutboxRepository,
      syncCoordinator: syncCoordinator,
      catalogCaptureProjection: catalogCaptureProjection,
    );
    final backupService = BackupService();
    final weatherService = WeatherService(
      apiKeyService,
      backendClient: externalApiClient,
    );
    final plateSolveSettingsService = PlateSolveSettingsService();
    const backendOnlyPlateSolveProvider = BackendOnlyPlateSolveProvider();
    final backendPlateSolveService = TcBackendPlateSolveService(
      client: externalApiClient,
    );
    final plateSolveService = PlateSolveService(
      <PlateSolveProvider>[backendOnlyPlateSolveProvider],
      plateSolveSettingsService,
      backendService: backendPlateSolveService,
    );
    final celestialObjectSearchService = CelestialObjectSearchService(
      catalogRepository,
      photoObjectRepository,
    );
    final photoOverlayService = PhotoOverlayService(catalogRepository);
    final weatherCacheService = WeatherCacheService();
    final locationService = LocationService();
    final activeObservationSiteViewModel = ActiveObservationSiteViewModel(
      observationSiteRepository,
    );
    final deviceOrientationService = NativeDeviceOrientationService();
    final recommendationSettingsService = RecommendationSettingsService();
    final baseExposureSettingsService = BaseExposureSettingsService();
    final tonightShootingPlanService = TonightShootingPlanService();
    final seasonPlannerFilterService = SeasonPlannerFilterService();
    final splashImageService = SplashImageService();
    final celestialPositionService = CelestialPositionService();
    final observationConditionService = ObservationConditionService(
      locationService,
      bortleRepository,
    );
    final exposurePolicy = ExposurePolicy();
    const profileProvider = ObjectImagingProfileProvider();
    const equipmentRecommendationService = EquipmentRecommendationService();
    final observationEngine = ObservationEngine(
      observationConditionService,
      celestialPositionService,
    );
    const schedulerEngine = SchedulerEngine();
    final recommendationEngine = RecommendationEngine(
      celestialPositionService,
      exposurePolicy,
      profileProvider,
      schedulerEngine,
    );
    final tilePreloadService = LightPollutionTilePreloadService(
      shootingRecordRepository,
      observationConditionService,
    );

    photoFirstViewModel = PhotoFirstRegistrationViewModel(
      catalogRepository,
      registrationService,
      catalogSearchService,
    );

    final homeViewModel = HomeViewModel(
      catalogRepository,
      weatherService,
      locationService,
      recommendationSettingsService,
      observationEngine,
      recommendationEngine,
      celestialPositionService,
      weatherCacheService,
      tonightShootingPlanService,
      equipmentRepository,
      equipmentRecommendationService,
      schedulerEngine,
      activeObservationSiteViewModel,
    );

    // Home/Catalog/Gallery/Stats 등은 AppStartupViewModel이 순차 preload한다.
    // 탭 첫 진입 시 MainShell._ensureTabLoaded는 hasLoaded면 재로드하지 않는다.
    final catalogViewModel = CatalogViewModel(
      catalogRepository,
      galleryShootingRecordRepository,
      equipmentRepository,
      equipmentRecommendationService,
      captureProjection: catalogCaptureProjection,
    );

    final galleryViewModel = GalleryViewModel(
      galleryShootingRecordRepository,
      catalogRepository,
      catalogSearchService,
    );

    final plateSolveViewModel = PlateSolveViewModel(
      plateSolveService,
      plateSolveSettingsService,
      galleryViewModel,
      celestialObjectSearchService,
      catalogRepository,
      equipmentRepository,
      commonFileLinks: commonFileLinks,
    );

    final statsAnalyticsService = StatsAnalyticsService();

    final statsViewModel = StatsViewModel(
      galleryShootingRecordRepository,
      catalogRepository,
      statsAnalyticsService,
    );

    final lightPollutionMapViewModel = LightPollutionMapViewModel(
      observationConditionService,
      geocodingService,
      tilePreloadService,
      weatherService,
      observationSiteRepository,
      catalogRepository,
      equipmentRepository,
      observationEngine,
      recommendationEngine,
      equipmentRecommendationService,
      recommendationSettingsService,
    );

    refreshAfterCaptureReset = () async {
      photoFirstViewModel.reset();
      await Future.wait([
        galleryViewModel.load(),
        statsViewModel.load(),
        homeViewModel.load(),
        catalogViewModel.load(),
      ]);
    };

    final settingsViewModel = SettingsViewModel(
      captureResetCoordinator,
      backupService,
    );

    final tcBackendViewModel = TcBackendViewModel(
      tcBackendSettingsService,
      syncOutboxRepository: syncOutboxRepository,
      retryFailed: syncCoordinator.retryFailed,
      tokenStore: tcBackendTokenStore,
      authHeaders: tcBackendAuthHeaders,
    );

    final equipmentViewModel = EquipmentViewModel(equipmentRepository);

    final skyMapViewModel = SkyMapViewModel(
      catalogRepository,
      equipmentRepository,
    );

    final appNavigationNotifier = AppNavigationNotifier();
    final mainBackNavigationViewModel = MainBackNavigationViewModel(
      appNavigationNotifier,
    );

    return [
      ChangeNotifierProvider.value(value: appNavigationNotifier),
      ChangeNotifierProvider.value(value: mainBackNavigationViewModel),
      Provider<BortleRepository>.value(value: bortleRepository),
      Provider<CatalogRepository>.value(value: catalogRepository),
      Provider<EquipmentRepository>.value(value: equipmentRepository),
      Provider<ShootingRecordRepository>.value(value: shootingRecordRepository),
      Provider<PhotoRepository>.value(value: photoRepository),
      Provider<ObservationSiteRepository>.value(
        value: observationSiteRepository,
      ),
      Provider<PhotoObjectRepository>.value(value: photoObjectRepository),
      Provider<PhotoService>.value(value: photoService),
      Provider<ExifService>.value(value: exifService),
      Provider<GeocodingService>.value(value: geocodingService),
      Provider<ApiKeyService>.value(value: apiKeyService),
      Provider<TcBackendSettingsService>.value(value: tcBackendSettingsService),
      Provider<TcBackendTokenStore>.value(value: tcBackendTokenStore),
      Provider<TcBackendAuthHeaders>.value(value: tcBackendAuthHeaders),
      Provider<TcBackendMediaAuthService>.value(
        value: tcBackendMediaAuthService,
      ),
      Provider<GalleryRepository>.value(value: galleryRepository),
      Provider<GalleryShootingRecordRepositoryAdapter>.value(
        value: galleryShootingRecordRepository,
      ),
      Provider<TcBackendUploadService>.value(value: tcBackendUploadService),
      Provider<TcBackendRecordService>.value(value: tcBackendRecordService),
      Provider<TcBackendChangesService>.value(value: changesService),
      Provider<SyncOutboxRepository>.value(value: syncOutboxRepository),
      Provider<SyncCheckpointDataSource>.value(value: syncCheckpoints),
      Provider<TcBackendSyncGate>.value(value: syncGate),
      Provider<AstroJournalResetApi>.value(value: resetApi),
      Provider<AstroJournalLocalCaptureReset>.value(value: localCaptureReset),
      Provider<AstroJournalCaptureResetCoordinator>.value(
        value: captureResetCoordinator,
      ),
      Provider<TcBackendSyncCoordinator>.value(value: syncCoordinator),
      Provider<TcBackendPullSyncCoordinator>.value(value: pullSyncCoordinator),
      Provider<TcBackendStartupResumeService>.value(
        value: startupResumeService,
      ),
      Provider<MetadataService>.value(value: metadataService),
      Provider<CatalogSearchService>.value(value: catalogSearchService),
      ChangeNotifierProvider<CatalogCaptureProjectionService>.value(
        value: catalogCaptureProjection,
      ),
      Provider<PhotoMetadataPipeline>.value(value: metadataPipeline),
      Provider<PhotoRegistrationService>.value(value: registrationService),
      Provider<PhotoOverlayService>.value(value: photoOverlayService),
      Provider<BackupService>.value(value: backupService),
      Provider<WeatherService>.value(value: weatherService),
      Provider<PlateSolveSettingsService>.value(
        value: plateSolveSettingsService,
      ),
      Provider<PlateSolveService>.value(value: plateSolveService),
      Provider<TcBackendPlateSolveService>.value(
        value: backendPlateSolveService,
      ),
      Provider<WeatherCacheService>.value(value: weatherCacheService),
      Provider<LocationService>.value(value: locationService),
      Provider<DeviceOrientationService>.value(value: deviceOrientationService),
      ChangeNotifierProvider.value(value: activeObservationSiteViewModel),
      Provider<RecommendationSettingsService>.value(
        value: recommendationSettingsService,
      ),
      Provider<BaseExposureSettingsService>.value(
        value: baseExposureSettingsService,
      ),
      Provider<TonightShootingPlanService>.value(
        value: tonightShootingPlanService,
      ),
      Provider<SeasonPlannerFilterService>.value(
        value: seasonPlannerFilterService,
      ),
      Provider<CelestialPositionService>.value(value: celestialPositionService),
      Provider<ObservationConditionService>.value(
        value: observationConditionService,
      ),
      Provider<ExposurePolicy>.value(value: exposurePolicy),
      Provider<ObjectImagingProfileProvider>.value(value: profileProvider),
      Provider<EquipmentRecommendationService>.value(
        value: equipmentRecommendationService,
      ),
      Provider<ObservationEngine>.value(value: observationEngine),
      Provider<RecommendationEngine>.value(value: recommendationEngine),
      Provider<SchedulerEngine>.value(value: schedulerEngine),
      Provider<StatsAnalyticsService>.value(value: statsAnalyticsService),
      Provider<SplashImageService>.value(value: splashImageService),
      ChangeNotifierProvider.value(value: photoFirstViewModel),
      ChangeNotifierProvider.value(value: homeViewModel),
      ChangeNotifierProvider.value(value: catalogViewModel),
      ChangeNotifierProvider.value(value: galleryViewModel),
      ChangeNotifierProvider.value(value: plateSolveViewModel),
      ChangeNotifierProvider.value(value: lightPollutionMapViewModel),
      ChangeNotifierProvider.value(value: statsViewModel),
      ChangeNotifierProvider.value(value: settingsViewModel),
      ChangeNotifierProvider.value(value: tcBackendViewModel),
      ChangeNotifierProvider.value(value: equipmentViewModel),
      ChangeNotifierProvider.value(value: skyMapViewModel),
    ];
  }
}

import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/core/constants/equipment_kind.dart';
import 'package:astro_journal/core/constants/equipment_purpose.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/equipment.dart';
import 'package:astro_journal/data/models/equipment_recommendation.dart';
import 'package:astro_journal/data/models/imaging_suitability_assessment.dart';
import 'package:astro_journal/data/models/object_observation_window.dart';
import 'package:astro_journal/data/models/observation_condition.dart';
import 'package:astro_journal/data/models/observation_site.dart';
import 'package:astro_journal/data/models/recommendation_result.dart';
import 'package:astro_journal/data/models/shooting_record.dart';
import 'package:astro_journal/data/models/target_imaging_availability.dart';
import 'package:astro_journal/data/repositories/catalog_repository.dart';
import 'package:astro_journal/data/repositories/equipment_repository.dart';
import 'package:astro_journal/data/repositories/observation_site_repository.dart';
import 'package:astro_journal/data/repositories/shooting_record_repository.dart';
import 'package:astro_journal/features/catalog/viewmodel/catalog_detail_view_model.dart';
import 'package:astro_journal/services/base_exposure_settings_service.dart';
import 'package:astro_journal/services/equipment/equipment_recommendation_service.dart';
import 'package:astro_journal/services/equipment/equipment_capture_presets.dart';
import 'package:astro_journal/services/exposure_policy.dart';
import 'package:astro_journal/services/metadata_service.dart';
import 'package:astro_journal/services/object_imaging_profile_provider.dart';
import 'package:astro_journal/services/observation_condition_service.dart';
import 'package:astro_journal/services/photo_registration_service.dart';
import 'package:astro_journal/services/target_imaging_availability_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final object = CatalogObject(
    id: 'm42',
    number: 42,
    catalog: CatalogType.messier,
    name: '오리온대성운',
    type: '성운',
    constellation: '오리온자리',
    ra: '05h 35m',
    dec: '-05° 23m',
    magnitude: '4.0',
  );
  final home = ObservationSite(
    id: 'home',
    name: '집',
    latitude: 37.5,
    longitude: 127,
    bortle: 8,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  final gure = ObservationSite(
    id: 'gure',
    name: '구례',
    latitude: 35.2,
    longitude: 127.4,
    bortle: 4,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  test(
    'registered-site selection never replaces current-location state',
    () async {
      final availability = _AvailabilityService();
      final viewModel = _viewModel(
        object: object,
        sites: [home, gure],
        availability: availability,
        condition: _ConditionService(_currentCondition),
      );

      await viewModel.refreshAvailability();
      final currentBefore = viewModel.currentLocationAvailability;

      expect(
        viewModel.currentLocationSite?.latitude,
        _currentCondition.latitude,
      );
      expect(
        viewModel.currentLocationSite?.longitude,
        _currentCondition.longitude,
      );
      expect(viewModel.currentLocationSite?.name, '현재 위치');
      expect(viewModel.currentLocationSite?.bortle, _currentCondition.bortle);
      expect(viewModel.currentLocationSite?.horizonPoints, isEmpty);
      expect(viewModel.currentLocationSite?.blockedAzimuthRanges, isEmpty);
      expect(viewModel.currentLocationSite?.defaultMinAltitude, 0);
      expect(viewModel.currentLocationSite?.defaultMaxAltitude, 90);
      expect(viewModel.selectedRegisteredObservationSite?.id, home.id);

      await viewModel.selectObservationSite(gure.id);

      expect(viewModel.currentLocationAvailability, same(currentBefore));
      expect(
        viewModel.currentLocationSite?.latitude,
        _currentCondition.latitude,
      );
      expect(viewModel.selectedRegisteredObservationSite?.id, gure.id);
      expect(
        availability.siteIds.where((id) => id == 'catalog-current-location'),
        hasLength(1),
      );
      expect(availability.siteIds, containsAll(<String>[home.id, gure.id]));
      viewModel.dispose();
    },
  );

  test('current location works when there are no registered sites', () async {
    final viewModel = _viewModel(
      object: object,
      sites: const [],
      availability: _AvailabilityService(),
      condition: _ConditionService(_currentCondition),
    );

    await viewModel.refreshAvailability();

    expect(viewModel.currentLocationAvailability, isNotNull);
    expect(viewModel.selectedRegisteredObservationSite, isNull);
    expect(viewModel.registeredImagingAvailability, isNull);
    viewModel.dispose();
  });

  test(
    'current location failure preserves registered-site availability',
    () async {
      final viewModel = _viewModel(
        object: object,
        sites: [home],
        availability: _AvailabilityService(),
        condition: _ConditionService.failure(),
      );

      await viewModel.refreshAvailability();

      expect(viewModel.currentLocationAvailability, isNull);
      expect(viewModel.currentLocationAvailabilityError, '현재 위치를 확인할 수 없습니다.');
      expect(viewModel.selectedRegisteredObservationSite?.id, home.id);
      expect(viewModel.registeredImagingAvailability, isNotNull);
      viewModel.dispose();
    },
  );

  test(
    'selected registered site feeds capture recommendation context',
    () async {
      final viewModel = _viewModel(
        object: object,
        sites: [home, gure],
        availability: _AvailabilityService(),
        condition: _ConditionService(_currentCondition),
      );

      await viewModel.load();
      await viewModel.refreshAvailability();
      await viewModel.selectObservationSite(gure.id);

      final setting = viewModel
          .equipmentRecommendation
          .imaging
          .single
          .captureSettings
          .first;
      expect(
        setting.exposureConfidence,
        CaptureRecommendationConfidence.experimental,
      );
      expect(setting.filterInputs, contains('Bortle 4'));
      expect(setting.filterInputs, isNot(contains('Bortle 7')));
      viewModel.dispose();
    },
  );
}

final _currentCondition = ObservationCondition(
  latitude: 37.61,
  longitude: 126.91,
  bortle: 7,
  sqm: 18.2,
  createdAt: DateTime(2026, 9, 17),
);

CatalogDetailViewModel _viewModel({
  required CatalogObject object,
  required List<ObservationSite> sites,
  required _AvailabilityService availability,
  required _ConditionService condition,
}) => CatalogDetailViewModel(
  object,
  _ShootingRecords(),
  _Catalogs(),
  _RegistrationService(),
  const MetadataService(),
  _Equipment(),
  const EquipmentRecommendationService(),
  _BaseExposureSettings(),
  const ObjectImagingProfileProvider(),
  const ExposurePolicy(),
  observationSiteRepository: _Sites(sites),
  availabilityService: availability,
  observationConditionService: condition,
);

class _AvailabilityService implements TargetImagingAvailabilityService {
  final List<String> siteIds = [];

  @override
  Future<TargetImagingAvailability> evaluate({
    required CatalogObject object,
    required ObservationSite site,
    DateTime? referenceDate,
    Equipment? equipment,
    ImagingEquipmentFit? equipmentFit,
  }) async {
    siteIds.add(site.id);
    return TargetImagingAvailability(
      object: object,
      referenceDate: referenceDate ?? DateTime(2026, 9, 17),
      isAvailableTonight: true,
      usableMinutes: 90,
      recommendation: RecommendationResult(
        object: object,
        reasons: const [],
        season: '가을',
        score: 80,
        moonSeparation: 40,
        observationWindow: ObjectObservationWindow(
          currentAltitude: 35,
          currentAzimuth: 180,
          isCurrentlyVisible: true,
          optimalAltitude: 55,
          optimalTime: DateTime(2026, 9, 17, 22),
          totalObservableMinutes: 120,
        ),
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ConditionService implements ObservationConditionService {
  _ConditionService(this._condition) : _error = null;
  _ConditionService.failure()
    : _condition = null,
      _error = StateError('location unavailable');

  final ObservationCondition? _condition;
  final Object? _error;

  @override
  Future<ObservationCondition> getCurrentCondition({
    bool preferLastKnown = false,
  }) async {
    final error = _error;
    if (error != null) throw error;
    return _condition!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sites implements ObservationSiteRepository {
  _Sites(this.sites);
  final List<ObservationSite> sites;

  @override
  Future<List<ObservationSite>> list({bool includeDeleted = false}) async =>
      sites;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BaseExposureSettings extends BaseExposureSettingsService {
  @override
  Future<BaseExposureSettings> load() async => BaseExposureSettings.defaults;
}

class _ShootingRecords implements ShootingRecordRepository {
  @override
  Future<List<ShootingRecord>> getByCelestialObjectId(String objectId) async =>
      [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Catalogs implements CatalogRepository {
  @override
  Future<CatalogObject?> getById(String id) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RegistrationService implements PhotoRegistrationService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Equipment implements EquipmentRepository {
  @override
  Future<List<Equipment>> getAll({bool activeOnly = false}) async => [
    Equipment(
      id: 's30',
      name: 'Seestar S30 Pro',
      kind: EquipmentKind.smartTelescope,
      purpose: EquipmentPurpose.imaging,
      focalLengthMm: 160,
      fovWidthDegrees: 2.24,
      fovHeightDegrees: 3.99,
      captureCapability: EquipmentCapturePresets.build(
        EquipmentCapturePreset.seestarS30Pro,
      ),
    ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

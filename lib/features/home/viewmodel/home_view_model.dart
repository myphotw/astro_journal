import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/constants/catalog_type.dart';
import '../../../core/services/observation_context_invalidator.dart';
import '../../../core/services/performance_probe.dart';
import '../../../data/models/catalog_object.dart';
import '../../../data/models/observation_quality_component.dart';
import '../../../data/models/observation_quality_index.dart';
import '../../../data/models/observation_status.dart';
import '../../../data/models/observation_score_contribution.dart';
import '../../../data/models/observation_stability.dart';
import '../../../data/models/observation_weather.dart';
import '../../../data/models/observation_context.dart';
import '../../../data/models/recommendation_result.dart';
import '../../../data/models/scored_observation_target.dart';
import '../../../data/models/scheduler_models.dart';
import '../../../data/models/tonight_observation_session.dart';
import '../../../data/models/weather_data.dart';
import '../../../data/models/weather_forecast_slot.dart';
import '../../../data/models/catalog_equipment_chips.dart';
import '../../../data/models/equipment_tonight_group.dart';
import '../../../data/models/equipment_recommendation.dart';
import '../../../data/models/equipment.dart';
import '../../../data/models/imaging_suitability_assessment.dart';
import '../../../data/models/object_observation_window.dart';
import '../../../data/models/observation_site.dart';
import '../../../data/models/multi_night_framing_reference.dart';
import '../../../data/models/shooting_suitability.dart';
import '../../../data/models/shooting_time_window.dart';
import '../../../data/repositories/catalog_repository.dart';
import '../../../data/repositories/equipment_repository.dart';
import '../../../data/repositories/multi_night_framing_reference_repository.dart';
import '../../../services/celestial_position_service.dart';
import '../../../services/equipment/equipment_recommendation_service.dart';
import '../../../services/tonight_shooting_plan_service.dart';
import '../../../services/location_service.dart';
import '../../../services/observation_engine.dart';
import '../../../services/observation_quality_service.dart';
import '../../../services/observation_score_service.dart';
import '../../../services/recommendation/catalog_recommendation_eligibility_policy.dart';
import '../../../services/recommendation/observation_window_calculator.dart';
import '../../../services/recommendation_engine.dart';
import '../../../services/recommendation_settings_service.dart';
import '../../../services/scheduler_engine.dart';
import '../../../services/multi_night_framing_match_service.dart';
import '../../../services/shooting_suitability_service.dart';
import '../../../services/weather_cache_service.dart';
import '../../../services/weather_service.dart';
import '../../../services/rain_observation_policy.dart';
import '../../observation_site/viewmodel/active_observation_site_view_model.dart';

// ── Value objects ────────────────────────────────────────────────────────────

class MoonInfo {
  const MoonInfo({
    required this.age,
    required this.illumination,
    required this.phaseName,
    required this.phaseEmoji,
  });

  final double age;
  final double illumination;
  final String phaseName;
  final String phaseEmoji;

  int get illuminationPercent => (illumination * 100).round();
}

class ObservationCondition {
  const ObservationCondition({
    required this.score,
    required this.siteName,
    required this.moon,
    this.weather,
    this.weatherError,
    this.qualityComponents = const [],
    this.averageQuality = const ObservationQualityIndex(components: []),
    this.condensationRisk = CondensationRisk.low,
    this.tonightSlots = const [],
    this.bestTonightSlot,
    this.observationWindow,
    this.recommendedWindow = '',
    this.nightAverageScore = 0,
    this.contributions = const [],
    this.averageCloudCoverage = 0,
    this.averageWindSpeed = 0,
    this.averageTemperature = 0,
    this.averageMoonIllumination = 0,
    this.averagePrecipitationPop = 0,
    this.averageVisibilityMeters = 10000,
    this.cloudCover = 0,
    this.visibilityMeters = 10000,
    this.humidity = 0,
    this.windSpeed = 0,
    this.precipitationProbability = 0,
    this.dewPoint = 0,
    this.weatherScore = 0,
    this.isObservationFeasible = true,
    this.observationStatus = ObservationStatus.good,
    this.statusPrimaryReason,
    this.statusUserMessage,
    this.primaryInfeasibleReason,
    this.infeasibleUserMessage,
    this.isWeatherFromCache = false,
    this.weatherCachedAt,
  });

  final int score;
  final String siteName;
  final MoonInfo moon;
  final WeatherData? weather;
  final String? weatherError;

  final List<ObservationQualityComponent> qualityComponents;
  final ObservationQualityIndex averageQuality;
  final CondensationRisk condensationRisk;

  final List<TonightObservationSlot> tonightSlots;
  final TonightObservationSlot? bestTonightSlot;
  final ObservationWindow? observationWindow;
  final String recommendedWindow;
  final int nightAverageScore;
  final List<ObservationScoreContribution> contributions;

  final double averageCloudCoverage;
  final double averageWindSpeed;
  final double averageTemperature;
  final double averageMoonIllumination;
  final double averagePrecipitationPop;
  final int averageVisibilityMeters;
  final int cloudCover;
  final int visibilityMeters;
  final int humidity;
  final double windSpeed;
  final double precipitationProbability;
  final double dewPoint;
  final double weatherScore;
  final bool isObservationFeasible;
  final ObservationStatus observationStatus;
  final String? statusPrimaryReason;
  final String? statusUserMessage;
  final String? primaryInfeasibleReason;
  final String? infeasibleUserMessage;
  final bool isWeatherFromCache;
  final DateTime? weatherCachedAt;

  ObservationStability? get stability => observationWindow?.stability;

  int get windowAverageScore => observationWindow?.averageScore ?? 0;

  int get windowStarCount =>
      ObservationScoreService.recommendationStarCount(windowAverageScore);

  bool get hasTonightForecast => tonightSlots.isNotEmpty;
  bool get hasWeather => weather != null;

  int get starCount => observationStatus.homeStarCount;

  int get averageMoonIlluminationPercent =>
      (averageMoonIllumination * 100).round();

  String get limitedRecommendationNotice =>
      observationStatus.limitedRecommendationNotice;

  String get summaryText {
    if (observationStatus == ObservationStatus.unavailable) {
      return statusUserMessage ??
          statusPrimaryReason ??
          observationStatus.headline;
    }
    return observationStatus.headline;
  }

  String get commentText {
    if (observationStatus == ObservationStatus.unavailable) {
      final reason = statusPrimaryReason ?? observationStatus.headline;
      return '☁ $reason';
    }
    if (observationStatus == ObservationStatus.limited) {
      return '☁ ${observationStatus.limitedRecommendationNotice}';
    }
    final moonIllum = moon.illumination;
    if (score >= 80) {
      if (moonIllum < 0.2) return '🌌 오늘은 딥스카이 촬영 최적의 조건입니다.';
      return '🌟 ${observationStatus.headline}';
    }
    if (score >= 60) {
      if (moonIllum < 0.3) return '🌙 달빛 영향이 적어 성운 촬영을 추천합니다.';
      return '⭐ ${observationStatus.headline}';
    }
    return '🌟 ${observationStatus.headline}';
  }

  bool get isRainUnavailable =>
      observationStatus == ObservationStatus.unavailable &&
      (statusPrimaryReason == RainObservationPolicy.reasonRain ||
          statusPrimaryReason == RainObservationPolicy.reasonPop);
}

class CategoryProgress {
  const CategoryProgress({
    required this.type,
    required this.total,
    required this.captured,
  });

  final CatalogType type;
  final int total;
  final int captured;

  double get progress => total == 0 ? 0 : captured / total;
  double get progressPercent => progress * 100;
}

class ManualShootingCandidate {
  const ManualShootingCandidate({
    required this.target,
    required this.recommendation,
    required this.suitability,
    required this.proposal,
  });

  final ScoredObservationTarget target;
  final RecommendationResult recommendation;
  final ShootingSuitability suitability;
  final ManualShootingWindowProposal proposal;

  ShootingTimeWindow get searchWindow => proposal.searchWindow;
  ShootingTimeWindow get usableWindow => proposal.usableWindow;
  ShootingTimeWindow get proposedWindow => proposal.proposedWindow;
  Duration get proposedDuration => proposal.proposedDuration;
  bool get isBelowMinimumDuration => proposal.isBelowMinimumDuration;
  bool get isBelowRecommendedDuration => proposal.isBelowRecommendedDuration;
  bool get isMultiNightAccumulationOpportunity =>
      proposal.isMultiNightAccumulationOpportunity;

  bool get isObservable =>
      suitability.selectedWindowIsObservable(proposedWindow);
  bool get matchesFraming => proposal.framingMatched;
  bool get isOptimal => suitability.selectedWindowIsOptimal(proposedWindow);
  bool get overlapsOptimal =>
      suitability.selectedWindowOverlapsOptimal(proposedWindow);
}

// ── ViewModel ────────────────────────────────────────────────────────────────

enum RecommendationComputationState { current, recalculating, failed }

enum ScheduleComputationState { current, recalculating, failed }

class HomeViewModel extends ChangeNotifier {
  HomeViewModel(
    this._catalogRepository,
    this._weatherService,
    this._locationService,
    this._recommendationSettingsService,
    this._observationEngine,
    this._recommendationEngine,
    this._celestialPositionService,
    this._weatherCacheService,
    this._shootingPlanService,
    this._equipmentRepository,
    this._equipmentRecommendationService,
    this._schedulerEngine,
    this._activeObservationSiteViewModel, [
    this._contextInvalidator,
    this._multiNightFramingRepository,
    this._multiNightFramingMatchService,
  ]) {
    _contextBindingToken = _contextInvalidator?.bind(
      _handleContextInvalidation,
    );
  }

  final CatalogRepository _catalogRepository;
  final WeatherService _weatherService;
  final LocationService _locationService;
  final RecommendationSettingsService _recommendationSettingsService;
  final ObservationEngine _observationEngine;
  final RecommendationEngine _recommendationEngine;
  final CelestialPositionService _celestialPositionService;
  final WeatherCacheService _weatherCacheService;
  final TonightShootingPlanService _shootingPlanService;
  final EquipmentRepository _equipmentRepository;
  final EquipmentRecommendationService _equipmentRecommendationService;
  final SchedulerEngine _schedulerEngine;
  final ActiveObservationSiteViewModel _activeObservationSiteViewModel;
  final ObservationContextInvalidator? _contextInvalidator;
  final MultiNightFramingReferenceRepository? _multiNightFramingRepository;
  final MultiNightFramingMatchService? _multiNightFramingMatchService;
  final ShootingSuitabilityService _shootingSuitabilityService =
      const ShootingSuitabilityService();
  late final Object? _contextBindingToken;

  bool _isLoading = false;
  bool _isWeatherLoading = false;
  bool _isDisposed = false;
  int _weatherRequestGeneration = 0;
  String? _errorMessage;
  List<RecommendationResult> _recommendedObjects = [];
  List<RecommendationResult> _allRecommendedObjects = [];
  List<ScheduleItem> _scheduleItems = [];
  List<EquipmentTonightGroup> _equipmentTonightGroups = [];
  List<Equipment> _activeEquipment = [];
  List<String> _plannedObjectOrder = [];
  final Map<String, TonightShootingPlanEntry> _planEntriesById = {};
  bool _userEditedTonightPlan = false;
  List<ScheduleItem> _recommendedScheduleItems = [];
  final Map<String, CatalogEquipmentChips> _todayEquipmentChipsByObjectId = {};
  final Map<String, TodayEquipmentRecommendation> _todayEquipmentRecByObjectId =
      {};
  List<ScoredObservationTarget> _scoredTargets = [];
  Map<String, RecommendationResult> _resultsById = {};
  Map<String, ShootingSuitability> _shootingSuitabilityById = {};
  ObservationContext? _lastSessionContext;
  TonightObservationSession? _lastSession;
  DateTime? _lastReferenceTime;
  List<CategoryProgress> _categoryProgress = [];
  ObservationCondition? _observationCondition;
  List<CatalogObject> _cachedAllObjects = [];
  List<WeatherForecastSlot> _cachedForecasts = [];
  List<String> _exclusionReasons = [];
  String? _scheduleEmptyMessage;
  RecommendationComputationState _recommendationState =
      RecommendationComputationState.current;
  ScheduleComputationState _scheduleState = ScheduleComputationState.current;
  DateTime? _scheduleUpdatedAt;
  int _recommendationRequestToken = 0;
  int _lastScheduleRequestToken = 0;
  int _lastScheduleContextRevision = 0;
  List<String> _lastScheduleCandidateIds = const [];
  String? _recommendationErrorMessage;
  _PendingHomeHeavyLoad? _pendingHeavyLoad;

  double _latitude = 37.5;
  double _longitude = 127.0;
  bool _hasLocation = false;

  DateTime? _nightStart;
  DateTime? _nightEnd;

  RecommendationSettings _recommendationSettings =
      RecommendationSettings.defaults;
  TrackingMode _trackingMode = TrackingMode.altAz;

  bool get isLoading => _isLoading;
  bool get isWeatherLoading => _isWeatherLoading;
  String? get errorMessage => _errorMessage;
  List<RecommendationResult> get recommendedObjects => _recommendedObjects;
  List<RecommendationResult> get allRecommendedObjects =>
      _allRecommendedObjects;
  List<ScheduleItem> get scheduleItems => _scheduleItems;
  List<EquipmentTonightGroup> get equipmentTonightGroups =>
      _equipmentTonightGroups;
  List<Equipment> get activeEquipment => List.unmodifiable(_activeEquipment);
  Set<String> get plannedObjectIds => Set.unmodifiable(_plannedObjectOrder);
  bool get userEditedTonightPlan => _userEditedTonightPlan;
  DateTime get planDate => _planDate;
  List<CategoryProgress> get categoryProgress => _categoryProgress;
  ObservationCondition? get observationCondition => _observationCondition;
  List<String> get exclusionReasons => _exclusionReasons;
  String? get scheduleEmptyMessage => _scheduleEmptyMessage;
  RecommendationComputationState get recommendationState =>
      _recommendationState;
  ScheduleComputationState get scheduleState => _scheduleState;
  DateTime? get scheduleUpdatedAt => _scheduleUpdatedAt;
  @visibleForTesting
  int get lastScheduleRequestToken => _lastScheduleRequestToken;
  @visibleForTesting
  int get lastScheduleContextRevision => _lastScheduleContextRevision;
  @visibleForTesting
  List<String> get lastScheduleCandidateIds =>
      List.unmodifiable(_lastScheduleCandidateIds);
  String? get recommendationErrorMessage => _recommendationErrorMessage;
  bool get hasLocation => _hasLocation;
  double get latitude => _latitude;
  double get longitude => _longitude;
  ObservationContext? get lastSessionContext => _lastSessionContext;
  TrackingMode get trackingMode => _trackingMode;
  ActiveObservationSiteViewModel get activeObservationSiteViewModel =>
      _activeObservationSiteViewModel;

  Future<void> setTrackingMode(TrackingMode mode) async {
    if (_trackingMode == mode) return;
    _trackingMode = mode;
    _markRecommendationRecalculating();
    await _activeObservationSiteViewModel.setTemporaryTrackingOverride(mode);

    if (_contextInvalidator != null) {
      return;
    }

    if (_cachedAllObjects.isEmpty || _nightStart == null || _nightEnd == null) {
      return;
    }

    await _recalculateWithoutInvalidator();
  }

  Future<void> setEquipment(String? equipmentId) async {
    if (_activeObservationSiteViewModel.active.effectiveEquipmentId ==
        equipmentId) {
      return;
    }
    _markRecommendationRecalculating();
    await _activeObservationSiteViewModel.setTemporaryEquipmentOverride(
      equipmentId,
    );

    if (_contextInvalidator != null) {
      return;
    }

    if (_cachedAllObjects.isEmpty || _nightStart == null || _nightEnd == null) {
      return;
    }

    await _recalculateWithoutInvalidator();
  }

  Future<void> updateRecommendationSettings(
    RecommendationSettings settings,
  ) async {
    _recommendationSettings = settings;
    _markRecommendationRecalculating();
    final invalidator = _contextInvalidator;
    if (invalidator != null) {
      await invalidator.invalidate(
        ObservationContextChange.recommendationSettings,
      );
      return;
    }
    await _recalculateWithoutInvalidator();
  }

  DateTime get _planDate {
    final night = _nightStart ?? DateTime.now();
    return DateTime(night.year, night.month, night.day);
  }

  bool isPlanned(String objectId) => _plannedObjectOrder.contains(objectId);

  TonightShootingPlanEntry? planEntryFor(String objectId) =>
      _planEntriesById[objectId];

  ShootingSuitability? shootingSuitabilityFor(String objectId) =>
      _shootingSuitabilityById[objectId];

  List<ManualShootingCandidate> manualCandidatesFor({
    required DateTime start,
    required DateTime end,
    bool onlyFramingMatches = false,
  }) {
    if (!end.isAfter(start)) return const [];
    final selected = ShootingTimeWindow(start: start, end: end);
    final candidates = <ManualShootingCandidate>[];
    for (final target in _scoredTargets) {
      final suitability = _shootingSuitabilityById[target.object.id];
      final recommendation = _resultsById[target.object.id];
      if (suitability == null || recommendation == null) continue;
      final proposal = _shootingSuitabilityService.proposeManualWindow(
        target: target,
        suitability: suitability,
        searchWindow: selected,
      );
      if (proposal == null) continue;
      if (onlyFramingMatches &&
          (!suitability.hasFramingReference || !proposal.framingMatched)) {
        continue;
      }
      candidates.add(
        ManualShootingCandidate(
          target: target,
          recommendation: recommendation,
          suitability: suitability,
          proposal: proposal,
        ),
      );
    }
    candidates.sort((a, b) {
      final optimal = (b.isOptimal ? 1 : 0).compareTo(a.isOptimal ? 1 : 0);
      if (optimal != 0) return optimal;
      final overlap = (b.overlapsOptimal ? 1 : 0).compareTo(
        a.overlapsOptimal ? 1 : 0,
      );
      if (overlap != 0) return overlap;
      return b.recommendation.score.compareTo(a.recommendation.score);
    });
    return candidates;
  }

  Future<void> addManualSchedule({
    required String objectId,
    required DateTime start,
    required DateTime end,
  }) async {
    if (!end.isAfter(start) || !_resultsById.containsKey(objectId)) return;
    if (!_plannedObjectOrder.contains(objectId)) {
      _plannedObjectOrder = [..._plannedObjectOrder, objectId];
    }
    _planEntriesById[objectId] = TonightShootingPlanEntry(
      objectId: objectId,
      startTime: start,
      endTime: end,
      source: TonightPlanSource.manual,
      hasTimeOverride: true,
    );
    _userEditedTonightPlan = true;
    await _persistTonightPlan();
    _applyShootingPlanFilter();
    await _persistResolvedPlanTimes();
    notifyListeners();
  }

  Future<void> updateScheduleTime({
    required String objectId,
    required DateTime start,
    required DateTime end,
  }) async {
    if (!end.isAfter(start) || !_plannedObjectOrder.contains(objectId)) return;
    final current =
        _planEntriesById[objectId] ??
        TonightShootingPlanEntry(objectId: objectId);
    _planEntriesById[objectId] = current.copyWith(
      startTime: start,
      endTime: end,
      source: TonightPlanSource.manual,
      hasTimeOverride: true,
    );
    _userEditedTonightPlan = true;
    await _persistTonightPlan();
    _applyShootingPlanFilter();
    await _persistResolvedPlanTimes();
    notifyListeners();
  }

  Future<void> resetScheduleTimeToAutomatic(String objectId) async {
    if (!_plannedObjectOrder.contains(objectId)) return;
    _planEntriesById[objectId] = TonightShootingPlanEntry(objectId: objectId);
    _userEditedTonightPlan = true;
    await _persistTonightPlan();
    _applyShootingPlanFilter();
    await _persistResolvedPlanTimes();
    notifyListeners();
  }

  Future<void> reorderTonightPlan(int oldIndex, int newIndex) async {
    if (oldIndex == newIndex) return;
    if (oldIndex < 0 ||
        newIndex < 0 ||
        oldIndex >= _plannedObjectOrder.length ||
        newIndex >= _plannedObjectOrder.length) {
      return;
    }

    final updated = List<String>.from(_plannedObjectOrder);
    final moved = updated.removeAt(oldIndex);
    updated.insert(newIndex, moved);
    _plannedObjectOrder = updated;
    _userEditedTonightPlan = true;
    await _persistTonightPlan();
    _reorderScheduleItemsToMatchPlan();
    notifyListeners();
  }

  Future<void> resetTonightPlanToRecommended() async {
    final autoIds = _extractAutoPlanIds();
    _plannedObjectOrder = autoIds;
    _planEntriesById
      ..clear()
      ..addEntries(
        _recommendedScheduleItems
            .where((item) => autoIds.contains(item.target.object.id))
            .map(
              (item) => MapEntry(
                item.target.object.id,
                TonightShootingPlanEntry(
                  objectId: item.target.object.id,
                  startTime: item.startTime,
                  endTime: item.endTime,
                ),
              ),
            ),
      );
    _userEditedTonightPlan = false;
    await _persistTonightPlan();
    _applyShootingPlanFilter();
    notifyListeners();
  }

  CatalogEquipmentChips todayEquipmentChipsFor(String objectId) =>
      _todayEquipmentChipsByObjectId[objectId] ?? const CatalogEquipmentChips();

  TodayEquipmentRecommendation? todayEquipmentRecommendationFor(
    String objectId,
  ) => _todayEquipmentRecByObjectId[objectId];

  /// 오늘 촬영 장비 추천이 있는 대상만 촬영 계획에 추가 가능 (안시 전용 제외).
  bool canAddToShootingPlan(String objectId) {
    final chips = todayEquipmentChipsFor(objectId);
    return chips.items.any((item) => !item.isVisual);
  }

  Future<void> toggleTonightPlan(String objectId) async {
    if (_plannedObjectOrder.contains(objectId)) {
      _plannedObjectOrder = _plannedObjectOrder
          .where((id) => id != objectId)
          .toList();
      _planEntriesById.remove(objectId);
    } else {
      if (!canAddToShootingPlan(objectId)) return;
      _plannedObjectOrder = [..._plannedObjectOrder, objectId];
      _planEntriesById[objectId] = TonightShootingPlanEntry(objectId: objectId);
    }
    _userEditedTonightPlan = true;
    await _persistTonightPlan();
    _applyShootingPlanFilter();
    await _persistResolvedPlanTimes();
    notifyListeners();
  }

  static MoonInfo _moonFromPhase(MoonPhaseInfo info) {
    return MoonInfo(
      age: info.age,
      illumination: info.illumination,
      phaseName: info.phaseName,
      phaseEmoji: info.phaseEmoji,
    );
  }

  static ObservationCondition _buildCondition({
    required MoonInfo moon,
    required String siteName,
    TonightObservationSummary? summary,
    WeatherData? currentWeather,
    String? weatherError,
    bool isWeatherFromCache = false,
    DateTime? weatherCachedAt,
    ObservationStatus observationStatus = ObservationStatus.good,
    String? statusPrimaryReason,
    String? statusUserMessage,
  }) {
    ObservationWeather? slotWeather;
    if (summary?.bestSlot != null) {
      slotWeather = ObservationWeather.fromForecast(
        summary!.bestSlot!.forecast,
      );
    } else if (currentWeather != null) {
      slotWeather = ObservationWeather.fallback(
        time: DateTime.now(),
        cloudCover: currentWeather.cloudCoverage,
        visibility: currentWeather.visibility,
        humidity: currentWeather.humidity,
        windSpeed: currentWeather.windSpeed,
        temperature: currentWeather.temperature,
      );
    }

    if (summary != null) {
      final window = summary.observationWindow;
      final averageQuality = summary.averageQuality;
      final condensationComponent = averageQuality.componentFor(
        ObservationQualityService.condensationCategory,
      );
      final condensationRisk = switch (condensationComponent?.qualityPoints) {
        null || >= 80 => CondensationRisk.low,
        >= 50 => CondensationRisk.moderate,
        _ => CondensationRisk.high,
      };

      return ObservationCondition(
        score: observationStatus == ObservationStatus.unavailable
            ? 0
            : summary.finalScore,
        siteName: siteName,
        moon: moon,
        weather: currentWeather,
        weatherError: weatherError,
        qualityComponents: averageQuality.components,
        averageQuality: averageQuality,
        condensationRisk: condensationRisk,
        tonightSlots: summary.slots,
        bestTonightSlot: summary.bestSlot,
        observationWindow: window,
        recommendedWindow: window?.label ?? '',
        nightAverageScore: summary.averageScore,
        contributions: window?.contributions ?? const [],
        averageCloudCoverage: summary.averageCloudCoverage,
        averageWindSpeed: summary.averageWindSpeed,
        averageTemperature: summary.averageTemperature,
        averageMoonIllumination: summary.averageMoonIllumination,
        averagePrecipitationPop: summary.averagePrecipitationPop,
        averageVisibilityMeters: summary.averageVisibilityMeters,
        cloudCover: summary.representativeCloudCoverage,
        visibilityMeters:
            slotWeather?.visibility ?? summary.averageVisibilityMeters,
        humidity:
            slotWeather?.humidity ?? summary.bestSlot?.forecast.humidity ?? 50,
        windSpeed: slotWeather?.windSpeed ?? summary.averageWindSpeed,
        precipitationProbability:
            slotWeather?.precipitationProbability ??
            summary.averagePrecipitationPop,
        dewPoint:
            slotWeather?.dewPoint ??
            ObservationScoreService.dewPointCelsius(
              summary.averageTemperature,
              summary.bestSlot?.forecast.humidity ?? 50,
            ),
        weatherScore:
            slotWeather?.weatherScore ?? window?.averageScore.toDouble() ?? 0,
        isObservationFeasible:
            observationStatus != ObservationStatus.unavailable,
        observationStatus: observationStatus,
        statusPrimaryReason:
            statusPrimaryReason ?? summary.primaryInfeasibleReason,
        statusUserMessage: statusUserMessage ?? summary.infeasibleUserMessage,
        primaryInfeasibleReason: summary.primaryInfeasibleReason,
        infeasibleUserMessage: summary.infeasibleUserMessage,
        isWeatherFromCache: isWeatherFromCache,
        weatherCachedAt: weatherCachedAt,
      );
    }

    final fallback = ObservationScoreService.fallbackBreakdown(
      moonIllumination: moon.illumination,
    );

    return ObservationCondition(
      score: fallback.score,
      siteName: siteName,
      moon: moon,
      weather: currentWeather,
      weatherError: weatherError,
      qualityComponents: const [],
      averageQuality: const ObservationQualityIndex(components: []),
      condensationRisk: fallback.condensationRisk,
      averageMoonIllumination: moon.illumination,
      cloudCover: slotWeather?.cloudCover ?? currentWeather?.cloudCoverage ?? 0,
      visibilityMeters:
          slotWeather?.visibility ?? currentWeather?.visibility ?? 10000,
      humidity: slotWeather?.humidity ?? currentWeather?.humidity ?? 0,
      windSpeed: slotWeather?.windSpeed ?? currentWeather?.windSpeed ?? 0,
      precipitationProbability: slotWeather?.precipitationProbability ?? 0,
      dewPoint:
          slotWeather?.dewPoint ??
          (currentWeather != null
              ? ObservationScoreService.dewPointCelsius(
                  currentWeather.temperature,
                  currentWeather.humidity,
                )
              : 0),
      weatherScore: slotWeather?.weatherScore ?? fallback.score.toDouble(),
      isWeatherFromCache: isWeatherFromCache,
      weatherCachedAt: weatherCachedAt,
    );
  }

  static String milkyWayWindow(int month) {
    const windows = <int, String?>{
      1: null,
      2: null,
      3: null,
      4: '새벽 04:30 ~ 05:30',
      5: '새벽 02:30 ~ 05:00',
      6: '자정 00:00 ~ 04:00',
      7: '21:30 ~ 03:30',
      8: '20:30 ~ 01:00',
      9: '19:30 ~ 22:30',
      10: '일몰 직후 (촬영 어려움)',
      11: null,
      12: null,
    };
    return windows[month] ?? '이 달은 은하수 촬영이 어렵습니다';
  }

  static ({DateTime nightStart, DateTime nightEnd}) _estimateNightWindow(
    DateTime now,
  ) => ObservationScoreService.estimatedNightWindow(now);

  Future<bool> _applyRecommendations({
    required List<CatalogObject> allObjects,
    required DateTime now,
    int cloudCoverage = 0,
    double windSpeed = 0,
    double? moonIllumination,
    int mainLimit = 4,
    int allLimit = 20,
    int? expectedRevision,
  }) async {
    if (_nightStart == null || _nightEnd == null) return false;
    final requestToken = ++_recommendationRequestToken;

    final session = TonightObservationSession(
      start: _nightStart!,
      end: _nightEnd!,
    );

    final revision = _contextInvalidator?.revision ?? 0;
    final context = await PerformanceProbe.measureAsync(
      'observation_context.build',
      () => _observationEngine.buildContext(
        latitude: _latitude,
        longitude: _longitude,
        currentTime: now,
        weather: _observationCondition?.weather,
        forecasts: _cachedForecasts,
        session: session,
        catalog: allObjects,
      ),
      state: 'revision=$revision',
    );

    final sessionContext = context.copyWith(
      observationStart: session.start,
      observationEnd: session.end,
      moonIllumination: moonIllumination ?? context.moonIllumination,
      horizonProfile: _activeObservationSiteViewModel.active.horizonProfile,
      trackingMode: _trackingMode,
    );

    final allEquipment = await PerformanceProbe.measureAsync(
      'repository.equipment.active_list',
      () => _equipmentRepository.getAll(activeOnly: true),
      state: 'revision=$revision',
    );
    var preferredEquipmentId =
        _activeObservationSiteViewModel.active.effectiveEquipmentId;
    if (preferredEquipmentId != null &&
        !allEquipment.any((item) => item.id == preferredEquipmentId)) {
      preferredEquipmentId = allEquipment.firstOrNull?.id;
      _activeObservationSiteViewModel.reconcileEquipmentSelection(
        preferredEquipmentId,
      );
    }
    final preferredEquipment = preferredEquipmentId == null
        ? null
        : allEquipment
              .where((item) => item.id == preferredEquipmentId)
              .toList();
    final equipment = preferredEquipment == null || preferredEquipment.isEmpty
        ? allEquipment
        : preferredEquipment;
    final result = await PerformanceProbe.measureAsync(
      'recommendation.build',
      () => _recommendationEngine.build(
        catalog: allObjects,
        settings: _recommendationSettings,
        context: sessionContext,
        session: session,
        limit: allLimit,
        windSpeed: windSpeed,
        referenceTime: now,
        trackingMode: sessionContext.trackingMode,
        candidateScope: RecommendationCandidateScope.representative,
        durationPolicy: ObservationWindowDurationPolicy.informational,
        equipmentFitResolver: (object, window) => _equipmentFitFor(
          object: object,
          window: window,
          equipment: equipment,
          context: sessionContext,
        ),
      ),
      state: 'revision=$revision',
    );

    if (_isDisposed ||
        requestToken != _recommendationRequestToken ||
        (expectedRevision != null &&
            _contextInvalidator?.revision != expectedRevision)) {
      PerformanceProbe.event(
        'recommendation.stale_result_discarded',
        state:
            'request_token=$requestToken latest_token=$_recommendationRequestToken '
            'expected_revision=$expectedRevision current_revision=${_contextInvalidator?.revision ?? 0}',
      );
      return false;
    }

    final suitabilityById = await _buildShootingSuitability(
      targets: result.scoredTargets,
      session: session,
      referenceTime: now,
      equipment: equipment,
      context: sessionContext,
    );
    if (_isDisposed ||
        requestToken != _recommendationRequestToken ||
        (expectedRevision != null &&
            _contextInvalidator?.revision != expectedRevision)) {
      PerformanceProbe.event(
        'recommendation.suitability_stale_result_discarded',
        state:
            'request_token=$requestToken latest_token=$_recommendationRequestToken '
            'expected_revision=$expectedRevision current_revision=${_contextInvalidator?.revision ?? 0}',
      );
      return false;
    }
    final automaticTargets = result.scoredTargets
        .where(
          (target) =>
              suitabilityById[target.object.id]?.automaticEligible ?? false,
        )
        .toList();
    final automaticIds = automaticTargets
        .map((target) => target.object.id)
        .toSet();
    final automaticRecommendations = result.allRecommendations
        .where(
          (recommendation) => automaticIds.contains(recommendation.object.id),
        )
        .toList();
    final automaticResultsById = {
      for (final recommendation in automaticRecommendations)
        recommendation.object.id: recommendation,
    };
    final needsFramingAwareReschedule =
        _multiNightFramingRepository != null &&
        _multiNightFramingMatchService != null;
    final qualityScheduleItems = needsFramingAwareReschedule
        ? _schedulerEngine
              .buildSchedule(
                SchedulerInput(
                  context: sessionContext,
                  session: session,
                  targets: automaticTargets,
                  resultsById: automaticResultsById,
                  referenceTime: now,
                  suitabilityByObjectId: suitabilityById,
                ),
              )
              .items
              .where((item) => item.status != ScheduleItemStatus.excluded)
              .toList()
        : result.scheduleItems
              .where(
                (item) =>
                    automaticIds.contains(item.target.object.id) &&
                    item.status != ScheduleItemStatus.excluded,
              )
              .toList();

    final candidateIds = automaticTargets
        .map((target) => target.object.id)
        .toList(growable: false);
    final scheduleIds = qualityScheduleItems
        .map((item) => item.target.object.id)
        .toList(growable: false);
    _lastScheduleRequestToken = requestToken;
    _lastScheduleContextRevision = revision;
    _lastScheduleCandidateIds = candidateIds;
    _scheduleState = ScheduleComputationState.current;
    _scheduleUpdatedAt = DateTime.now();
    PerformanceProbe.event(
      'scheduler.latest_result_applied',
      state:
          'revision=$revision request_token=$requestToken '
          'candidates=${candidateIds.length} candidate_hash=${Object.hashAll(candidateIds)} '
          'candidate_sample=${candidateIds.take(5).join(",")} '
          'schedules=${scheduleIds.length} selected=${scheduleIds.take(5).join(",")}',
    );

    _activeEquipment = allEquipment;
    _exclusionReasons = [
      ...result.exclusionReasons,
      ...suitabilityById.values
          .where((suitability) => !suitability.eligible)
          .map((suitability) => suitability.rejectionReason)
          .whereType<String>()
          .toSet(),
    ];
    _allRecommendedObjects = automaticRecommendations;
    _recommendedObjects = automaticRecommendations.take(mainLimit).toList();
    _scoredTargets = result.scoredTargets;
    _recommendedScheduleItems = qualityScheduleItems;
    _resultsById = {
      for (final recommendation in result.allRecommendations)
        recommendation.object.id: recommendation,
    };
    _shootingSuitabilityById = suitabilityById;
    _lastSessionContext = sessionContext;
    _lastSession = session;
    _lastReferenceTime = now;

    await _buildEquipmentGroups(equipment: equipment);
    await _autoGenerateTonightPlanIfNeeded();
    _applyShootingPlanFilter();
    await _persistResolvedPlanTimes();
    return !_isDisposed &&
        (expectedRevision == null ||
            _contextInvalidator?.revision == expectedRevision);
  }

  Future<void> _loadTonightPlan() async {
    final snapshot = await _shootingPlanService.loadSnapshotForDate(_planDate);
    _plannedObjectOrder = List<String>.from(snapshot.orderedObjectIds);
    _planEntriesById
      ..clear()
      ..addEntries(
        snapshot.entries.map((entry) => MapEntry(entry.objectId, entry)),
      );
    _userEditedTonightPlan = snapshot.userEdited;
  }

  Future<void> _persistTonightPlan() async {
    await _shootingPlanService.saveSnapshotForDate(
      _planDate,
      TonightShootingPlanSnapshot(
        orderedObjectIds: _plannedObjectOrder,
        userEdited: _userEditedTonightPlan,
        entries: _plannedObjectOrder
            .map(
              (id) =>
                  _planEntriesById[id] ??
                  TonightShootingPlanEntry(objectId: id),
            )
            .toList(),
      ),
    );
  }

  Future<void> _autoGenerateTonightPlanIfNeeded() async {
    if (_userEditedTonightPlan) return;

    final autoIds = _extractAutoPlanIds();
    _plannedObjectOrder = autoIds;
    _planEntriesById
      ..clear()
      ..addEntries(
        _recommendedScheduleItems
            .where((item) => autoIds.contains(item.target.object.id))
            .map(
              (item) => MapEntry(
                item.target.object.id,
                TonightShootingPlanEntry(
                  objectId: item.target.object.id,
                  startTime: item.startTime,
                  endTime: item.endTime,
                ),
              ),
            ),
      );
    _userEditedTonightPlan = false;
    await _persistTonightPlan();
  }

  Future<void> _persistResolvedPlanTimes() async {
    if (_plannedObjectOrder.isEmpty) return;
    var changed = false;
    for (final item in _scheduleItems) {
      final id = item.target.object.id;
      final current = _planEntriesById[id];
      if (current?.hasTimeOverride ?? false) continue;
      if (current?.startTime == item.startTime &&
          current?.endTime == item.endTime) {
        continue;
      }
      _planEntriesById[id] = TonightShootingPlanEntry(
        objectId: id,
        startTime: item.startTime,
        endTime: item.endTime,
      );
      changed = true;
    }
    if (changed) await _persistTonightPlan();
  }

  List<String> _extractAutoPlanIds() {
    final ids = <String>[];
    for (final item in _recommendedScheduleItems) {
      final id = item.target.object.id;
      if (ids.contains(id) || !canAddToShootingPlan(id)) {
        continue;
      }
      ids.add(id);
    }
    if (ids.isNotEmpty) {
      return ids;
    }

    if (_lastSessionContext?.observationStatus.allowsScheduling == false) {
      return const [];
    }

    return _recommendedObjects
        .map((result) => result.object.id)
        .where(canAddToShootingPlan)
        .take(4)
        .toList();
  }

  void _reorderScheduleItemsToMatchPlan() {
    if (_scheduleItems.isEmpty || _plannedObjectOrder.isEmpty) {
      return;
    }
    final byId = {
      for (final item in _scheduleItems) item.target.object.id: item,
    };
    _scheduleItems = _plannedObjectOrder
        .map((id) => byId[id])
        .whereType<ScheduleItem>()
        .toList();
  }

  void _sortScheduleItemsByPlanOrder() {
    _scheduleItems.sort((a, b) {
      final ai = _plannedObjectOrder.indexOf(a.target.object.id);
      final bi = _plannedObjectOrder.indexOf(b.target.object.id);
      if (ai == -1 && bi == -1) return 0;
      if (ai == -1) return 1;
      if (bi == -1) return -1;
      return ai.compareTo(bi);
    });
  }

  void _applyShootingPlanFilter() {
    if (_plannedObjectOrder.isEmpty) {
      if (_userEditedTonightPlan) {
        _scheduleItems = [];
        _scheduleEmptyMessage = '촬영 계획에 추가한 대상이 없습니다';
        return;
      }

      _scheduleItems = List<ScheduleItem>.from(_recommendedScheduleItems);
      _scheduleEmptyMessage = _scheduleItems.isEmpty
          ? (_lastSessionContext?.observationStatus.allowsScheduling == false
                ? SchedulerEngine.weatherLimitedMessage
                : '오늘 밤 촬영 순서를 추천할 대상이 없습니다')
          : null;
      return;
    }

    final context = _lastSessionContext;
    final session = _lastSession;
    final referenceTime = _lastReferenceTime;
    if (context == null || session == null || referenceTime == null) {
      _scheduleItems = [];
      _scheduleEmptyMessage = '촬영 계획 대상의 촬영 순서를 계산할 수 없습니다';
      return;
    }

    final plannedTargets = <ScoredObservationTarget>[];
    for (final id in _plannedObjectOrder) {
      for (final target in _scoredTargets) {
        if (target.object.id == id) {
          plannedTargets.add(target);
          break;
        }
      }
    }

    if (plannedTargets.isEmpty) {
      _scheduleItems = [];
      _scheduleEmptyMessage = '현재 조건에서 촬영 가능한 계획 대상이 없습니다';
      return;
    }

    final resultsById = <String, RecommendationResult>{};
    for (final target in plannedTargets) {
      final recommendation = _resultsById[target.object.id];
      if (recommendation == null) {
        _scheduleItems = [];
        _scheduleEmptyMessage = '촬영 계획 대상의 촬영 순서를 계산할 수 없습니다';
        return;
      }
      resultsById[target.object.id] = recommendation;
    }

    final fixedItems = <ScheduleItem>[];
    final automaticTargets = <ScoredObservationTarget>[];
    final occupiedWindows = <ShootingTimeWindow>[];
    for (final target in plannedTargets) {
      final entry = _planEntriesById[target.object.id];
      final recommendation = resultsById[target.object.id];
      if (entry != null &&
          entry.hasTimeOverride &&
          entry.hasValidTime &&
          recommendation != null) {
        final fixed = _manualScheduleItem(
          target: target,
          recommendation: recommendation,
          entry: entry,
        );
        fixedItems.add(fixed);
        occupiedWindows.add(
          ShootingTimeWindow(start: fixed.startTime, end: fixed.endTime),
        );
      } else {
        automaticTargets.add(target);
      }
    }

    final scheduleResult = _schedulerEngine.buildSchedule(
      SchedulerInput(
        context: context,
        session: session,
        targets: automaticTargets,
        resultsById: resultsById,
        referenceTime: referenceTime,
        suitabilityByObjectId: _shootingSuitabilityById,
        occupiedWindows: occupiedWindows,
      ),
    );

    _scheduleItems = [
      ...fixedItems,
      ...scheduleResult.items.where(
        (item) => item.status != ScheduleItemStatus.excluded,
      ),
    ]..sort((a, b) => a.startTime.compareTo(b.startTime));

    if (_userEditedTonightPlan) {
      _sortScheduleItemsByPlanOrder();
    }

    _scheduleEmptyMessage = _scheduleItems.isEmpty
        ? (scheduleResult.emptyMessage ?? '촬영 계획 대상의 촬영 순서를 계산할 수 없습니다')
        : null;
  }

  ScheduleItem _manualScheduleItem({
    required ScoredObservationTarget target,
    required RecommendationResult recommendation,
    required TonightShootingPlanEntry entry,
  }) {
    final start = entry.startTime!;
    final end = entry.endTime!;
    final duration = end.difference(start);
    final recommendedDuration =
        target.imagingAssessment?.trackingMode == TrackingMode.altAz
        ? target.imagingAssessment?.recommendedDailyExposure ??
              target.recommendedExposure
        : target.recommendedExposure;
    final status = duration >= recommendedDuration
        ? ScheduleItemStatus.optimal
        : duration >= target.minimumExposure
        ? ScheduleItemStatus.belowRecommended
        : ScheduleItemStatus.excluded;
    final suitability = _shootingSuitabilityById[target.object.id];
    return ScheduleItem(
      target: target,
      startTime: start,
      endTime: end,
      shootingDuration: duration,
      recommendedDuration: recommendedDuration,
      optimalTime: start.add(Duration(minutes: duration.inMinutes ~/ 2)),
      optimalAltitude:
          target.window.optimalAltitude ?? target.window.peakAltitude ?? 0,
      recommendationScore: target.score,
      schedulerPriority: target.schedulerPriority,
      urgencyScore: target.urgencyScore,
      status: status,
      result: recommendation,
      isManual: entry.source == TonightPlanSource.manual,
      hasTimeOverride: true,
      recommendedWindow: suitability?.recommendedWindow,
      framingWindow: suitability?.framingWindow,
    );
  }

  Future<Map<String, ShootingSuitability>> _buildShootingSuitability({
    required List<ScoredObservationTarget> targets,
    required TonightObservationSession session,
    required DateTime referenceTime,
    required List<Equipment> equipment,
    required ObservationContext context,
  }) async {
    final repository = _multiNightFramingRepository;
    final matchService = _multiNightFramingMatchService;
    final activeSite = _activeObservationSiteViewModel.active;
    final site = activeSite.site ??
        ObservationSite(
          id: 'current-location',
          name: activeSite.displayName,
          latitude: context.latitude,
          longitude: context.longitude,
          bortle: context.bortle,
          trackingMode: context.trackingMode,
          defaultMinAltitude: 0,
          defaultMaxAltitude: 90,
          createdAt: referenceTime,
          updatedAt: referenceTime,
          horizonPoints: activeSite.horizonProfile.points,
          blockedAzimuthRanges: activeSite.horizonProfile.blockedRanges,
        );
    final equipmentById = {for (final item in equipment) item.id: item};
    final result = <String, ShootingSuitability>{};

    for (final target in targets) {
      final equipmentId = target.imagingAssessment?.equipmentId;
      final selectedEquipment = equipmentId == null
          ? null
          : equipmentById[equipmentId];
      var hasReference = false;
      MultiNightFramingMatchResult? framingMatch;
      if (repository != null && selectedEquipment != null) {
        final reference = await repository.find(
          catalogObjectId: target.object.effectivePrimaryId,
          equipmentId: selectedEquipment.id,
        );
        hasReference = reference != null;
        if (reference != null && matchService != null) {
          framingMatch = _bestFramingMatchForSession(
            target: target,
            reference: reference,
            site: site,
            equipment: selectedEquipment,
            session: session,
            referenceTime: referenceTime,
            matchService: matchService,
          );
        }
      }
      result[target.object.id] = _shootingSuitabilityService.evaluate(
        target: target,
        hasFramingReference: hasReference,
        framingMatch: framingMatch,
      );
    }
    return result;
  }

  MultiNightFramingMatchResult? _bestFramingMatchForSession({
    required ScoredObservationTarget target,
    required MultiNightFramingReference reference,
    required ObservationSite site,
    required Equipment equipment,
    required TonightObservationSession session,
    required DateTime referenceTime,
    required MultiNightFramingMatchService matchService,
  }) {
    final dates = <DateTime>{
      DateTime(session.start.year, session.start.month, session.start.day),
      DateTime(session.end.year, session.end.month, session.end.day),
    };
    final darkWindows = <MultiNightDarkWindow>[
      (nightStart: session.start, nightEnd: session.end),
    ];
    MultiNightFramingMatchResult? fallback;
    MultiNightFramingMatchResult? best;
    var bestMinutes = -1;
    for (final date in dates) {
      final candidate = matchService.findToday(
        object: target.object,
        reference: reference,
        site: site,
        equipment: equipment,
        today: date,
        now: referenceTime,
        darkWindows: darkWindows,
      );
      fallback ??= candidate;
      final start = candidate.rangeStart;
      final end = candidate.rangeEnd;
      if (!candidate.isAvailable || start == null || end == null) continue;
      final clippedStart = start.isAfter(session.start) ? start : session.start;
      final clippedEnd = end.isBefore(session.end) ? end : session.end;
      final minutes = clippedEnd.isAfter(clippedStart)
          ? clippedEnd.difference(clippedStart).inMinutes
          : 0;
      if (minutes > bestMinutes) {
        best = candidate;
        bestMinutes = minutes;
      }
    }
    return best ?? fallback;
  }

  ImagingEquipmentFit? _equipmentFitFor({
    required CatalogObject object,
    required ObjectObservationWindow window,
    required List<Equipment> equipment,
    required ObservationContext context,
  }) {
    if (equipment.isEmpty) return null;

    ImagingOrientationContext? orientation;
    if (_trackingMode == TrackingMode.altAz) {
      final start =
          window.recommendStartTime ??
          window.optimalStartTime ??
          window.peakAltitudeTime;
      final end = window.observationEndTime ?? window.optimalEndTime;
      if (start != null && end != null && end.isAfter(start)) {
        final raHours = CelestialPositionService.parseRaHours(object.ra);
        final declinationDeg = CelestialPositionService.parseDecDeg(object.dec);
        if (raHours != null && declinationDeg != null) {
          orientation = ImagingOrientationContext(
            latitude: context.latitude,
            longitude: context.longitude,
            raHours: raHours,
            declinationDeg: declinationDeg,
            windowStart: start,
            windowEnd: end,
          );
        }
      }
    }

    final recommendation = _equipmentRecommendationService.recommendForObject(
      object: object,
      equipment: equipment,
      orientation: orientation,
    );
    if (recommendation.imaging.isEmpty) return null;
    final best = recommendation.imaging.first;
    return ImagingEquipmentFit(
      score: best.score,
      screenFillPercent: best.screenFillPercent,
      equipmentId: best.equipment.id,
      equipmentName: best.equipment.name,
      framingRecommendation: best.framingRecommendation,
      supportsMosaic: best.equipment.supportsMosaic,
    );
  }

  Future<void> _buildEquipmentGroups({List<Equipment>? equipment}) async {
    _equipmentTonightGroups = [];
    _todayEquipmentChipsByObjectId.clear();
    _todayEquipmentRecByObjectId.clear();

    final availableEquipment =
        equipment ?? await _equipmentRepository.getAll(activeOnly: true);
    if (availableEquipment.isEmpty || _allRecommendedObjects.isEmpty) return;

    final sortedEquipment = [...availableEquipment]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    final todayRecByObjectId = <String, TodayEquipmentRecommendation>{};
    for (final rec in _allRecommendedObjects) {
      todayRecByObjectId[rec.object.id] = _equipmentRecommendationService
          .recommendForToday(
            object: rec.object,
            equipment: availableEquipment,
            recommendation: rec,
            condition: _observationCondition,
            observerLatitude: _hasLocation ? _latitude : null,
            observerLongitude: _hasLocation ? _longitude : null,
            trackingMode: _trackingMode,
          );
      _todayEquipmentRecByObjectId[rec.object.id] =
          todayRecByObjectId[rec.object.id]!;
      _cacheTodayEquipmentChips(
        rec.object.id,
        todayRecByObjectId[rec.object.id]!,
      );
    }

    final groups = <EquipmentTonightGroup>[];

    for (final eq in sortedEquipment) {
      if (eq.isImaging) {
        final targets = _allRecommendedObjects
            .where(
              (rec) =>
                  todayRecByObjectId[rec.object.id]?.imaging?.equipment.id ==
                  eq.id,
            )
            .toList();
        if (targets.isEmpty) continue;
        groups.add(
          EquipmentTonightGroup(
            equipment: eq,
            targets: targets,
            starCount: _maxStarCount(targets),
            isVisual: false,
          ),
        );
      } else if (eq.isVisual) {
        final targets = _allRecommendedObjects.where((rec) {
          final todayRec = todayRecByObjectId[rec.object.id];
          if (todayRec == null) return false;
          return todayRec.visual.any(
            (visual) =>
                visual.equipment.id == eq.id &&
                visual.isFeasibleToday &&
                visual.isRecommended,
          );
        }).toList();
        if (targets.isEmpty) continue;
        groups.add(
          EquipmentTonightGroup(
            equipment: eq,
            targets: targets,
            starCount: _maxStarCount(targets),
            isVisual: true,
          ),
        );
      }
    }

    _equipmentTonightGroups = groups;
  }

  void _cacheTodayEquipmentChips(
    String objectId,
    TodayEquipmentRecommendation todayRec,
  ) {
    final items = <CatalogEquipmentChipItem>[];

    final imaging = todayRec.imaging;
    if (imaging != null) {
      final name = imaging.equipment.name.trim();
      if (name.isNotEmpty) {
        items.add(
          CatalogEquipmentChipItem(
            label: name,
            equipmentId: imaging.equipment.id,
          ),
        );
      }
    }

    for (final visual in todayRec.visual) {
      if (!visual.isRecommended || !visual.isFeasibleToday) continue;
      items.add(
        CatalogEquipmentChipItem(
          label: '안시',
          equipmentId: visual.equipment.id,
          isVisual: true,
        ),
      );
      break;
    }

    _todayEquipmentChipsByObjectId[objectId] = CatalogEquipmentChips(
      items: items,
    );
  }

  int _maxStarCount(List<RecommendationResult> targets) {
    return targets
        .map((target) => target.starCount)
        .reduce((a, b) => a > b ? a : b);
  }

  Future<void> load({bool silent = false, bool deferHeavyWork = false}) async {
    final loadStopwatch = kDebugMode ? (Stopwatch()..start()) : null;
    if (!silent) {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();
    } else {
      _errorMessage = null;
    }

    final sw = Stopwatch()..start();
    try {
      await _activeObservationSiteViewModel.load();
      _applyActiveSiteDefaults();
      final now = DateTime.now();

      _recommendationSettings = await _recommendationSettingsService.load();

      final allObjects = await _catalogRepository.getAll(listOnly: true);
      _cachedAllObjects = allObjects;
      debugPrint(
        '[HomeVM] catalog getAll: ${sw.elapsedMilliseconds}ms '
        '(${allObjects.length} objects)',
      );

      final moon = _moonFromPhase(ObservationScoreService.computeMoonInfo(now));
      _observationCondition = _buildCondition(
        moon: moon,
        siteName: _activeObservationSiteViewModel.active.displayName,
      );

      if (_nightStart == null || _nightEnd == null) {
        final est = _estimateNightWindow(now);
        _nightStart = est.nightStart;
        _nightEnd = est.nightEnd;
      }

      await _loadTonightPlan();

      // 무거운 추천 계산 전에 홈 셸(달/관측조건/계획)을 먼저 그린다.
      _isLoading = false;
      notifyListeners();

      if (deferHeavyWork) {
        _pendingHeavyLoad = _PendingHomeHeavyLoad(
          allObjects: allObjects,
          now: now,
          moonIllumination: moon.illumination,
        );
        _fetchWeather();
        return;
      }

      await _finishHeavyLoad(
        allObjects: allObjects,
        now: now,
        moonIllumination: moon.illumination,
        sw: sw,
      );
    } catch (error) {
      _errorMessage = error.toString();
      _isLoading = false;
    } finally {
      loadStopwatch?.stop();
      if (loadStopwatch != null) {
        PerformanceProbe.record(
          'home.load',
          loadStopwatch.elapsed,
          state: 'silent=$silent deferred=$deferHeavyWork',
        );
      }
      if (!deferHeavyWork) {
        notifyListeners();
      }
    }

    if (!deferHeavyWork) {
      _fetchWeather();
    }
  }

  /// 스플래시 종료 후 추천·카테고리 진행률을 채운다.
  Future<void> finishDeferredHeavyWork() async {
    final pending = _pendingHeavyLoad;
    if (pending == null) return;
    _pendingHeavyLoad = null;
    await _finishHeavyLoad(
      allObjects: pending.allObjects,
      now: pending.now,
      moonIllumination: pending.moonIllumination,
      sw: Stopwatch()..start(),
    );
  }

  Future<void> _finishHeavyLoad({
    required List<CatalogObject> allObjects,
    required DateTime now,
    required double moonIllumination,
    required Stopwatch sw,
  }) async {
    await _applyRecommendations(
      allObjects: allObjects,
      now: now,
      moonIllumination: moonIllumination,
    );
    debugPrint('[HomeVM] recommendations ready: ${sw.elapsedMilliseconds}ms');

    _categoryProgress =
        [
          CatalogType.messier,
          CatalogType.ngc,
          CatalogType.ic,
          CatalogType.caldwell,
          CatalogType.sh2,
          CatalogType.star,
          CatalogType.solar,
          CatalogType.milky,
        ].map((type) {
          final objects = allObjects.where((o) => o.catalog == type).toList();
          return CategoryProgress(
            type: type,
            total: objects.length,
            captured: objects.where((o) => o.captured).length,
          );
        }).toList();
    debugPrint('[HomeVM] load complete: ${sw.elapsedMilliseconds}ms');
    notifyListeners();
  }

  Future<void> refresh() async {
    if (_isWeatherLoading) return;
    await _fetchWeather();
  }

  Future<void> refreshForActiveSite() async {
    _applyActiveSiteDefaults();
    await _fetchWeather();
  }

  Future<void> _handleContextInvalidation(
    ObservationContextChange change,
    int revision,
  ) async {
    _markRecommendationRecalculating();
    final refreshSiteCache =
        change == ObservationContextChange.observationSite ||
        change == ObservationContextChange.horizon;
    final changesLocation =
        refreshSiteCache || change == ObservationContextChange.activeSite;
    try {
      if (refreshSiteCache) {
        await _activeObservationSiteViewModel.load(force: true);
      }

      if (changesLocation) {
        _celestialPositionService.clearCache();
        _applyActiveSiteDefaults();
      }

      if (_cachedAllObjects.isNotEmpty &&
          _nightStart != null &&
          _nightEnd != null) {
        final applied = await _applyRecommendations(
          allObjects: _cachedAllObjects,
          now: DateTime.now(),
          cloudCoverage: _observationCondition?.cloudCover ?? 0,
          windSpeed: _observationCondition?.windSpeed ?? 0,
          moonIllumination: _observationCondition?.moon.illumination,
          expectedRevision: revision,
        );
        if (!applied || _contextInvalidator?.revision != revision) return;
      }

      _markRecommendationCurrent();
      if (changesLocation) {
        unawaited(_fetchWeather());
      }
    } catch (_) {
      if (_contextInvalidator?.revision == revision) {
        _markRecommendationFailed();
      }
    }
  }

  Future<void> _recalculateWithoutInvalidator() async {
    try {
      final applied = await _applyRecommendations(
        allObjects: _cachedAllObjects,
        now: DateTime.now(),
        cloudCoverage: _observationCondition?.cloudCover ?? 0,
        windSpeed: _observationCondition?.windSpeed ?? 0,
        moonIllumination: _observationCondition?.moon.illumination,
      );
      if (applied) _markRecommendationCurrent();
    } catch (_) {
      _markRecommendationFailed();
    }
  }

  void _markRecommendationRecalculating() {
    if (_isDisposed) return;
    _recommendationErrorMessage = null;
    _scheduleState = ScheduleComputationState.recalculating;
    if (_recommendationState == RecommendationComputationState.recalculating) {
      return;
    }
    _recommendationState = RecommendationComputationState.recalculating;
    notifyListeners();
  }

  void _markRecommendationCurrent() {
    if (_isDisposed) return;
    _recommendationState = RecommendationComputationState.current;
    _scheduleState = ScheduleComputationState.current;
    _scheduleUpdatedAt ??= DateTime.now();
    _recommendationErrorMessage = null;
    notifyListeners();
  }

  void _markRecommendationFailed() {
    if (_isDisposed) return;
    _recommendationState = RecommendationComputationState.failed;
    _scheduleState = ScheduleComputationState.failed;
    _recommendationErrorMessage = '추천을 다시 계산하지 못했습니다. 잠시 후 다시 시도해주세요.';
    notifyListeners();
  }

  void _applyActiveSiteDefaults() {
    final active = _activeObservationSiteViewModel.active;
    _trackingMode = active.effectiveTrackingMode;
    if (active.latitude != null && active.longitude != null) {
      _latitude = active.latitude!;
      _longitude = active.longitude!;
      _hasLocation = true;
    }
  }

  Future<void> _fetchWeather() async {
    final requestGeneration = ++_weatherRequestGeneration;
    _isWeatherLoading = true;
    notifyListeners();

    try {
      final active = _activeObservationSiteViewModel.active;
      final location = active.isCurrentLocation
          ? await _locationService.getCurrentLocation()
          : LocationData(
              latitude: active.latitude!,
              longitude: active.longitude!,
              accuracy: 0,
              timestamp: DateTime.now(),
            );
      if (requestGeneration != _weatherRequestGeneration) return;

      if (active.isCurrentLocation) {
        _activeObservationSiteViewModel.updateCurrentLocation(
          latitude: location.latitude,
          longitude: location.longitude,
        );
      }

      final latDiff = (_latitude - location.latitude).abs();
      final lonDiff = (_longitude - location.longitude).abs();
      if (latDiff > 0.5 || lonDiff > 0.5) {
        _celestialPositionService.clearCache();
      }

      _latitude = location.latitude;
      _longitude = location.longitude;
      _hasLocation = true;

      final results = await Future.wait([
        _weatherService.getCurrentWeather(
          location.latitude,
          location.longitude,
        ),
        _weatherService.getForecast(location.latitude, location.longitude),
      ]);

      final weather = results[0] as WeatherData;
      final forecasts = results[1] as List<WeatherForecastSlot>;
      if (requestGeneration != _weatherRequestGeneration) return;

      await _weatherCacheService.save(
        latitude: location.latitude,
        longitude: location.longitude,
        weather: weather,
        forecasts: forecasts,
      );

      await _applyWeatherResponse(
        latitude: location.latitude,
        longitude: location.longitude,
        weather: weather,
        forecasts: forecasts,
        siteName: active.displayName,
      );
    } catch (e) {
      if (requestGeneration != _weatherRequestGeneration) return;
      final cached = await _weatherCacheService.load(
        latitude: _latitude,
        longitude: _longitude,
      );

      if (cached != null) {
        await _applyWeatherResponse(
          latitude: cached.latitude,
          longitude: cached.longitude,
          weather: cached.weather,
          forecasts: cached.forecasts,
          isFromCache: true,
          cachedAt: cached.cachedAt,
          weatherError: '오프라인 · 저장된 날씨 정보 표시',
          siteName: _activeObservationSiteViewModel.active.displayName,
        );
      } else {
        final current = _observationCondition;
        if (current != null) {
          _observationCondition = ObservationCondition(
            score: current.score,
            siteName: current.siteName,
            moon: current.moon,
            weather: current.weather,
            weatherError: _friendlyWeatherError(e),
            qualityComponents: current.qualityComponents,
            averageQuality: current.averageQuality,
            condensationRisk: current.condensationRisk,
            tonightSlots: current.tonightSlots,
            bestTonightSlot: current.bestTonightSlot,
            observationWindow: current.observationWindow,
            recommendedWindow: current.recommendedWindow,
            nightAverageScore: current.nightAverageScore,
            contributions: current.contributions,
            averageCloudCoverage: current.averageCloudCoverage,
            averageWindSpeed: current.averageWindSpeed,
            averageTemperature: current.averageTemperature,
            averageMoonIllumination: current.averageMoonIllumination,
            averagePrecipitationPop: current.averagePrecipitationPop,
            averageVisibilityMeters: current.averageVisibilityMeters,
            cloudCover: current.cloudCover,
            visibilityMeters: current.visibilityMeters,
            humidity: current.humidity,
            windSpeed: current.windSpeed,
            precipitationProbability: current.precipitationProbability,
            dewPoint: current.dewPoint,
            weatherScore: current.weatherScore,
            isObservationFeasible: current.isObservationFeasible,
            primaryInfeasibleReason: current.primaryInfeasibleReason,
            infeasibleUserMessage: current.infeasibleUserMessage,
            isWeatherFromCache: current.isWeatherFromCache,
            weatherCachedAt: current.weatherCachedAt,
          );
        }
      }
    } finally {
      if (requestGeneration == _weatherRequestGeneration) {
        _isWeatherLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> _applyWeatherResponse({
    required double latitude,
    required double longitude,
    required WeatherData weather,
    required List<WeatherForecastSlot> forecasts,
    bool isFromCache = false,
    DateTime? cachedAt,
    String? weatherError,
    String? siteName,
  }) async {
    _cachedForecasts = forecasts;
    final now = DateTime.now();
    final moon = _moonFromPhase(ObservationScoreService.computeMoonInfo(now));

    final nightWindow = ObservationScoreService.observationNightWindow(
      now: now,
      sunrise: weather.sunrise,
      sunset: weather.sunset,
    );
    _nightStart = nightWindow.nightStart;
    _nightEnd = nightWindow.nightEnd;
    await _loadTonightPlan();

    final session = TonightObservationSession(
      start: _nightStart!,
      end: _nightEnd!,
    );

    final context = await _observationEngine.buildContext(
      latitude: latitude,
      longitude: longitude,
      currentTime: now,
      weather: weather,
      forecasts: forecasts,
      session: session,
    );

    final summary = ObservationScoreService.buildTonightSummary(
      context: context,
      forecasts: forecasts,
      sunrise: weather.sunrise,
      sunset: weather.sunset,
      now: now,
    );

    _observationCondition = _buildCondition(
      moon: moon,
      siteName:
          siteName ??
          (weather.cityName.isNotEmpty ? weather.cityName : '현재 위치'),
      summary: summary,
      currentWeather: weather,
      weatherError: weatherError,
      isWeatherFromCache: isFromCache,
      weatherCachedAt: cachedAt,
      observationStatus: context.observationStatus,
      statusPrimaryReason: context.statusPrimaryReason,
      statusUserMessage: context.statusUserMessage,
    );

    if (_cachedAllObjects.isNotEmpty) {
      await _applyRecommendations(
        allObjects: _cachedAllObjects,
        now: now,
        moonIllumination: summary?.averageMoonIllumination ?? moon.illumination,
        cloudCoverage: summary?.averageCloudCoverage.round() ?? 0,
        windSpeed: summary?.averageWindSpeed ?? 0,
        expectedRevision: _contextInvalidator?.revision,
      );
    }
  }

  static String _friendlyWeatherError(Object e) {
    final msg = e.toString();
    if (msg.contains('API Key') || msg.contains('appid')) {
      return '날씨 서비스를 사용할 수 없습니다';
    }
    if (msg.contains('위치') ||
        msg.contains('permission') ||
        msg.contains('Location')) {
      return '위치 권한이 필요합니다';
    }
    return '날씨 정보를 불러올 수 없습니다';
  }

  @override
  void dispose() {
    _isDisposed = true;
    _weatherRequestGeneration += 1;
    _contextInvalidator?.unbind(_contextBindingToken);
    super.dispose();
  }
}

class _PendingHomeHeavyLoad {
  const _PendingHomeHeavyLoad({
    required this.allObjects,
    required this.now,
    required this.moonIllumination,
  });

  final List<CatalogObject> allObjects;
  final DateTime now;
  final double moonIllumination;
}

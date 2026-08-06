import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/constants/catalog_type.dart';
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
import '../../../data/repositories/catalog_repository.dart';
import '../../../data/repositories/equipment_repository.dart';
import '../../../services/celestial_position_service.dart';
import '../../../services/equipment/equipment_recommendation_service.dart';
import '../../../services/tonight_shooting_plan_service.dart';
import '../../../services/location_service.dart';
import '../../../services/observation_engine.dart';
import '../../../services/observation_quality_service.dart';
import '../../../services/observation_score_service.dart';
import '../../../services/recommendation_engine.dart';
import '../../../services/recommendation_settings_service.dart';
import '../../../services/scheduler_engine.dart';
import '../../../services/weather_cache_service.dart';
import '../../../services/weather_service.dart';
import '../../../services/rain_observation_policy.dart';

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

// ── ViewModel ────────────────────────────────────────────────────────────────

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
  );

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

  bool _isLoading = false;
  bool _isWeatherLoading = false;
  String? _errorMessage;
  List<RecommendationResult> _recommendedObjects = [];
  List<RecommendationResult> _allRecommendedObjects = [];
  List<ScheduleItem> _scheduleItems = [];
  List<EquipmentTonightGroup> _equipmentTonightGroups = [];
  List<String> _plannedObjectOrder = [];
  bool _userEditedTonightPlan = false;
  List<ScheduleItem> _recommendedScheduleItems = [];
  final Map<String, CatalogEquipmentChips> _todayEquipmentChipsByObjectId = {};
  final Map<String, TodayEquipmentRecommendation> _todayEquipmentRecByObjectId =
      {};
  List<ScoredObservationTarget> _scoredTargets = [];
  Map<String, RecommendationResult> _resultsById = {};
  ObservationContext? _lastSessionContext;
  TonightObservationSession? _lastSession;
  DateTime? _lastReferenceTime;
  List<CategoryProgress> _categoryProgress = [];
  ObservationCondition? _observationCondition;
  List<CatalogObject> _cachedAllObjects = [];
  List<WeatherForecastSlot> _cachedForecasts = [];
  List<String> _exclusionReasons = [];
  String? _scheduleEmptyMessage;
  _PendingHomeHeavyLoad? _pendingHeavyLoad;

  double _latitude = 37.5;
  double _longitude = 127.0;
  bool _hasLocation = false;

  DateTime? _nightStart;
  DateTime? _nightEnd;

  RecommendationSettings _recommendationSettings =
      RecommendationSettings.defaults;

  bool get isLoading => _isLoading;
  bool get isWeatherLoading => _isWeatherLoading;
  String? get errorMessage => _errorMessage;
  List<RecommendationResult> get recommendedObjects => _recommendedObjects;
  List<RecommendationResult> get allRecommendedObjects =>
      _allRecommendedObjects;
  List<ScheduleItem> get scheduleItems => _scheduleItems;
  List<EquipmentTonightGroup> get equipmentTonightGroups =>
      _equipmentTonightGroups;
  Set<String> get plannedObjectIds => Set.unmodifiable(_plannedObjectOrder);
  bool get userEditedTonightPlan => _userEditedTonightPlan;
  List<CategoryProgress> get categoryProgress => _categoryProgress;
  ObservationCondition? get observationCondition => _observationCondition;
  List<String> get exclusionReasons => _exclusionReasons;
  String? get scheduleEmptyMessage => _scheduleEmptyMessage;
  bool get hasLocation => _hasLocation;
  double get latitude => _latitude;
  double get longitude => _longitude;
  ObservationContext? get lastSessionContext => _lastSessionContext;

  DateTime get _planDate {
    final night = _nightStart ?? DateTime.now();
    return DateTime(night.year, night.month, night.day);
  }

  bool isPlanned(String objectId) => _plannedObjectOrder.contains(objectId);

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
    _userEditedTonightPlan = false;
    await _persistTonightPlan();
    _applyShootingPlanFilter();
    notifyListeners();
  }

  CatalogEquipmentChips todayEquipmentChipsFor(String objectId) =>
      _todayEquipmentChipsByObjectId[objectId] ?? const CatalogEquipmentChips();

  TodayEquipmentRecommendation? todayEquipmentRecommendationFor(
    String objectId,
  ) =>
      _todayEquipmentRecByObjectId[objectId];

  /// 오늘 촬영 장비 추천이 있는 대상만 촬영 계획에 추가 가능 (안시 전용 제외).
  bool canAddToShootingPlan(String objectId) {
    final chips = todayEquipmentChipsFor(objectId);
    return chips.items.any((item) => !item.isVisual);
  }

  Future<void> toggleTonightPlan(String objectId) async {
    if (_plannedObjectOrder.contains(objectId)) {
      _plannedObjectOrder =
          _plannedObjectOrder.where((id) => id != objectId).toList();
    } else {
      if (!canAddToShootingPlan(objectId)) return;
      _plannedObjectOrder = [..._plannedObjectOrder, objectId];
    }
    _userEditedTonightPlan = true;
    await _persistTonightPlan();
    _applyShootingPlanFilter();
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
      slotWeather = ObservationWeather.fromForecast(summary!.bestSlot!.forecast);
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
        cloudCover: slotWeather?.cloudCover ?? summary.averageCloudCoverage.round(),
        visibilityMeters:
            slotWeather?.visibility ?? summary.averageVisibilityMeters,
        humidity: slotWeather?.humidity ?? summary.bestSlot?.forecast.humidity ?? 50,
        windSpeed: slotWeather?.windSpeed ?? summary.averageWindSpeed,
        precipitationProbability:
            slotWeather?.precipitationProbability ?? summary.averagePrecipitationPop,
        dewPoint: slotWeather?.dewPoint ??
            ObservationScoreService.dewPointCelsius(
              summary.averageTemperature,
              summary.bestSlot?.forecast.humidity ?? 50,
            ),
        weatherScore:
            slotWeather?.weatherScore ?? window?.averageScore.toDouble() ?? 0,
        isObservationFeasible:
            observationStatus != ObservationStatus.unavailable,
        observationStatus: observationStatus,
        statusPrimaryReason: statusPrimaryReason ?? summary.primaryInfeasibleReason,
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
      dewPoint: slotWeather?.dewPoint ??
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
  ) {
    const sunsetH = [17, 17, 18, 19, 19, 19, 19, 19, 18, 17, 17, 17];
    const sunriseH = [7, 7, 6, 6, 5, 5, 5, 5, 6, 6, 7, 7];

    final m = now.month - 1;
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    final sunset = DateTime(today.year, today.month, today.day, sunsetH[m], 30);
    final sunrise = DateTime(
      tomorrow.year,
      tomorrow.month,
      tomorrow.day,
      sunriseH[m],
      30,
    );

    final nightStart = sunset.add(const Duration(minutes: 80));
    return (nightStart: nightStart, nightEnd: sunrise);
  }

  Future<void> _applyRecommendations({
    required List<CatalogObject> allObjects,
    required DateTime now,
    int cloudCoverage = 0,
    double windSpeed = 0,
    double? moonIllumination,
    int mainLimit = 4,
    int allLimit = 20,
  }) async {
    if (_nightStart == null || _nightEnd == null) return;

    final session = TonightObservationSession(
      start: _nightStart!,
      end: _nightEnd!,
    );

    final context = await _observationEngine.buildContext(
      latitude: _latitude,
      longitude: _longitude,
      currentTime: now,
      weather: _observationCondition?.weather,
      forecasts: _cachedForecasts,
      session: session,
      catalog: allObjects,
    );

    final sessionContext = context.copyWith(
      observationStart: session.start,
      observationEnd: session.end,
      moonIllumination: moonIllumination ?? context.moonIllumination,
    );

    final result = await _recommendationEngine.build(
      catalog: allObjects,
      settings: _recommendationSettings,
      context: sessionContext,
      session: session,
      limit: allLimit,
      windSpeed: windSpeed,
      referenceTime: now,
    );

    _exclusionReasons = result.exclusionReasons;
    _allRecommendedObjects = result.allRecommendations;
    _recommendedObjects = result.allRecommendations.take(mainLimit).toList();
    _scoredTargets = result.scoredTargets;
    _recommendedScheduleItems = result.scheduleItems;
    _resultsById = {
      for (final rec in result.allRecommendations) rec.object.id: rec,
    };
    _lastSessionContext = sessionContext;
    _lastSession = session;
    _lastReferenceTime = now;

    await _buildEquipmentGroups();
    await _autoGenerateTonightPlanIfNeeded();
    _applyShootingPlanFilter();
  }

  Future<void> _loadTonightPlan() async {
    final snapshot = await _shootingPlanService.loadSnapshotForDate(_planDate);
    _plannedObjectOrder = List<String>.from(snapshot.orderedObjectIds);
    _userEditedTonightPlan = snapshot.userEdited;
  }

  Future<void> _persistTonightPlan() async {
    await _shootingPlanService.saveOrderedForDate(
      _planDate,
      _plannedObjectOrder,
      userEdited: _userEditedTonightPlan,
    );
  }

  Future<void> _autoGenerateTonightPlanIfNeeded() async {
    if (_plannedObjectOrder.isNotEmpty || _userEditedTonightPlan) {
      return;
    }

    final autoIds = _extractAutoPlanIds();
    if (autoIds.isEmpty) {
      return;
    }

    _plannedObjectOrder = autoIds;
    _userEditedTonightPlan = false;
    await _persistTonightPlan();
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
          ? '오늘 밤 촬영 순서를 추천할 대상이 없습니다'
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
      _scheduleEmptyMessage = '촬영 계획 대상의 촬영 순서를 계산할 수 없습니다';
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

    final scheduleResult = _schedulerEngine.buildSchedule(
      SchedulerInput(
        context: context,
        session: session,
        targets: plannedTargets,
        resultsById: resultsById,
        referenceTime: referenceTime,
      ),
    );

    _scheduleItems = scheduleResult.items
        .where((item) => item.status != ScheduleItemStatus.excluded)
        .toList();

    if (_userEditedTonightPlan) {
      _sortScheduleItemsByPlanOrder();
    }

    _scheduleEmptyMessage = _scheduleItems.isEmpty
        ? (scheduleResult.emptyMessage ??
            '촬영 계획 대상의 촬영 순서를 계산할 수 없습니다')
        : null;
  }

  Future<void> _buildEquipmentGroups() async {
    _equipmentTonightGroups = [];
    _todayEquipmentChipsByObjectId.clear();
    _todayEquipmentRecByObjectId.clear();

    final equipment = await _equipmentRepository.getAll(activeOnly: true);
    if (equipment.isEmpty || _allRecommendedObjects.isEmpty) return;

    final sortedEquipment = [...equipment]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    final todayRecByObjectId = <String, TodayEquipmentRecommendation>{};
    for (final rec in _allRecommendedObjects) {
      todayRecByObjectId[rec.object.id] =
          _equipmentRecommendationService.recommendForToday(
        object: rec.object,
        equipment: equipment,
        recommendation: rec,
        condition: _observationCondition,
        observerLatitude: _hasLocation ? _latitude : null,
        observerLongitude: _hasLocation ? _longitude : null,
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

    _todayEquipmentChipsByObjectId[objectId] = CatalogEquipmentChips(items: items);
  }

  int _maxStarCount(List<RecommendationResult> targets) {
    return targets
        .map((target) => target.starCount)
        .reduce((a, b) => a > b ? a : b);
  }

  Future<void> load({bool silent = false, bool deferHeavyWork = false}) async {
    if (!silent) {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();
    } else {
      _errorMessage = null;
    }

    final sw = Stopwatch()..start();
    try {
      final now = DateTime.now();

      _recommendationSettings = await _recommendationSettingsService.load();

      final allObjects = await _catalogRepository.getAll(listOnly: true);
      _cachedAllObjects = allObjects;
      debugPrint('[HomeVM] catalog getAll: ${sw.elapsedMilliseconds}ms '
          '(${allObjects.length} objects)');

      final moon = _moonFromPhase(ObservationScoreService.computeMoonInfo(now));
      _observationCondition = _buildCondition(
        moon: moon,
        siteName: '현재 위치',
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
    debugPrint(
      '[HomeVM] recommendations ready: ${sw.elapsedMilliseconds}ms',
    );

    _categoryProgress = [
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

  Future<void> _fetchWeather() async {
    _isWeatherLoading = true;
    notifyListeners();

    try {
      final location = await _locationService.getCurrentLocation();

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
        _weatherService.getForecast(
          location.latitude,
          location.longitude,
        ),
      ]);

      final weather = results[0] as WeatherData;
      final forecasts = results[1] as List<WeatherForecastSlot>;

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
      );
    } catch (e) {
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
      _isWeatherLoading = false;
      notifyListeners();
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
      siteName: weather.cityName.isNotEmpty ? weather.cityName : '현재 위치',
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
      );
    }
  }

  static String _friendlyWeatherError(Object e) {
    final msg = e.toString();
    if (msg.contains('API Key') || msg.contains('appid')) {
      return '날씨 API 키가 설정되지 않았습니다';
    }
    if (msg.contains('위치') ||
        msg.contains('permission') ||
        msg.contains('Location')) {
      return '위치 권한이 필요합니다';
    }
    return '날씨 정보를 불러올 수 없습니다';
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

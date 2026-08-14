import 'package:flutter/foundation.dart';

import '../core/constants/catalog_type.dart';
import '../core/constants/imaging_difficulty.dart';
import '../core/constants/observation_status_config.dart';
import '../data/models/catalog_object.dart';
import '../data/models/imaging_suitability_assessment.dart';
import '../data/models/observation_context.dart';
import '../data/models/object_observation_window.dart';
import '../data/models/observation_status.dart';
import '../data/models/recommendation_build_result.dart';
import '../data/models/recommendation_result.dart';
import '../data/models/scored_observation_target.dart';
import '../data/models/scheduler_models.dart';
import '../data/models/tonight_observation_session.dart';
import 'app_logger.dart';
import 'celestial_position_service.dart';
import 'exposure_policy.dart';
import 'equipment/field_orientation_calculator.dart';
import 'imaging_suitability_service.dart';
import 'object_imaging_profile_provider.dart';
import 'recommendation/feasibility_exclusion_messages.dart';
import 'recommendation/limited_recommendation_policy.dart';
import 'recommendation/recommendation_candidate_sorter.dart';
import 'recommendation/recommendation_exclusion_messages.dart';
import 'recommendation/recommendation_reason_builder.dart';
import 'recommendation/observation_window_calculator.dart';
import 'recommendation_settings_service.dart';
import 'scheduler_engine.dart';
import 'scoring/recommendation_score.dart';

/// Evaluates the catalog for tonight's observation session.
class RecommendationEngine {
  RecommendationEngine(
    this._celestialPositionService,
    this._exposurePolicy,
    this._profileProvider,
    this._schedulerEngine, {
    RecommendationScore? recommendationScore,
    ObservationWindowCalculator? windowCalculator,
    ImagingSuitabilityService? imagingSuitabilityService,
  }) : _recommendationScore =
           recommendationScore ?? const RecommendationScore(),
       _windowCalculator =
           windowCalculator ??
           ObservationWindowCalculator(_celestialPositionService),
       _imagingSuitabilityService =
           imagingSuitabilityService ?? const ImagingSuitabilityService();

  final CelestialPositionService _celestialPositionService;
  final ExposurePolicy _exposurePolicy;
  final ObjectImagingProfileProvider _profileProvider;
  final SchedulerEngine _schedulerEngine;
  final RecommendationScore _recommendationScore;
  final ObservationWindowCalculator _windowCalculator;
  final ImagingSuitabilityService _imagingSuitabilityService;

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
    final filtered = _filterCatalog(catalog, settings);
    if (filtered.isEmpty) {
      return _emptyResult(
        session: session,
        context: context,
        referenceTime: referenceTime ?? context.currentTime,
        exclusionReasons: const ['선택된 카탈로그의 대상이 없습니다'],
      );
    }

    final now = referenceTime ?? context.currentTime;
    final refTime = _clampReferenceTime(now, session);

    // 관측 불가여도 기상은 변할 수 있으므로, 천체·광해 기준으로 추천/스케줄은 계속 계산한다.
    final evalContext =
        context.observationStatus == ObservationStatus.unavailable
        ? _planningContextIgnoringWeather(context)
        : context;

    final month = session.start.month;
    final season = RecommendationReasonBuilder.seasonLabel(month);

    var excludedAltitude = 0;
    var excludedAzimuth = 0;
    var excludedNoWindow = 0;
    var excludedLightPollution = 0;
    var excludedInsufficientDuration = 0;
    var excludedLimitedDifficulty = 0;

    final isLimited =
        evalContext.observationStatus == ObservationStatus.limited;

    final candidates = <ScoredObservationTarget>[];

    // 카탈로그가 클수록 메인 isolate에서 동기 계산이 길어지므로
    // 일정 간격마다 이벤트 루프에 양보해 첫 진입 UI 버벅임을 줄인다.
    const yieldEvery = 40;
    var processed = 0;

    for (final object in filtered) {
      processed++;
      if (processed % yieldEvery == 0) {
        await Future<void>.delayed(Duration.zero);
      }

      final profile = _profileProvider.profileFor(object);

      if (isLimited && !LimitedRecommendationPolicy.allowsTarget(profile)) {
        excludedLimitedDifficulty++;
        continue;
      }

      final minimumExposure = _exposurePolicy.calculateMinimumExposure(
        bortle: evalContext.bortle,
        brightness: evalContext.brightness,
        profile: profile,
      );
      final recommendedExposure = _exposurePolicy.calculateRecommendedExposure(
        bortle: evalContext.bortle,
        brightness: evalContext.brightness,
        profile: profile,
      );

      final windowResult = _windowCalculator.calculate(
        object: object,
        profile: profile,
        context: evalContext,
        settings: settings,
        session: session,
        referenceTime: refTime,
        minimumExposure: minimumExposure,
        recommendedExposure: recommendedExposure,
      );

      switch (windowResult.exclusion) {
        case ObservationWindowExclusion.noWindow:
          excludedNoWindow++;
          continue;
        case ObservationWindowExclusion.altitude:
          excludedAltitude++;
          continue;
        case ObservationWindowExclusion.azimuth:
          excludedAzimuth++;
          continue;
        case ObservationWindowExclusion.insufficientDuration:
          excludedInsufficientDuration++;
          continue;
        case ObservationWindowExclusion.none:
          break;
      }

      if (!_exposurePolicy.isRecommended(
        bortle: evalContext.bortle,
        brightness: evalContext.brightness,
        profile: profile,
      )) {
        excludedLightPollution++;
        continue;
      }

      final window = windowResult.window!;
      final equipmentFit = equipmentFitResolver?.call(object, window);
      final rotationSpan = trackingMode == TrackingMode.altAz
          ? _fieldRotationSpan(
              object: object,
              context: evalContext,
              window: window,
            )
          : 0.0;
      final assessment = _imagingSuitabilityService.assess(
        profile: profile,
        bortle: _exposurePolicy.resolveBortle(
          bortle: evalContext.bortle,
          brightness: evalContext.brightness,
        ),
        trackingMode: trackingMode,
        equipmentFit: equipmentFit,
        recommendedExposure: recommendedExposure,
        targetAltitude: window.peakAltitude ?? window.currentAltitude,
        moonIllumination: evalContext.moonIllumination,
        moonSeparation: windowResult.moonSeparation,
        cloudCover:
            (window.optimalFeasibleCloudCoverage ?? evalContext.cloudCover)
                .toDouble(),
        fieldRotationSpanDegrees: rotationSpan,
      );
      final evaluationTime =
          window.optimalTime ?? window.peakAltitudeTime ?? session.start;
      var score = _recommendationScore.calculate(
        object: object,
        context: evalContext,
        profile: profile,
        window: window,
        evaluationTime: evaluationTime,
        positionService: _celestialPositionService,
      );
      score *= assessment.scoreMultiplier;

      if (isLimited && profile.imagingDifficulty == ImagingDifficulty.normal) {
        score *= ObservationStatusConfig.limitedNormalDifficultyScoreMultiplier;
      }

      if (score <= 0) continue;

      candidates.add(
        ScoredObservationTarget(
          object: object,
          window: window,
          profile: profile,
          score: score,
          moonSeparation: windowResult.moonSeparation,
          minimumExposure: minimumExposure,
          recommendedExposure: recommendedExposure,
          imagingAssessment: assessment,
        ),
      );
    }

    if (candidates.isEmpty) {
      final siteFeasibility = evalContext.siteSlotFeasibility.values;
      if (siteFeasibility.isNotEmpty &&
          siteFeasibility.every((result) => !result.canObserve)) {
        return _emptyResult(
          session: session,
          context: context,
          referenceTime: refTime,
          exclusionReasons: FeasibilityExclusionMessages.build(
            feasibilityResults: siteFeasibility,
          ),
        );
      }

      return _emptyResult(
        session: session,
        context: context,
        referenceTime: refTime,
        exclusionReasons: RecommendationExclusionMessages.build(
          altitudeExcluded: excludedAltitude,
          azimuthExcluded: excludedAzimuth,
          noWindow: excludedNoWindow,
          lightPollutionExcluded: excludedLightPollution,
          insufficientDuration: excludedInsufficientDuration,
          limitedDifficultyExcluded: excludedLimitedDifficulty,
        ),
      );
    }

    RecommendationCandidateSorter.sort(candidates, settings.priorityMode);

    final allResults = candidates
        .map(
          (candidate) => RecommendationResult(
            object: candidate.object,
            reasons: RecommendationReasonBuilder.build(
              object: candidate.object,
              window: candidate.window,
              moonSeparation: candidate.moonSeparation,
              moonIllumination: evalContext.moonIllumination,
              season: season,
              month: month,
              cloudCoverage:
                  candidate.window.optimalFeasibleCloudCoverage ?? -1,
              windSpeed: candidate.window.optimalFeasibleWindSpeed ?? -1,
            ),
            season: season,
            score: candidate.score,
            moonSeparation: candidate.moonSeparation,
            observationWindow: candidate.window,
            imagingAssessment: candidate.imagingAssessment,
            minimumExposure: candidate.minimumExposure,
            recommendedExposure: candidate.recommendedExposure,
          ),
        )
        .toList();

    final resultsById = {
      for (final result in allResults) result.object.id: result,
    };

    final scheduleResult = _schedulerEngine.buildSchedule(
      SchedulerInput(
        context: evalContext,
        session: session,
        targets: candidates,
        resultsById: resultsById,
        referenceTime: refTime,
      ),
    );

    final scheduleItems = scheduleResult.items
        .where((item) => item.status != ScheduleItemStatus.excluded)
        .toList();

    final recommendations = allResults.take(limit).toList();

    _logRecommendationsDebug(recommendations, candidates);

    return RecommendationBuildResult(
      session: session,
      recommendations: recommendations,
      allRecommendations: allResults,
      scheduleItems: scheduleItems,
      exclusionReasons: const [],
      scheduleResult: scheduleResult,
      scoredTargets: candidates,
    );
  }

  double _fieldRotationSpan({
    required CatalogObject object,
    required ObservationContext context,
    required ObjectObservationWindow window,
  }) {
    final start =
        window.recommendStartTime ??
        window.optimalStartTime ??
        window.peakAltitudeTime;
    final end = window.observationEndTime ?? window.optimalEndTime;
    if (start == null || end == null || !end.isAfter(start)) return 0;

    return FieldOrientationCalculator.fieldRotationSpanDuringWindow(
      latitudeDeg: context.latitude,
      longitudeDeg: context.longitude,
      raHours: CelestialPositionService.parseRaHours(object.ra),
      declinationDeg: CelestialPositionService.parseDecDeg(object.dec),
      windowStart: start,
      windowEnd: end,
    );
  }

  /// 관측 불가 시에도 추천·스케줄을 보여주기 위한 기상 무시 컨텍스트.
  /// 위치·달·Bortle 등 천체/광해 조건은 유지한다.
  ObservationContext _planningContextIgnoringWeather(
    ObservationContext context,
  ) {
    return ObservationContext(
      latitude: context.latitude,
      longitude: context.longitude,
      brightness: context.brightness,
      bortle: context.bortle,
      moonIllumination: context.moonIllumination,
      moonAltitude: context.moonAltitude,
      moonAzimuth: context.moonAzimuth,
      cloudCover: 0,
      observationStart: context.observationStart,
      observationEnd: context.observationEnd,
      currentTime: context.currentTime,
      observationStatus: ObservationStatus.good,
      catalog: context.catalog,
      shootingRecords: context.shootingRecords,
    );
  }

  List<CatalogObject> _filterCatalog(
    List<CatalogObject> catalog,
    RecommendationSettings settings,
  ) {
    return catalog.where((object) {
      if (object.catalog == CatalogType.solar ||
          object.catalog == CatalogType.milky) {
        return false;
      }
      return settings.enabledCatalogs.contains(object.catalog);
    }).toList();
  }

  DateTime _clampReferenceTime(
    DateTime time,
    TonightObservationSession session,
  ) {
    if (time.isBefore(session.start)) return session.start;
    if (time.isAfter(session.end)) return session.start;
    return time;
  }

  RecommendationBuildResult _emptyResult({
    required TonightObservationSession session,
    required ObservationContext context,
    required DateTime referenceTime,
    required List<String> exclusionReasons,
  }) {
    return RecommendationBuildResult(
      session: session,
      recommendations: const [],
      allRecommendations: const [],
      scheduleItems: const [],
      exclusionReasons: exclusionReasons,
      scheduleResult: _schedulerEngine.buildSchedule(
        SchedulerInput(
          context: context,
          session: session,
          targets: const [],
          resultsById: const {},
          referenceTime: referenceTime,
        ),
      ),
      scoredTargets: const [],
    );
  }

  void _logRecommendationsDebug(
    List<RecommendationResult> recommendations,
    List<ScoredObservationTarget> candidates,
  ) {
    if (!kDebugMode || recommendations.isEmpty) return;

    final byId = {
      for (final candidate in candidates) candidate.object.id: candidate,
    };

    for (final recommendation in recommendations.take(4)) {
      final candidate = byId[recommendation.object.id];
      if (candidate == null) continue;

      AppLogger.info(
        'RECOMMEND',
        'Target : ${recommendation.object.displayName}',
      );
      AppLogger.info('RECOMMEND', 'FinalScore : ${candidate.score.round()}');
    }
  }
}

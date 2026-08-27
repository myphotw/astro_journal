import '../../data/models/catalog_object.dart';
import '../../data/models/observation_feasibility_reason.dart';
import '../../data/models/object_imaging_profile.dart';
import '../../data/models/object_observation_window.dart';
import '../../data/models/observation_context.dart';
import '../../data/models/observation_weather.dart';
import '../../data/models/tonight_observation_session.dart';
import '../../core/services/performance_probe.dart';
import '../celestial_position_service.dart';
import '../horizon_visibility_service.dart';
import '../observation_feasibility_policy.dart';
import '../observation_score_service.dart';
import '../recommendation/feasible_slot_continuity.dart';
import '../recommendation/feasible_window_formatter.dart';
import '../recommendation_settings_service.dart';
import '../scoring/moon_score.dart';
import '../scoring/light_pollution_score.dart';
import '../scheduler_engine.dart';

enum ObservationWindowExclusion {
  none,
  noWindow,
  altitude,
  azimuth,
  insufficientDuration,
}

class ObservationWindowCalculation {
  const ObservationWindowCalculation({
    required this.window,
    required this.exclusion,
    required this.moonSeparation,
  });

  final ObjectObservationWindow? window;
  final ObservationWindowExclusion exclusion;
  final double moonSeparation;
}

/// Builds [ObjectObservationWindow] for a target across tonight's session.
class ObservationWindowCalculator {
  const ObservationWindowCalculator(
    this._positionService, {
    MoonScore? moonScore,
    ObservationFeasibilityPolicy? feasibilityPolicy,
    HorizonVisibilityService? horizonVisibilityService,
  }) : _moonScore = moonScore ?? const MoonScore(),
       _feasibilityPolicy =
           feasibilityPolicy ?? const ObservationFeasibilityPolicy(),
       _horizonVisibilityService =
           horizonVisibilityService ?? const HorizonVisibilityService();

  final CelestialPositionService _positionService;
  final MoonScore _moonScore;
  final ObservationFeasibilityPolicy _feasibilityPolicy;
  final HorizonVisibilityService _horizonVisibilityService;

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
    performance?.calls += 1;
    performance?.astrometry.start();
    final latitude = context.latitude;
    final longitude = context.longitude;
    final raH = CelestialPositionService.parseRaHours(object.ra);
    final decD = CelestialPositionService.parseDecDeg(object.dec);

    final moonCoords = _positionService.getMoonEquatorial(referenceTime);
    final moonSeparation = CelestialPositionService.angularSeparationDeg(
      ra1Hours: moonCoords.raHours,
      dec1Deg: moonCoords.decDeg,
      ra2Hours: raH,
      dec2Deg: decD,
    );

    final referenceAltAz = CelestialPositionService.computeAltAz(
      raHours: raH,
      decDeg: decD,
      latDeg: latitude,
      lonDeg: longitude,
      time: referenceTime,
    );

    final trajectory = _positionService.getTrajectory(
      objectId: object.id,
      raHours: raH,
      decDeg: decD,
      latitude: latitude,
      longitude: longitude,
      start: session.start,
      end: session.end,
    );
    performance?.astrometry.stop();

    if (trajectory.points.isEmpty) {
      return ObservationWindowCalculation(
        window: null,
        exclusion: ObservationWindowExclusion.noWindow,
        moonSeparation: moonSeparation,
      );
    }

    performance?.visibility.start();
    final visiblePoints = trajectory.points.where((point) {
      return settings.isAltitudeInRange(point.altitude) &&
          settings.isAzimuthInRange(point.azimuth) &&
          _horizonVisibilityService.isVisible(
            profile: context.horizonProfile,
            azimuth: point.azimuth,
            altitude: point.altitude,
          );
    }).toList();
    performance?.visiblePoints += visiblePoints.length;
    performance?.visibility.stop();

    if (visiblePoints.isEmpty) {
      final anyAlt = trajectory.points.any(
        (point) => settings.isAltitudeInRange(point.altitude),
      );
      return ObservationWindowCalculation(
        window: null,
        exclusion: anyAlt
            ? ObservationWindowExclusion.azimuth
            : ObservationWindowExclusion.altitude,
        moonSeparation: moonSeparation,
      );
    }

    final horizonStart = visiblePoints.first.time;
    final horizonEnd = visiblePoints.last.time;
    final horizonSpanMinutes =
        horizonEnd.difference(horizonStart).inMinutes + 10;

    if (horizonSpanMinutes < minimumExposure.inMinutes) {
      return ObservationWindowCalculation(
        window: null,
        exclusion: ObservationWindowExclusion.insufficientDuration,
        moonSeparation: moonSeparation,
      );
    }

    final peakPoint = visiblePoints.reduce(
      (a, b) => a.altitude >= b.altitude ? a : b,
    );

    final meridianPoint = trajectory.points.reduce(
      (a, b) => a.altitude >= b.altitude ? a : b,
    );

    final siteWindow = context.observationWindow;
    final slotScores = <DateTime, double>{};
    final pointBySlot = <DateTime, CelestialTimePoint>{};
    final lightPollutionScore = const LightPollutionScore().calculate(
      context: context,
      profile: profile,
    );
    var bestScore = -1.0;
    CelestialTimePoint? bestPoint;
    var hadLightPollutionFailure = false;
    var hadWeatherFailure = false;

    performance?.slotScoring.start();
    for (final point in visiblePoints) {
      final slotStart = _alignToSlot(point.time);
      final weather = context.sessionWeather?.weatherAt(slotStart);
      if (weather != null) {
        final feasibility = _feasibilityPolicy.evaluateTargetSlot(
          context: context,
          forecast: weather.toForecastSlot(),
          settings: settings,
          profile: profile,
          altitude: point.altitude,
          azimuth: point.azimuth,
        );
        if (!feasibility.canObserve) {
          if (feasibility.failedConditions.contains(
            ObservationFeasibilityReason.lightPollution,
          )) {
            hadLightPollutionFailure = true;
          }
          if (feasibility.failedConditions.any(_isWeatherReason)) {
            hadWeatherFailure = true;
          }
          continue;
        }
      }

      final targetWeatherScore = sharedCache?.targetWeatherScore(
        context: context,
        evaluationTime: point.time,
        weather: weather,
      );
      final moonCoordinates = sharedCache?.moonCoordinates(
        positionService: _positionService,
        evaluationTime: point.time,
      );
      final score = ObservationScoreService.calculateTargetSlotScore(
        object: object,
        profile: profile,
        context: context,
        evaluationTime: point.time,
        altitude: point.altitude,
        positionService: _positionService,
        weather: weather,
        raHours: raH,
        declinationDeg: decD,
        lightPollutionScore: lightPollutionScore,
        targetWeatherScore: targetWeatherScore,
        moonCoordinates: moonCoordinates,
      );
      slotScores[slotStart] = score;
      pointBySlot.putIfAbsent(slotStart, () => point);

      final inSiteWindow =
          siteWindow == null || siteWindow.containsTime(point.time);
      if (inSiteWindow && score > bestScore) {
        bestScore = score;
        bestPoint = point;
      }
    }
    performance?.scoredSlots += slotScores.length;
    performance?.slotScoring.stop();

    if (bestScore < 0) {
      if (hadLightPollutionFailure && !hadWeatherFailure) {
        return ObservationWindowCalculation(
          window: null,
          exclusion: ObservationWindowExclusion.noWindow,
          moonSeparation: moonSeparation,
        );
      }
      return ObservationWindowCalculation(
        window: null,
        exclusion: hadWeatherFailure
            ? ObservationWindowExclusion.noWindow
            : ObservationWindowExclusion.insufficientDuration,
        moonSeparation: moonSeparation,
      );
    }

    performance?.continuity.start();
    final continuity = FeasibleSlotContinuity.analyzeSorted(
      slotScores.keys.toList(growable: false),
    );
    if (!continuity.hasMinimumContinuousDuration) {
      performance?.continuity.stop();
      return ObservationWindowCalculation(
        window: null,
        exclusion: ObservationWindowExclusion.insufficientDuration,
        moonSeparation: moonSeparation,
      );
    }

    final filteredScores = Map<DateTime, double>.fromEntries(
      continuity.allowedSlots.map((slot) => MapEntry(slot, slotScores[slot]!)),
    );

    if (continuity.longestMinutes < minimumExposure.inMinutes) {
      performance?.continuity.stop();
      return ObservationWindowCalculation(
        window: null,
        exclusion: ObservationWindowExclusion.insufficientDuration,
        moonSeparation: moonSeparation,
      );
    }

    bestScore = -1.0;
    bestPoint = null;
    for (final entry in filteredScores.entries) {
      if (entry.value > bestScore) {
        bestScore = entry.value;
        bestPoint = pointBySlot[entry.key] ?? visiblePoints.first;
      }
    }

    if (bestScore < 0 || bestPoint == null) {
      performance?.continuity.stop();
      return ObservationWindowCalculation(
        window: null,
        exclusion: ObservationWindowExclusion.insufficientDuration,
        moonSeparation: moonSeparation,
      );
    }

    final optimalPoint = bestPoint;
    final feasibleStarts = continuity.allowedSlots;
    final recommendStart = feasibleStarts.first;
    final observationEnd = feasibleStarts.last;
    final totalMinutes = feasibleStarts.length * _slotDuration.inMinutes;
    final remainingVisibleMinutes =
        feasibleStarts.where((slot) => !slot.isBefore(referenceTime)).length *
        _slotDuration.inMinutes;
    var latestStart = observationEnd
        .add(_slotDuration)
        .subtract(recommendedExposure);
    if (latestStart.isBefore(recommendStart)) latestStart = recommendStart;
    performance?.continuity.stop();
    performance?.moonSafety.start();
    final moonSafeMinutes = _calculateMoonSafeMinutes(
      context: context,
      visiblePoints: visiblePoints,
      raHours: raH,
      declinationDeg: decD,
      sharedCache: sharedCache,
    );
    performance?.moonSafety.stop();

    final isCurrentlyVisible =
        referenceTime.isAfter(session.start) &&
        referenceTime.isBefore(session.end) &&
        settings.isAltitudeInRange(referenceAltAz.altitude) &&
        settings.isAzimuthInRange(referenceAltAz.azimuth) &&
        _horizonVisibilityService.isVisible(
          profile: context.horizonProfile,
          azimuth: referenceAltAz.azimuth,
          altitude: referenceAltAz.altitude,
        );

    final feasibleRanges = continuity.allowedRanges;
    final bestRange = FeasibleWindowFormatter.bestScoringRange(
      slotScores: filteredScores,
      focusTime: optimalPoint.time,
      precomputedRanges: feasibleRanges,
    );
    final feasibleSummary = FeasibleWindowFormatter.buildSummary(
      feasibleRanges: feasibleRanges,
      fullWindowStart: recommendStart,
      fullWindowEnd: observationEnd.add(_slotDuration),
    );

    final optimalSlotStart = _alignToSlot(optimalPoint.time);
    final optimalWeather = context.sessionWeather?.weatherAt(optimalSlotStart);

    return ObservationWindowCalculation(
      window: ObjectObservationWindow(
        currentAltitude: referenceAltAz.altitude,
        currentAzimuth: referenceAltAz.azimuth,
        isCurrentlyVisible: isCurrentlyVisible,
        recommendStartTime: recommendStart,
        optimalStartTime: bestRange?.start,
        optimalEndTime: bestRange?.end,
        optimalTime: optimalPoint.time,
        optimalAltitude: optimalPoint.altitude,
        peakAltitude: peakPoint.altitude,
        peakAltitudeTime: peakPoint.time,
        meridianPassTime: meridianPoint.time,
        observationEndTime: observationEnd,
        totalObservableMinutes: totalMinutes,
        remainingVisibleMinutes: remainingVisibleMinutes.clamp(0, totalMinutes),
        latestStartTime: latestStart,
        moonSafeMinutes: moonSafeMinutes,
        bestObservationScore: bestScore.clamp(0, 100),
        slotObservationScores: filteredScores,
        feasibleWindowSummary: feasibleSummary,
        optimalFeasibleCloudCoverage: optimalWeather?.cloudCover,
        optimalFeasibleWindSpeed: optimalWeather?.windSpeed,
      ),
      exclusion: ObservationWindowExclusion.none,
      moonSeparation: moonSeparation,
    );
  }

  int _calculateMoonSafeMinutes({
    required ObservationContext context,
    required List<CelestialTimePoint> visiblePoints,
    required double raHours,
    required double declinationDeg,
    ObservationWindowSharedCache? sharedCache,
  }) {
    const moonThreshold = 60.0;
    var bestRun = 0;
    var currentRun = 0;

    for (final point in visiblePoints) {
      final moon = _moonScore.calculateForCoordinates(
        raHours: raHours,
        decDeg: declinationDeg,
        context: context,
        positionService: _positionService,
        evaluationTime: point.time,
        moonCoordinates: sharedCache?.moonCoordinates(
          positionService: _positionService,
          evaluationTime: point.time,
        ),
      );
      if (moon >= moonThreshold) {
        currentRun += 10;
        if (currentRun > bestRun) bestRun = currentRun;
      } else {
        currentRun = 0;
      }
    }

    return bestRun;
  }

  DateTime _alignToSlot(DateTime time) {
    final remainder = time.minute % SchedulerEngine.slotDuration.inMinutes;
    return DateTime(
      time.year,
      time.month,
      time.day,
      time.hour,
      time.minute - remainder,
    );
  }

  static const _slotDuration = SchedulerEngine.slotDuration;

  bool _isWeatherReason(ObservationFeasibilityReason reason) {
    return switch (reason) {
      ObservationFeasibilityReason.cloudTooHigh ||
      ObservationFeasibilityReason.rainProbability ||
      ObservationFeasibilityReason.visibilityTooLow ||
      ObservationFeasibilityReason.windTooStrong => true,
      _ => false,
    };
  }
}

/// Aggregated Debug-only timing for one recommendation pass.
class ObservationWindowPerformance {
  final Stopwatch astrometry = Stopwatch();
  final Stopwatch visibility = Stopwatch();
  final Stopwatch slotScoring = Stopwatch();
  final Stopwatch continuity = Stopwatch();
  final Stopwatch moonSafety = Stopwatch();
  int calls = 0;
  int visiblePoints = 0;
  int scoredSlots = 0;

  void report(String state) {
    final detail =
        '$state calls=$calls visible_points=$visiblePoints scored_slots=$scoredSlots';
    PerformanceProbe.record(
      'recommendation.window.astrometry',
      astrometry.elapsed,
      state: detail,
    );
    PerformanceProbe.record(
      'recommendation.window.visibility',
      visibility.elapsed,
      state: detail,
    );
    PerformanceProbe.record(
      'recommendation.window.slot_scoring',
      slotScoring.elapsed,
      state: detail,
    );
    PerformanceProbe.record(
      'recommendation.window.continuity',
      continuity.elapsed,
      state: detail,
    );
    PerformanceProbe.record(
      'recommendation.window.moon_safety',
      moonSafety.elapsed,
      state: detail,
    );
  }
}

class ObservationWindowSharedCache {
  final Map<DateTime, double> _targetWeatherScores = {};
  final Map<DateTime, EquatorialCoordinates> _moonCoordinates = {};

  EquatorialCoordinates moonCoordinates({
    required CelestialPositionService positionService,
    required DateTime evaluationTime,
  }) {
    return _moonCoordinates.putIfAbsent(
      evaluationTime,
      () => positionService.getMoonEquatorial(evaluationTime),
    );
  }

  double targetWeatherScore({
    required ObservationContext context,
    required DateTime evaluationTime,
    required ObservationWeather? weather,
  }) {
    return _targetWeatherScores.putIfAbsent(
      evaluationTime,
      () => ObservationScoreService.calculateTargetWeatherScore(
        context: context,
        evaluationTime: evaluationTime,
        weather: weather,
      ),
    );
  }
}

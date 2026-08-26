import '../../data/models/catalog_object.dart';
import '../../data/models/observation_feasibility_reason.dart';
import '../../data/models/object_imaging_profile.dart';
import '../../data/models/object_observation_window.dart';
import '../../data/models/observation_context.dart';
import '../../data/models/tonight_observation_session.dart';
import '../celestial_position_service.dart';
import '../horizon_visibility_service.dart';
import '../observation_feasibility_policy.dart';
import '../observation_score_service.dart';
import '../recommendation/feasible_slot_continuity.dart';
import '../recommendation/feasible_window_formatter.dart';
import '../recommendation_settings_service.dart';
import '../scoring/moon_score.dart';
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
  }) {
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

    if (trajectory.points.isEmpty) {
      return ObservationWindowCalculation(
        window: null,
        exclusion: ObservationWindowExclusion.noWindow,
        moonSeparation: moonSeparation,
      );
    }

    final visiblePoints = trajectory.points.where((point) {
      return settings.isAltitudeInRange(point.altitude) &&
          settings.isAzimuthInRange(point.azimuth) &&
          _horizonVisibilityService.isVisible(
            profile: context.horizonProfile,
            azimuth: point.azimuth,
            altitude: point.altitude,
          );
    }).toList();

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
    var bestScore = -1.0;
    CelestialTimePoint? bestPoint;
    var hadLightPollutionFailure = false;
    var hadWeatherFailure = false;

    for (final point in visiblePoints) {
      final slotStart = _alignToSlot(point.time);
      final weatherObs = context.sessionWeather?.weatherAt(slotStart);
      if (weatherObs != null) {
        final feasibility = _feasibilityPolicy.evaluateTargetSlot(
          context: context,
          forecast: weatherObs.toForecastSlot(),
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

      final weather = context.sessionWeather?.weatherAt(slotStart);
      final score = ObservationScoreService.calculateTargetSlotScore(
        object: object,
        profile: profile,
        context: context,
        evaluationTime: point.time,
        altitude: point.altitude,
        positionService: _positionService,
        weather: weather,
      );
      slotScores[slotStart] = score;

      final inSiteWindow =
          siteWindow == null || siteWindow.containsTime(point.time);
      if (inSiteWindow && score > bestScore) {
        bestScore = score;
        bestPoint = point;
      }
    }

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

    if (!FeasibleSlotContinuity.hasMinimumContinuousDuration(slotScores.keys)) {
      return ObservationWindowCalculation(
        window: null,
        exclusion: ObservationWindowExclusion.insufficientDuration,
        moonSeparation: moonSeparation,
      );
    }

    final allowedSlots = FeasibleSlotContinuity.slotsInRangesAtLeast(
      slotScores.keys,
    ).toSet();
    final filteredScores = Map<DateTime, double>.fromEntries(
      slotScores.entries.where((entry) => allowedSlots.contains(entry.key)),
    );

    if (FeasibleSlotContinuity.longestContiguousMinutes(filteredScores.keys) <
        minimumExposure.inMinutes) {
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
        bestPoint = visiblePoints.firstWhere(
          (point) => _alignToSlot(point.time) == entry.key,
          orElse: () => visiblePoints.first,
        );
      }
    }

    if (bestScore < 0 || bestPoint == null) {
      return ObservationWindowCalculation(
        window: null,
        exclusion: ObservationWindowExclusion.insufficientDuration,
        moonSeparation: moonSeparation,
      );
    }

    final optimalPoint = bestPoint;
    final feasibleStarts = filteredScores.keys.toList()..sort();
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
    final moonSafeMinutes = _calculateMoonSafeMinutes(
      object: object,
      context: context,
      visiblePoints: visiblePoints,
    );

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

    final feasibleRanges = FeasibleWindowFormatter.mergeSlotTimes(
      filteredScores.keys,
    );
    final bestRange = FeasibleWindowFormatter.bestScoringRange(
      slotScores: filteredScores,
      focusTime: optimalPoint.time,
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
    required CatalogObject object,
    required ObservationContext context,
    required List<CelestialTimePoint> visiblePoints,
  }) {
    const moonThreshold = 60.0;
    var bestRun = 0;
    var currentRun = 0;

    for (final point in visiblePoints) {
      final moon = _moonScore.calculate(
        object: object,
        context: context.copyWith(currentTime: point.time),
        positionService: _positionService,
        evaluationTime: point.time,
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

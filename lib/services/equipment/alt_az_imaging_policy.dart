import 'dart:math' as math;

import '../../data/models/catalog_object.dart';
import '../../data/models/imaging_suitability_assessment.dart';
import '../../data/models/object_observation_window.dart';
import '../../data/models/observation_context.dart';
import '../celestial_position_service.dart';
import '../scheduler_engine.dart';
import 'field_orientation_calculator.dart';

class AltAzImagingPlan {
  const AltAzImagingPlan({
    required this.recommendedDailyExposure,
    required this.dailyDurationLimitedByFieldRotation,
    required this.fieldRotationSpanDegrees,
    this.preferredHaWindow,
  });

  final Duration recommendedDailyExposure;
  final bool dailyDurationLimitedByFieldRotation;
  final double fieldRotationSpanDegrees;
  final TargetPreferredHaWindow? preferredHaWindow;
}

/// Derives an Alt-Az daily block and a repeatable target/site HA window from
/// the geometry slots already produced by ObservationWindowCalculator.
class AltAzImagingPolicy {
  const AltAzImagingPolicy();

  static const double maxRecommendedFieldRotationDegrees = 20;
  static const int minimumPracticalDailyMinutes = 30;
  static const double schedulerHaBonusWeight = 0.08;
  static const double maxHaMatchDistanceHours = 6;
  static const double _haObservationScoreWeight = 0.05;

  static double haMatchQuality({
    required TargetPreferredHaWindow preferred,
    required double longitudeDeg,
    required DateTime candidateCenter,
    required double raHours,
  }) {
    final candidateHa = FieldOrientationCalculator.signedHourAngleHours(
      longitudeDeg: longitudeDeg,
      time: candidateCenter,
      raHours: raHours,
    );
    final distance = FieldOrientationCalculator.hourAngleDistanceHours(
      candidateHa,
      preferred.centerHours,
    );
    return (100 * (1 - distance / maxHaMatchDistanceHours))
        .clamp(0.0, 100.0)
        .toDouble();
  }

  AltAzImagingPlan calculate({
    required CatalogObject object,
    required ObservationContext context,
    required ObjectObservationWindow window,
    required TrackingMode trackingMode,
    required Duration minimumExposure,
    required Duration recommendedTotalExposure,
  }) {
    if (trackingMode == TrackingMode.eq) {
      return AltAzImagingPlan(
        recommendedDailyExposure: recommendedTotalExposure,
        dailyDurationLimitedByFieldRotation: false,
        fieldRotationSpanDegrees: 0,
      );
    }

    final slotMinutes = SchedulerEngine.slotDuration.inMinutes;
    final totalSlots = math
        .max(
          1,
          (recommendedTotalExposure.inMinutes / slotMinutes).ceil(),
        )
        .toInt();
    final minimumSlots = math
        .min(
          totalSlots,
          math.max(
            (minimumExposure.inMinutes / slotMinutes).ceil(),
            (minimumPracticalDailyMinutes / slotMinutes).ceil(),
          ),
        )
        .toInt();

    final geometricStarts = _sortedUnique(
      window.geometricSlotStarts.isEmpty
          ? window.slotObservationScores.keys
          : window.geometricSlotStarts,
    );
    final feasibleStarts = _sortedUnique(window.slotObservationScores.keys);
    final geometricRuns = _contiguousRuns(geometricStarts);
    final feasibleRuns = _contiguousRuns(feasibleStarts);
    final maxFeasibleSlots = _longestRun(feasibleRuns);

    if (geometricRuns.isEmpty || maxFeasibleSlots == 0) {
      return const AltAzImagingPlan(
        recommendedDailyExposure: Duration.zero,
        dailyDurationLimitedByFieldRotation: false,
        fieldRotationSpanDegrees: 0,
      );
    }

    final raHours = CelestialPositionService.parseRaHours(object.ra);
    final declinationDeg = CelestialPositionService.parseDecDeg(object.dec);
    final rotationCache = <DateTime, double>{};
    final altitudeCache = <DateTime, double>{};

    final geometricSelection = _selectBlock(
      runs: geometricRuns,
      totalSlots: totalSlots,
      minimumSlots: minimumSlots,
      raHours: raHours,
      declinationDeg: declinationDeg,
      context: context,
      observationScores: window.slotObservationScores,
      rotationCache: rotationCache,
      altitudeCache: altitudeCache,
    );
    final feasibleSelection = _selectBlock(
      runs: feasibleRuns,
      totalSlots: totalSlots,
      minimumSlots: minimumSlots,
      raHours: raHours,
      declinationDeg: declinationDeg,
      context: context,
      observationScores: window.slotObservationScores,
      rotationCache: rotationCache,
      altitudeCache: altitudeCache,
    );
    final preferredBaseline =
        geometricSelection.safe ?? geometricSelection.fallback;
    final dailyBaseline = feasibleSelection.safe ?? feasibleSelection.fallback;
    if (preferredBaseline == null || dailyBaseline == null) {
      final dailySlots = math.min(totalSlots, maxFeasibleSlots).toInt();
      return AltAzImagingPlan(
        recommendedDailyExposure: Duration(
          minutes: dailySlots * slotMinutes,
        ),
        dailyDurationLimitedByFieldRotation: false,
        fieldRotationSpanDegrees: 0,
      );
    }

    final dailySlots = math
        .min(
          dailyBaseline.slotCount,
          math.min(totalSlots, maxFeasibleSlots),
        )
        .toInt();
    final dailyDuration = Duration(minutes: dailySlots * slotMinutes);
    final dailyEnd = dailyBaseline.start.add(dailyDuration);
    final dailyRotationSpan = _rotationSpan(
      start: dailyBaseline.start,
      end: dailyEnd,
      raHours: raHours,
      declinationDeg: declinationDeg,
      context: context,
      rotationCache: rotationCache,
    );
    final safeFeasible = feasibleSelection.safe;
    final rotationLimited = safeFeasible != null &&
        safeFeasible.slotCount <
            math.min(totalSlots, maxFeasibleSlots).toInt();

    final preferredDuration = Duration(
      minutes: preferredBaseline.slotCount * slotMinutes,
    );
    final preferredEnd = preferredBaseline.start.add(preferredDuration);
    final preferredCenter = preferredBaseline.start.add(
      Duration(minutes: preferredDuration.inMinutes ~/ 2),
    );
    final preferredHaWindow = TargetPreferredHaWindow(
      startHours: FieldOrientationCalculator.signedHourAngleHours(
        longitudeDeg: context.longitude,
        time: preferredBaseline.start,
        raHours: raHours,
      ),
      endHours: FieldOrientationCalculator.signedHourAngleHours(
        longitudeDeg: context.longitude,
        time: preferredEnd,
        raHours: raHours,
      ),
      centerHours: FieldOrientationCalculator.signedHourAngleHours(
        longitudeDeg: context.longitude,
        time: preferredCenter,
        raHours: raHours,
      ),
      durationMinutes: preferredDuration.inMinutes,
      todayStartTime: preferredBaseline.start,
      todayEndTime: preferredEnd,
    );

    return AltAzImagingPlan(
      recommendedDailyExposure: dailyDuration,
      dailyDurationLimitedByFieldRotation: rotationLimited,
      fieldRotationSpanDegrees: dailyRotationSpan,
      preferredHaWindow: preferredHaWindow,
    );
  }

  ({_BlockCandidate? safe, _BlockCandidate? fallback}) _selectBlock({
    required List<List<DateTime>> runs,
    required int totalSlots,
    required int minimumSlots,
    required double raHours,
    required double declinationDeg,
    required ObservationContext context,
    required Map<DateTime, double> observationScores,
    required Map<DateTime, double> rotationCache,
    required Map<DateTime, double> altitudeCache,
  }) {
    _BlockCandidate? bestSafe;
    _BlockCandidate? bestFallback;
    for (final run in runs) {
      for (var startIndex = 0; startIndex < run.length; startIndex++) {
        final available = math
            .min(run.length - startIndex, totalSlots)
            .toInt();
        if (available < minimumSlots) continue;

        for (var count = minimumSlots; count <= available; count++) {
          final candidate = _candidate(
            run: run,
            startIndex: startIndex,
            slotCount: count,
            raHours: raHours,
            declinationDeg: declinationDeg,
            context: context,
            observationScores: observationScores,
            rotationCache: rotationCache,
            altitudeCache: altitudeCache,
          );
          if (count == minimumSlots &&
              (bestFallback == null ||
                  candidate.score > bestFallback.score)) {
            bestFallback = candidate;
          }
          if (candidate.rotationSpanDegrees >
              maxRecommendedFieldRotationDegrees) {
            break;
          }
          if (bestSafe == null ||
              candidate.slotCount > bestSafe.slotCount ||
              (candidate.slotCount == bestSafe.slotCount &&
                  candidate.score > bestSafe.score)) {
            bestSafe = candidate;
          }
        }
      }
    }
    return (safe: bestSafe, fallback: bestFallback);
  }

  _BlockCandidate _candidate({
    required List<DateTime> run,
    required int startIndex,
    required int slotCount,
    required double raHours,
    required double declinationDeg,
    required ObservationContext context,
    required Map<DateTime, double> observationScores,
    required Map<DateTime, double> rotationCache,
    required Map<DateTime, double> altitudeCache,
  }) {
    final start = run[startIndex];
    final end = start.add(
      Duration(minutes: slotCount * SchedulerEngine.slotDuration.inMinutes),
    );
    final rotationSpan = _rotationSpan(
      start: start,
      end: end,
      raHours: raHours,
      declinationDeg: declinationDeg,
      context: context,
      rotationCache: rotationCache,
    );

    var altitudeTotal = 0.0;
    var observationTotal = 0.0;
    var observationCount = 0;
    for (var index = 0; index < slotCount; index++) {
      final time = run[startIndex + index];
      altitudeTotal += altitudeCache.putIfAbsent(
        time,
        () => CelestialPositionService.computeAltAz(
          raHours: raHours,
          decDeg: declinationDeg,
          latDeg: context.latitude,
          lonDeg: context.longitude,
          time: time,
        ).altitude,
      );
      final observation = observationScores[time];
      if (observation != null) {
        observationTotal += observation;
        observationCount++;
      }
    }
    final averageAltitude = altitudeTotal / slotCount;
    final altitudeScore = ((averageAltitude - 15) / 60 * 100)
        .clamp(0.0, 100.0)
        .toDouble();
    final rotationScore = (100 -
            rotationSpan / maxRecommendedFieldRotationDegrees * 100)
        .clamp(0.0, 100.0)
        .toDouble();
    final observationScore = observationCount == 0
        ? 50.0
        : observationTotal / observationCount;
    final score = altitudeScore * 0.70 +
        rotationScore * 0.25 +
        observationScore * _haObservationScoreWeight;

    return _BlockCandidate(
      start: start,
      slotCount: slotCount,
      rotationSpanDegrees: rotationSpan,
      score: score,
    );
  }

  double _rotationSpan({
    required DateTime start,
    required DateTime end,
    required double raHours,
    required double declinationDeg,
    required ObservationContext context,
    required Map<DateTime, double> rotationCache,
  }) {
    final angles = <double>[];
    var cursor = start;
    while (!cursor.isAfter(end)) {
      angles.add(
        rotationCache.putIfAbsent(
          cursor,
          () {
            final hourAngle = FieldOrientationCalculator.hourAngleDegrees(
              longitudeDeg: context.longitude,
              time: cursor,
              raHours: raHours,
            );
            return FieldOrientationCalculator.parallacticAngleDegrees(
              latitudeDeg: context.latitude,
              hourAngleDeg: hourAngle,
              declinationDeg: declinationDeg,
            );
          },
        ),
      );
      cursor = cursor.add(SchedulerEngine.slotDuration);
    }
    return FieldOrientationCalculator.unwrappedRotationSpanDegrees(angles);
  }

  List<DateTime> _sortedUnique(Iterable<DateTime> values) {
    final result = values.toSet().toList()..sort();
    return result;
  }

  List<List<DateTime>> _contiguousRuns(List<DateTime> starts) {
    if (starts.isEmpty) return const [];
    final runs = <List<DateTime>>[];
    var current = <DateTime>[starts.first];
    for (final start in starts.skip(1)) {
      if (start.difference(current.last) == SchedulerEngine.slotDuration) {
        current.add(start);
      } else {
        runs.add(current);
        current = [start];
      }
    }
    runs.add(current);
    return runs;
  }

  int _longestRun(List<List<DateTime>> runs) => runs.fold<int>(
        0,
        (longest, run) => math.max(longest, run.length).toInt(),
      );
}

class _BlockCandidate {
  const _BlockCandidate({
    required this.start,
    required this.slotCount,
    required this.rotationSpanDegrees,
    required this.score,
  });

  final DateTime start;
  final int slotCount;
  final double rotationSpanDegrees;
  final double score;
}

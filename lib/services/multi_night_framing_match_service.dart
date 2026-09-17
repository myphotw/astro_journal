import 'dart:math' as math;

import 'package:uuid/uuid.dart';

import '../data/models/catalog_object.dart';
import '../data/models/equipment.dart';
import '../data/models/multi_night_framing_reference.dart';
import '../data/models/observation_site.dart';
import '../data/models/site_horizon_profile.dart';
import 'celestial_position_service.dart';
import 'equipment/field_orientation_calculator.dart';
import 'horizon_visibility_service.dart';
import 'observation_score_service.dart';

typedef MultiNightDarkWindow = ({DateTime nightStart, DateTime nightEnd});
typedef MultiNightDarkWindowResolver =
    MultiNightDarkWindow Function(DateTime date);

enum MultiNightFramingUnavailableCause {
  noMatch,
  skyTooBright,
  dawn,
  altitude,
  obstructed,
  elapsed,
}

class MultiNightFramingMatchResult {
  const MultiNightFramingMatchResult({
    required this.reference,
    required this.site,
    required this.equipment,
    required this.isAvailable,
    required this.hourAngleDeg,
    required this.parallacticAngleDeg,
    required this.parallacticAngleDifferenceDeg,
    required this.altitudeDeg,
    required this.azimuthDeg,
    this.recommendedAt,
    this.framingMatchAt,
    this.rangeStart,
    this.rangeEnd,
    this.darkStart,
    this.darkEnd,
    this.unavailableCause,
    this.unavailableReason,
  });

  final MultiNightFramingReference reference;
  final ObservationSite site;
  final Equipment equipment;
  final bool isAvailable;
  final DateTime? recommendedAt;
  final DateTime? framingMatchAt;
  final DateTime? rangeStart;
  final DateTime? rangeEnd;
  final DateTime? darkStart;
  final DateTime? darkEnd;
  final double hourAngleDeg;
  final double parallacticAngleDeg;
  final double parallacticAngleDifferenceDeg;
  final double altitudeDeg;
  final double azimuthDeg;
  final MultiNightFramingUnavailableCause? unavailableCause;
  final String? unavailableReason;

  String get framingDifferenceLabel {
    final difference = parallacticAngleDifferenceDeg;
    if (difference <= 1) return '매우 작음';
    if (difference <= 2.5) return '작음';
    return '큼';
  }
}

class MultiNightFramingMatchService {
  const MultiNightFramingMatchService({
    HorizonVisibilityService horizonVisibility =
        const HorizonVisibilityService(),
    this.allowedParallacticAngleDifferenceDeg = 2.5,
    MultiNightDarkWindowResolver? darkWindowResolver,
  }) : _horizonVisibility = horizonVisibility,
       _darkWindowResolver = darkWindowResolver;

  final HorizonVisibilityService _horizonVisibility;
  final MultiNightDarkWindowResolver? _darkWindowResolver;

  /// Single source of truth for the first release's acceptable PA mismatch.
  final double allowedParallacticAngleDifferenceDeg;
  static const double maximumHourAngleMissDeg = 0.5;
  static const int maximumRangeSearchMinutes = 180;

  MultiNightFramingReference buildReference({
    required CatalogObject object,
    required DateTime capturedAt,
    required ObservationSite site,
    required Equipment equipment,
    String? id,
    MultiNightFramingReference? existing,
  }) {
    final raHours = CelestialPositionService.parseRaHours(object.ra);
    final decDeg = CelestialPositionService.parseDecDeg(object.dec);
    if (raHours == null || decDeg == null) {
      throw ArgumentError('Catalog object has invalid RA/Dec: ${object.id}');
    }
    final signedHa = signedHourAngleDegrees(
      longitudeDeg: site.longitude,
      time: capturedAt,
      raHours: raHours,
    );
    final pa = signedAngleDegrees(
      FieldOrientationCalculator.parallacticAngleDegrees(
        latitudeDeg: site.latitude,
        hourAngleDeg: signedHa,
        declinationDeg: decDeg,
      ),
    );
    final now = DateTime.now().toUtc();
    return MultiNightFramingReference(
      id: existing?.id ?? id ?? const Uuid().v4(),
      catalogObjectId: object.effectivePrimaryId,
      referenceCapturedAt: capturedAt,
      siteId: site.id,
      equipmentId: equipment.id,
      referenceHourAngleDeg: signedHa,
      referenceParallacticAngleDeg: pa,
      referenceBranch: branchForHourAngle(signedHa),
      revision: existing?.revision ?? 0,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
  }

  MultiNightFramingMatchResult findToday({
    required CatalogObject object,
    required MultiNightFramingReference reference,
    required ObservationSite site,
    required Equipment equipment,
    DateTime? today,
    DateTime? now,
    List<MultiNightDarkWindow>? darkWindows,
  }) {
    final currentTime = now ?? DateTime.now();
    final date = today ?? currentTime;
    final dayStart = DateTime(date.year, date.month, date.day);
    final shouldExcludePast = today == null || now != null;
    final searchStart = shouldExcludePast
        ? currentTime.add(const Duration(seconds: 1))
        : dayStart;
    final searchEnd = shouldExcludePast
        ? dayStart.add(const Duration(days: 2))
        : dayStart.add(const Duration(days: 1));
    final raHours = CelestialPositionService.parseRaHours(object.ra);
    final decDeg = CelestialPositionService.parseDecDeg(object.dec);
    if (raHours == null || decDeg == null) {
      return _unavailable(
        reference: reference,
        site: site,
        equipment: equipment,
        reason: '대상의 좌표를 확인할 수 없어 같은 구도를 계산할 수 없습니다.',
      );
    }

    DateTime? best;
    var bestDistance = double.infinity;
    for (
      var cursor = searchStart;
      !cursor.isAfter(searchEnd);
      cursor = cursor.add(const Duration(minutes: 1))
    ) {
      final ha = signedHourAngleDegrees(
        longitudeDeg: site.longitude,
        time: cursor,
        raHours: raHours,
      );
      if (branchForHourAngle(ha) != reference.referenceBranch) continue;
      final distance = circularAngleDifferenceDegrees(
        ha,
        reference.referenceHourAngleDeg,
      );
      if (distance < bestDistance) {
        bestDistance = distance;
        best = cursor;
      }
    }

    if (best == null) {
      return _unavailable(
        reference: reference,
        site: site,
        equipment: equipment,
        reason: '오늘은 이전 촬영과 같은 구도를 재현하기 어렵습니다.',
      );
    }

    var bestTime = best;
    final coarse = bestTime;
    for (
      var cursor = coarse.subtract(const Duration(minutes: 1));
      !cursor.isAfter(coarse.add(const Duration(minutes: 1)));
      cursor = cursor.add(const Duration(seconds: 1))
    ) {
      if (cursor.isBefore(searchStart) || cursor.isAfter(searchEnd)) continue;
      final ha = signedHourAngleDegrees(
        longitudeDeg: site.longitude,
        time: cursor,
        raHours: raHours,
      );
      if (branchForHourAngle(ha) != reference.referenceBranch) continue;
      final distance = circularAngleDifferenceDegrees(
        ha,
        reference.referenceHourAngleDeg,
      );
      if (distance < bestDistance) {
        bestDistance = distance;
        bestTime = cursor;
      }
    }

    final exactSample = _sample(
      time: bestTime,
      raHours: raHours,
      decDeg: decDeg,
      site: site,
      reference: reference,
    );
    if (exactSample.branch != reference.referenceBranch ||
        bestDistance > maximumHourAngleMissDeg) {
      return MultiNightFramingMatchResult(
        reference: reference,
        site: site,
        equipment: equipment,
        isAvailable: false,
        framingMatchAt: bestTime,
        hourAngleDeg: exactSample.hourAngleDeg,
        parallacticAngleDeg: exactSample.parallacticAngleDeg,
        parallacticAngleDifferenceDeg: exactSample.paDifferenceDeg,
        altitudeDeg: exactSample.altitudeDeg,
        azimuthDeg: exactSample.azimuthDeg,
        unavailableCause: MultiNightFramingUnavailableCause.noMatch,
        unavailableReason: '오늘은 이전 촬영과 같은 구도를 재현하기 어렵습니다.',
      );
    }

    final framingRange = _allowedFramingRange(
      center: bestTime,
      dayStart: searchStart,
      dayEnd: searchEnd,
      raHours: raHours,
      decDeg: decDeg,
      site: site,
      reference: reference,
    );
    if (framingRange == null) {
      return _unavailableFromSample(
        reference: reference,
        site: site,
        equipment: equipment,
        sample: exactSample,
        framingMatchAt: bestTime,
        cause: MultiNightFramingUnavailableCause.noMatch,
        reason: '오늘은 이전 촬영과 같은 구도를 재현하기 어렵습니다.',
      );
    }

    final effectiveDarkWindows = darkWindows ?? _darkWindowsForDay(dayStart);
    final candidates = <({DateTime time, _FramingSample sample})>[];
    for (
      var cursor = framingRange.$1;
      !cursor.isAfter(framingRange.$2);
      cursor = cursor.add(const Duration(minutes: 1))
    ) {
      candidates.add((
        time: cursor,
        sample: _sample(
          time: cursor,
          raHours: raHours,
          decDeg: decDeg,
          site: site,
          reference: reference,
        ),
      ));
    }

    final darkCandidates = candidates
        .where((candidate) => _isDark(candidate.time, effectiveDarkWindows))
        .toList();
    var availableCandidates = darkCandidates
        .where((candidate) => candidate.sample.visible)
        .toList();
    if (shouldExcludePast) {
      availableCandidates = availableCandidates
          .where((candidate) => !candidate.time.isBefore(currentTime))
          .toList();
    }

    if (availableCandidates.isEmpty) {
      if (darkCandidates.isEmpty) {
        final nextDarkStart = _nextDarkStart(bestTime, effectiveDarkWindows);
        final previousDarkEnd = _previousDarkEnd(
          bestTime,
          effectiveDarkWindows,
        );
        final isAfterDawn =
            previousDarkEnd != null &&
            bestTime.isAfter(previousDarkEnd) &&
            bestTime.hour < 12;
        return _unavailableFromSample(
          reference: reference,
          site: site,
          equipment: equipment,
          sample: exactSample,
          framingMatchAt: bestTime,
          darkStart: nextDarkStart,
          cause: isAfterDawn
              ? MultiNightFramingUnavailableCause.dawn
              : MultiNightFramingUnavailableCause.skyTooBright,
          reason: isAfterDawn
              ? '같은 구도가 되는 시간에는 하늘이 밝아지기 시작합니다.'
              : '같은 구도가 되는 시간에는 아직 하늘이 밝습니다.',
        );
      }

      final visibleBeforeNow = darkCandidates.any(
        (candidate) => candidate.sample.visible,
      );
      if (shouldExcludePast && visibleBeforeNow) {
        return _unavailableFromSample(
          reference: reference,
          site: site,
          equipment: equipment,
          sample: exactSample,
          framingMatchAt: bestTime,
          cause: MultiNightFramingUnavailableCause.elapsed,
          reason: '오늘은 촬영 가능한 시간이 지났습니다.',
        );
      }

      final diagnostic = _nearestCandidate(darkCandidates, bestTime).sample;
      final altitudeUnavailable = !diagnostic.altitudeVisible;
      return _unavailableFromSample(
        reference: reference,
        site: site,
        equipment: equipment,
        sample: diagnostic,
        framingMatchAt: bestTime,
        cause: altitudeUnavailable
            ? MultiNightFramingUnavailableCause.altitude
            : MultiNightFramingUnavailableCause.obstructed,
        reason: altitudeUnavailable
            ? '대상이 아직 너무 낮거나 관측 고도 범위를 벗어납니다.'
            : '선택한 관측지에서 가려지는 방향입니다.',
      );
    }

    final selected = _nearestCandidate(availableCandidates, bestTime);
    final selectedIndex = availableCandidates.indexOf(selected);
    var rangeStart = selected.time;
    var rangeEnd = selected.time;
    for (var index = selectedIndex - 1; index >= 0; index--) {
      final candidate = availableCandidates[index];
      if (rangeStart.difference(candidate.time) >
          const Duration(minutes: 1, seconds: 1)) {
        break;
      }
      rangeStart = candidate.time;
    }
    for (
      var index = selectedIndex + 1;
      index < availableCandidates.length;
      index++
    ) {
      final candidate = availableCandidates[index];
      if (candidate.time.difference(rangeEnd) >
          const Duration(minutes: 1, seconds: 1)) {
        break;
      }
      rangeEnd = candidate.time;
    }
    final selectedDarkWindow = effectiveDarkWindows.firstWhere(
      (window) => _isDark(selected.time, [window]),
    );
    return MultiNightFramingMatchResult(
      reference: reference,
      site: site,
      equipment: equipment,
      isAvailable: true,
      recommendedAt: selected.time,
      framingMatchAt: bestTime,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      darkStart: selectedDarkWindow.nightStart,
      darkEnd: selectedDarkWindow.nightEnd,
      hourAngleDeg: selected.sample.hourAngleDeg,
      parallacticAngleDeg: selected.sample.parallacticAngleDeg,
      parallacticAngleDifferenceDeg: selected.sample.paDifferenceDeg,
      altitudeDeg: selected.sample.altitudeDeg,
      azimuthDeg: selected.sample.azimuthDeg,
    );
  }

  (DateTime, DateTime)? _allowedFramingRange({
    required DateTime center,
    required DateTime dayStart,
    required DateTime dayEnd,
    required double raHours,
    required double decDeg,
    required ObservationSite site,
    required MultiNightFramingReference reference,
  }) {
    bool allowed(DateTime time) {
      if (time.isBefore(dayStart) || time.isAfter(dayEnd)) return false;
      final sample = _sample(
        time: time,
        raHours: raHours,
        decDeg: decDeg,
        site: site,
        reference: reference,
      );
      return sample.branch == reference.referenceBranch &&
          sample.paDifferenceDeg <= allowedParallacticAngleDifferenceDeg;
    }

    if (!allowed(center)) return null;
    var rangeStart = center;
    var rangeEnd = center;
    for (var offset = 1; offset <= maximumRangeSearchMinutes; offset++) {
      final candidate = center.subtract(Duration(minutes: offset));
      if (!allowed(candidate)) break;
      rangeStart = candidate;
    }
    for (var offset = 1; offset <= maximumRangeSearchMinutes; offset++) {
      final candidate = center.add(Duration(minutes: offset));
      if (!allowed(candidate)) break;
      rangeEnd = candidate;
    }
    return (rangeStart, rangeEnd);
  }

  List<MultiNightDarkWindow> _darkWindowsForDay(DateTime dayStart) {
    final resolver =
        _darkWindowResolver ?? ObservationScoreService.estimatedNightWindow;
    final previous = resolver(dayStart.subtract(const Duration(days: 1)));
    final current = resolver(dayStart);
    final next = resolver(dayStart.add(const Duration(days: 1)));
    return [previous, current, next];
  }

  bool _isDark(DateTime time, List<MultiNightDarkWindow> windows) =>
      windows.any(
        (window) =>
            !time.isBefore(window.nightStart) && !time.isAfter(window.nightEnd),
      );

  DateTime? _nextDarkStart(DateTime time, List<MultiNightDarkWindow> windows) {
    final starts =
        windows
            .map((window) => window.nightStart)
            .where((start) => start.isAfter(time))
            .toList()
          ..sort();
    return starts.isEmpty ? null : starts.first;
  }

  DateTime? _previousDarkEnd(
    DateTime time,
    List<MultiNightDarkWindow> windows,
  ) {
    final ends =
        windows
            .map((window) => window.nightEnd)
            .where((end) => end.isBefore(time))
            .toList()
          ..sort();
    return ends.isEmpty ? null : ends.last;
  }

  ({DateTime time, _FramingSample sample}) _nearestCandidate(
    List<({DateTime time, _FramingSample sample})> candidates,
    DateTime target,
  ) {
    var nearest = candidates.first;
    var nearestDistance = nearest.time.difference(target).abs();
    for (final candidate in candidates.skip(1)) {
      final distance = candidate.time.difference(target).abs();
      if (distance < nearestDistance) {
        nearest = candidate;
        nearestDistance = distance;
      }
    }
    return nearest;
  }

  _FramingSample _sample({
    required DateTime time,
    required double raHours,
    required double decDeg,
    required ObservationSite site,
    required MultiNightFramingReference reference,
  }) {
    final ha = signedHourAngleDegrees(
      longitudeDeg: site.longitude,
      time: time,
      raHours: raHours,
    );
    final pa = signedAngleDegrees(
      FieldOrientationCalculator.parallacticAngleDegrees(
        latitudeDeg: site.latitude,
        hourAngleDeg: ha,
        declinationDeg: decDeg,
      ),
    );
    final altAz = CelestialPositionService.computeAltAz(
      raHours: raHours,
      decDeg: decDeg,
      latDeg: site.latitude,
      lonDeg: site.longitude,
      time: time,
    );
    final profileVisible = _horizonVisibility.isVisible(
      profile: SiteHorizonProfile(
        points: site.horizonPoints,
        blockedRanges: site.blockedAzimuthRanges,
      ),
      azimuth: altAz.azimuth,
      altitude: altAz.altitude,
    );
    final altitudeVisible =
        altAz.altitude >= site.defaultMinAltitude &&
        (site.defaultMaxAltitude == null ||
            altAz.altitude <= site.defaultMaxAltitude!);
    return _FramingSample(
      hourAngleDeg: ha,
      parallacticAngleDeg: pa,
      paDifferenceDeg: circularAngleDifferenceDegrees(
        pa,
        reference.referenceParallacticAngleDeg,
      ),
      altitudeDeg: altAz.altitude,
      azimuthDeg: altAz.azimuth,
      branch: branchForHourAngle(ha),
      altitudeVisible: altitudeVisible,
      visible: profileVisible && altitudeVisible,
    );
  }

  MultiNightFramingMatchResult _unavailableFromSample({
    required MultiNightFramingReference reference,
    required ObservationSite site,
    required Equipment equipment,
    required _FramingSample sample,
    required DateTime framingMatchAt,
    required MultiNightFramingUnavailableCause cause,
    required String reason,
    DateTime? darkStart,
  }) => MultiNightFramingMatchResult(
    reference: reference,
    site: site,
    equipment: equipment,
    isAvailable: false,
    framingMatchAt: framingMatchAt,
    darkStart: darkStart,
    hourAngleDeg: sample.hourAngleDeg,
    parallacticAngleDeg: sample.parallacticAngleDeg,
    parallacticAngleDifferenceDeg: sample.paDifferenceDeg,
    altitudeDeg: sample.altitudeDeg,
    azimuthDeg: sample.azimuthDeg,
    unavailableCause: cause,
    unavailableReason: reason,
  );

  MultiNightFramingMatchResult _unavailable({
    required MultiNightFramingReference reference,
    required ObservationSite site,
    required Equipment equipment,
    required String reason,
  }) => MultiNightFramingMatchResult(
    reference: reference,
    site: site,
    equipment: equipment,
    isAvailable: false,
    hourAngleDeg: double.nan,
    parallacticAngleDeg: double.nan,
    parallacticAngleDifferenceDeg: double.nan,
    altitudeDeg: double.nan,
    azimuthDeg: double.nan,
    unavailableReason: reason,
  );

  static double signedHourAngleDegrees({
    required double longitudeDeg,
    required DateTime time,
    required double raHours,
  }) => signedAngleDegrees(
    FieldOrientationCalculator.hourAngleDegrees(
      longitudeDeg: longitudeDeg,
      time: time,
      raHours: raHours,
    ),
  );

  static MultiNightFramingBranch branchForHourAngle(double signedHaDeg) =>
      signedHaDeg < 0
      ? MultiNightFramingBranch.rising
      : MultiNightFramingBranch.setting;

  static double signedAngleDegrees(double value) {
    var normalized = value % 360;
    if (normalized > 180) normalized -= 360;
    if (normalized <= -180) normalized += 360;
    return normalized;
  }

  static double circularAngleDifferenceDegrees(double first, double second) {
    final raw = (first - second).abs() % 360;
    return math.min(raw, 360 - raw);
  }
}

class _FramingSample {
  const _FramingSample({
    required this.hourAngleDeg,
    required this.parallacticAngleDeg,
    required this.paDifferenceDeg,
    required this.altitudeDeg,
    required this.azimuthDeg,
    required this.branch,
    required this.altitudeVisible,
    required this.visible,
  });

  final double hourAngleDeg;
  final double parallacticAngleDeg;
  final double paDifferenceDeg;
  final double altitudeDeg;
  final double azimuthDeg;
  final MultiNightFramingBranch branch;
  final bool altitudeVisible;
  final bool visible;
}

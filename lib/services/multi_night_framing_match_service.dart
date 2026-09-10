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
    this.rangeStart,
    this.rangeEnd,
    this.unavailableReason,
  });

  final MultiNightFramingReference reference;
  final ObservationSite site;
  final Equipment equipment;
  final bool isAvailable;
  final DateTime? recommendedAt;
  final DateTime? rangeStart;
  final DateTime? rangeEnd;
  final double hourAngleDeg;
  final double parallacticAngleDeg;
  final double parallacticAngleDifferenceDeg;
  final double altitudeDeg;
  final double azimuthDeg;
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
  }) : _horizonVisibility = horizonVisibility;

  final HorizonVisibilityService _horizonVisibility;

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
  }) {
    final date = today ?? DateTime.now();
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    final raHours = CelestialPositionService.parseRaHours(object.ra);
    final decDeg = CelestialPositionService.parseDecDeg(object.dec);

    DateTime? best;
    var bestDistance = double.infinity;
    for (
      var cursor = start;
      !cursor.isAfter(end);
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
      if (cursor.isBefore(start) || cursor.isAfter(end)) continue;
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

    final sample = _sample(
      time: bestTime,
      raHours: raHours,
      decDeg: decDeg,
      site: site,
      reference: reference,
    );
    if (!sample.visible ||
        sample.branch != reference.referenceBranch ||
        bestDistance > maximumHourAngleMissDeg) {
      return MultiNightFramingMatchResult(
        reference: reference,
        site: site,
        equipment: equipment,
        isAvailable: false,
        recommendedAt: bestTime,
        hourAngleDeg: sample.hourAngleDeg,
        parallacticAngleDeg: sample.parallacticAngleDeg,
        parallacticAngleDifferenceDeg: sample.paDifferenceDeg,
        altitudeDeg: sample.altitudeDeg,
        azimuthDeg: sample.azimuthDeg,
        unavailableReason: '오늘은 이전 촬영과 같은 구도를 재현하기 어렵습니다.',
      );
    }

    final range = _allowedRange(
      center: bestTime,
      dayStart: start,
      dayEnd: end,
      raHours: raHours,
      decDeg: decDeg,
      site: site,
      reference: reference,
    );
    return MultiNightFramingMatchResult(
      reference: reference,
      site: site,
      equipment: equipment,
      isAvailable: true,
      recommendedAt: bestTime,
      rangeStart: range?.$1,
      rangeEnd: range?.$2,
      hourAngleDeg: sample.hourAngleDeg,
      parallacticAngleDeg: sample.parallacticAngleDeg,
      parallacticAngleDifferenceDeg: sample.paDifferenceDeg,
      altitudeDeg: sample.altitudeDeg,
      azimuthDeg: sample.azimuthDeg,
    );
  }

  (DateTime, DateTime)? _allowedRange({
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
      return sample.visible &&
          sample.branch == reference.referenceBranch &&
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
      visible: profileVisible && altitudeVisible,
    );
  }

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
    required this.visible,
  });

  final double hourAngleDeg;
  final double parallacticAngleDeg;
  final double paDifferenceDeg;
  final double altitudeDeg;
  final double azimuthDeg;
  final MultiNightFramingBranch branch;
  final bool visible;
}

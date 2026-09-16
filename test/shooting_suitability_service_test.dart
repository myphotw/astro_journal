import 'package:astro_journal/core/constants/angular_size_class.dart';
import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/core/constants/equipment_kind.dart';
import 'package:astro_journal/core/constants/equipment_purpose.dart';
import 'package:astro_journal/core/constants/imaging_difficulty.dart';
import 'package:astro_journal/core/constants/object_type.dart';
import 'package:astro_journal/core/constants/surface_brightness_class.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/equipment.dart';
import 'package:astro_journal/data/models/imaging_suitability_assessment.dart';
import 'package:astro_journal/data/models/multi_night_framing_reference.dart';
import 'package:astro_journal/data/models/object_imaging_profile.dart';
import 'package:astro_journal/data/models/object_observation_window.dart';
import 'package:astro_journal/data/models/observation_site.dart';
import 'package:astro_journal/data/models/scored_observation_target.dart';
import 'package:astro_journal/data/models/shooting_suitability.dart';
import 'package:astro_journal/services/multi_night_framing_match_service.dart';
import 'package:astro_journal/services/shooting_suitability_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = ShootingSuitabilityService();
  final observationStart = DateTime(2026, 9, 16, 21);
  final observationEnd = DateTime(2026, 9, 17, 1);
  final optimalStart = DateTime(2026, 9, 16, 22);
  final optimalEnd = DateTime(2026, 9, 16, 23);

  ScoredObservationTarget target({
    bool extremelyTiny = false,
    Duration minimumExposure = const Duration(minutes: 20),
  }) => ScoredObservationTarget(
    object: const CatalogObject(
      id: 'ngc7009',
      number: 7009,
      catalog: CatalogType.ngc,
      name: 'NGC 7009',
      type: '행성상성운',
      constellation: 'Aquarius',
      ra: '21h 04m',
      dec: '-11° 22m',
      magnitude: '8.0',
    ),
    window: ObjectObservationWindow(
      currentAltitude: 40,
      currentAzimuth: 180,
      isCurrentlyVisible: true,
      recommendStartTime: observationStart,
      observationEndTime: observationEnd,
      optimalStartTime: optimalStart,
      optimalEndTime: optimalEnd,
      optimalTime: optimalStart.add(const Duration(minutes: 30)),
      totalObservableMinutes: 240,
    ),
    profile: ObjectImagingProfile(
      objectType: ObjectType.planetaryNebula,
      imagingDifficulty: ImagingDifficulty.normal,
      surfaceBrightnessClass: SurfaceBrightnessClass.bright,
      angularSizeClass: AngularSizeClass.verySmall,
      baseExposureMinutes: 30,
      minimumRecommendedBortle: 8,
      recommendedBortle: 5,
      supportsNarrowband: true,
      recommendedFilters: const ['OIII'],
    ),
    score: 70,
    moonSeparation: 90,
    minimumExposure: minimumExposure,
    recommendedExposure: const Duration(minutes: 60),
    imagingAssessment: ImagingSuitabilityAssessment(
      quality: ExpectedResultQuality.trace,
      filterMode: FilterMode.on,
      trackingMode: TrackingMode.altAz,
      suitabilityScore: 20,
      scoreMultiplier: 0.2,
      reason: 'test',
      hasReliableSurfaceBrightness: true,
      isExtremelyTiny: extremelyTiny,
      equipmentId: 's30',
    ),
  );

  MultiNightFramingMatchResult framingMatch({required bool available}) {
    final now = DateTime(2026, 1, 1);
    final reference = MultiNightFramingReference(
      id: 'ref',
      catalogObjectId: 'ngc7009',
      referenceCapturedAt: now,
      siteId: 'site',
      equipmentId: 's30',
      referenceHourAngleDeg: 0,
      referenceParallacticAngleDeg: 0,
      referenceBranch: MultiNightFramingBranch.setting,
      revision: 0,
      createdAt: now,
      updatedAt: now,
    );
    final site = ObservationSite(
      id: 'site',
      name: '집',
      latitude: 37.5,
      longitude: 127,
      createdAt: now,
      updatedAt: now,
    );
    const equipment = Equipment(
      id: 's30',
      name: 'S30 Pro',
      kind: EquipmentKind.smartTelescope,
      purpose: EquipmentPurpose.imaging,
    );
    return MultiNightFramingMatchResult(
      reference: reference,
      site: site,
      equipment: equipment,
      isAvailable: available,
      rangeStart: available ? DateTime(2026, 9, 16, 22, 5) : null,
      rangeEnd: available ? DateTime(2026, 9, 16, 23, 20) : null,
      hourAngleDeg: 0,
      parallacticAngleDeg: 0,
      parallacticAngleDifferenceDeg: 0,
      altitudeDeg: 45,
      azimuthDeg: 180,
      unavailableReason: available ? null : 'same framing unavailable',
    );
  }

  test('extremely tiny equipment result is a hard recommendation gate', () {
    final result = service.evaluate(target: target(extremelyTiny: true));

    expect(result.eligible, isFalse);
    expect(result.rejection, ShootingSuitabilityRejection.equipmentTooSmall);
  });

  test('automatic window is observation intersect optimal window', () {
    final result = service.evaluate(target: target());

    expect(result.automaticEligible, isTrue);
    expect(result.recommendedWindow!.start, optimalStart);
    expect(result.recommendedWindow!.end, optimalEnd);
  });

  test('framing reference constrains the full automatic window', () {
    final result = service.evaluate(
      target: target(),
      hasFramingReference: true,
      framingMatch: framingMatch(available: true),
    );

    expect(result.automaticEligible, isTrue);
    expect(result.recommendedWindow!.start, DateTime(2026, 9, 16, 22, 5));
    expect(result.recommendedWindow!.end, optimalEnd);
  });

  test('unavailable framing reference is a hard gate', () {
    final result = service.evaluate(
      target: target(),
      hasFramingReference: true,
      framingMatch: framingMatch(available: false),
    );

    expect(result.eligible, isFalse);
    expect(result.rejection, ShootingSuitabilityRejection.framingUnavailable);
  });

  test('short optimal overlap remains manually eligible but not automatic', () {
    final result = service.evaluate(
      target: target(minimumExposure: const Duration(minutes: 90)),
    );

    expect(result.eligible, isTrue);
    expect(result.automaticEligible, isFalse);
    expect(result.rejection, ShootingSuitabilityRejection.insufficientDuration);
  });
}

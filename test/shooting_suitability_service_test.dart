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
import 'package:astro_journal/data/models/shooting_time_window.dart';
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
    Duration recommendedExposure = const Duration(minutes: 60),
    DateTime? observationStartTime,
    DateTime? observationEndTime,
    DateTime? optimalStartTime,
    DateTime? optimalEndTime,
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
      recommendStartTime: observationStartTime ?? observationStart,
      observationEndTime: observationEndTime ?? observationEnd,
      optimalStartTime: optimalStartTime ?? optimalStart,
      optimalEndTime: optimalEndTime ?? optimalEnd,
      optimalTime: (optimalStartTime ?? optimalStart).add(
        const Duration(minutes: 30),
      ),
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
    recommendedExposure: recommendedExposure,
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

  MultiNightFramingMatchResult framingMatch({
    required bool available,
    DateTime? rangeStart,
    DateTime? rangeEnd,
  }) {
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
      rangeStart:
          available ? rangeStart ?? DateTime(2026, 9, 16, 22, 5) : null,
      rangeEnd: available ? rangeEnd ?? DateTime(2026, 9, 16, 23, 20) : null,
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

  test('informational evaluation preserves extremely tiny target details', () {
    final result = service.evaluate(
      target: target(extremelyTiny: true),
      enforceMeaningfulEquipmentResult: false,
    );

    expect(result.eligible, isTrue);
    expect(result.hasUsableWindow, isTrue);
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

  test('manual search proposes a usable sub-window instead of full range', () {
    final m2 = target(
      minimumExposure: const Duration(minutes: 30),
      observationStartTime: DateTime(2026, 9, 16, 23, 20),
      observationEndTime: DateTime(2026, 9, 17, 1, 20),
      optimalStartTime: DateTime(2026, 9, 16, 23, 20),
      optimalEndTime: DateTime(2026, 9, 17, 1, 20),
    );
    final suitability = service.evaluate(target: m2);
    final proposal = service.proposeManualWindow(
      target: m2,
      suitability: suitability,
      searchWindow: ShootingTimeWindow(
        start: DateTime(2026, 9, 16, 23, 30),
        end: DateTime(2026, 9, 17, 5),
      ),
    );

    expect(proposal, isNotNull);
    final proposed = proposal!;
    expect(proposed.searchWindow.duration, const Duration(minutes: 330));
    expect(proposed.usableWindow.start, DateTime(2026, 9, 16, 23, 30));
    expect(proposed.usableWindow.end, DateTime(2026, 9, 17, 1, 20));
    expect(proposed.proposedDuration, const Duration(minutes: 60));
    expect(proposed.proposedWindow.start, DateTime(2026, 9, 16, 23, 30));
    expect(proposed.proposedWindow.end, DateTime(2026, 9, 17, 0, 30));
  });

  test('multi-night 17 minute same-framing window remains a manual candidate', () {
    final multiNightTarget = target(
      minimumExposure: const Duration(minutes: 30),
      observationStartTime: DateTime(2026, 9, 17, 4, 20),
      observationEndTime: DateTime(2026, 9, 17, 5),
      optimalStartTime: DateTime(2026, 9, 17, 4, 30),
      optimalEndTime: DateTime(2026, 9, 17, 5),
    );
    final suitability = service.evaluate(
      target: multiNightTarget,
      hasFramingReference: true,
      framingMatch: framingMatch(
        available: true,
        rangeStart: DateTime(2026, 9, 17, 4, 35),
        rangeEnd: DateTime(2026, 9, 17, 4, 52),
      ),
    );
    final proposal = service.proposeManualWindow(
      target: multiNightTarget,
      suitability: suitability,
      searchWindow: ShootingTimeWindow(
        start: DateTime(2026, 9, 17, 4),
        end: DateTime(2026, 9, 17, 5),
      ),
    );

    expect(suitability.automaticEligible, isFalse);
    expect(suitability.manualMultiNightEligible, isTrue);
    expect(proposal, isNotNull);
    final proposed = proposal!;
    expect(proposed.proposedWindow.start, DateTime(2026, 9, 17, 4, 35));
    expect(proposed.proposedWindow.end, DateTime(2026, 9, 17, 4, 52));
    expect(proposed.proposedDuration, const Duration(minutes: 17));
    expect(proposed.framingMatched, isTrue);
    expect(proposed.isBelowMinimumDuration, isTrue);
    expect(proposed.isMultiNightAccumulationOpportunity, isTrue);
  });

  test('general 17 minute window remains excluded from manual candidates', () {
    final generalTarget = target(
      minimumExposure: const Duration(minutes: 30),
      observationStartTime: DateTime(2026, 9, 17, 4, 35),
      observationEndTime: DateTime(2026, 9, 17, 4, 52),
      optimalStartTime: DateTime(2026, 9, 17, 4, 35),
      optimalEndTime: DateTime(2026, 9, 17, 4, 52),
    );
    final suitability = service.evaluate(target: generalTarget);
    final proposal = service.proposeManualWindow(
      target: generalTarget,
      suitability: suitability,
      searchWindow: ShootingTimeWindow(
        start: DateTime(2026, 9, 17, 4),
        end: DateTime(2026, 9, 17, 5),
      ),
    );

    expect(suitability.automaticEligible, isFalse);
    expect(suitability.manualMultiNightEligible, isFalse);
    expect(proposal, isNull);
  });
}

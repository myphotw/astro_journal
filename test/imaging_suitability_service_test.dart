import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/core/constants/equipment_kind.dart';
import 'package:astro_journal/core/constants/equipment_purpose.dart';
import 'package:astro_journal/core/constants/object_type.dart';
import 'package:astro_journal/core/constants/surface_brightness_class.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/equipment.dart';
import 'package:astro_journal/data/models/imaging_suitability_assessment.dart';
import 'package:astro_journal/services/equipment/equipment_recommendation_service.dart';
import 'package:astro_journal/services/imaging_suitability_service.dart';
import 'package:astro_journal/services/object_imaging_profile_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const profileProvider = ObjectImagingProfileProvider();
  const equipmentService = EquipmentRecommendationService();
  const suitabilityService = ImagingSuitabilityService();

  const s30 = Equipment(
    id: 's30',
    name: 'Seestar S30 Pro',
    kind: EquipmentKind.smartTelescope,
    purpose: EquipmentPurpose.imaging,
    focalLengthMm: 160,
    fovWidthDegrees: 2.24,
    fovHeightDegrees: 3.99,
  );

  CatalogObject object({
    required String id,
    required ObjectType type,
    required String magnitude,
    String? angularSize,
  }) {
    return CatalogObject(
      id: id,
      number: 1,
      catalog: CatalogType.ngc,
      name: id,
      type: type.label,
      objectType: type.label,
      constellation: 'Test',
      ra: '19h 44m',
      dec: "-14°48'",
      magnitude: magnitude,
      angularSize: angularSize,
    );
  }

  ImagingEquipmentFit fitFor(CatalogObject target) {
    final recommendation = equipmentService.recommendForObject(
      object: target,
      equipment: const [s30],
    );
    final best = recommendation.imaging.single;
    return ImagingEquipmentFit(
      score: best.score,
      screenFillPercent: best.screenFillPercent,
      equipmentId: best.equipment.id,
      equipmentName: best.equipment.name,
      framingRecommendation: best.framingRecommendation,
      supportsMosaic: best.equipment.supportsMosaic,
    );
  }

  group('realistic imaging suitability', () {
    final barnardsGalaxy = object(
      id: 'NGC6822',
      type: ObjectType.galaxy,
      magnitude: '10.05',
      angularSize: "17.38' × 16.75'",
    );

    test('NGC 6822 at Bortle 8 on S30 Alt-Az stays low quality', () {
      final profile = profileProvider.profileFor(barnardsGalaxy);
      final result = suitabilityService.assess(
        profile: profile,
        bortle: 8,
        trackingMode: TrackingMode.altAz,
        equipmentFit: fitFor(barnardsGalaxy),
        recommendedExposure: const Duration(minutes: 90),
        targetAltitude: 70,
        fieldRotationSpanDegrees: 35,
      );

      expect(profile.surfaceBrightnessClass, SurfaceBrightnessClass.extremeDim);
      expect(profile.estimatedSurfaceBrightness, greaterThan(24.5));
      expect(result.filterMode, FilterMode.off);
      expect(result.mosaicMode, MosaicMode.off);
      expect(result.quality, ExpectedResultQuality.trace);
      expect(result.suitabilityScore, lessThan(30));
      expect(result.scoreMultiplier, lessThan(0.4));
    });

    test('NGC 6822 EQ improves tracking only, not urban contrast', () {
      final profile = profileProvider.profileFor(barnardsGalaxy);
      final fit = fitFor(barnardsGalaxy);
      final altAz = suitabilityService.assess(
        profile: profile,
        bortle: 8,
        trackingMode: TrackingMode.altAz,
        equipmentFit: fit,
        recommendedExposure: const Duration(minutes: 90),
        targetAltitude: 70,
        fieldRotationSpanDegrees: 35,
      );
      final eq = suitabilityService.assess(
        profile: profile,
        bortle: 8,
        trackingMode: TrackingMode.eq,
        equipmentFit: fit,
        recommendedExposure: const Duration(minutes: 90),
        targetAltitude: 70,
      );

      expect(eq.scoreMultiplier, greaterThan(altAz.scoreMultiplier));
      expect(eq.quality.level, lessThanOrEqualTo(2));
      expect(eq.filterMode, FilterMode.off);
    });

    test('bright emission nebula benefits from Filter ON in Bortle 8', () {
      final nebula = object(
        id: 'NGC7000',
        type: ObjectType.emissionNebula,
        magnitude: '-',
        angularSize: "120' × 100'",
      );
      final result = suitabilityService.assess(
        profile: profileProvider.profileFor(nebula),
        bortle: 8,
        trackingMode: TrackingMode.altAz,
        equipmentFit: fitFor(nebula),
        recommendedExposure: const Duration(minutes: 60),
        targetAltitude: 50,
      );
      final barnardResult = suitabilityService.assess(
        profile: profileProvider.profileFor(barnardsGalaxy),
        bortle: 8,
        trackingMode: TrackingMode.altAz,
        equipmentFit: fitFor(barnardsGalaxy),
        recommendedExposure: const Duration(minutes: 90),
        targetAltitude: 70,
        fieldRotationSpanDegrees: 35,
      );

      expect(result.filterMode, FilterMode.on);
      expect(result.quality.level, greaterThan(barnardResult.quality.level));
      expect(
        result.scoreMultiplier,
        greaterThan(barnardResult.scoreMultiplier),
      );
    });

    test('representative galaxy improves at dark site with S30 EQ', () {
      final galaxy = object(
        id: 'M31',
        type: ObjectType.galaxy,
        magnitude: '3.4',
        angularSize: "190' × 60'",
      );
      final profile = profileProvider.profileFor(galaxy);
      final fit = fitFor(galaxy);
      final darkEq = suitabilityService.assess(
        profile: profile,
        bortle: 3,
        trackingMode: TrackingMode.eq,
        equipmentFit: fit,
        recommendedExposure: const Duration(minutes: 90),
        targetAltitude: 60,
      );
      final urbanAltAz = suitabilityService.assess(
        profile: profile,
        bortle: 8,
        trackingMode: TrackingMode.altAz,
        equipmentFit: fit,
        recommendedExposure: const Duration(minutes: 90),
        targetAltitude: 70,
        fieldRotationSpanDegrees: 30,
      );

      expect(darkEq.filterMode, FilterMode.off);
      expect(darkEq.quality.level, greaterThan(urbanAltAz.quality.level));
      expect(darkEq.scoreMultiplier, greaterThan(urbanAltAz.scoreMultiplier));
    });

    test('target far too small for S30 is downrated despite visibility', () {
      final tiny = object(
        id: 'TINY',
        type: ObjectType.planetaryNebula,
        magnitude: '8.0',
        angularSize: "0.5'",
      );
      final fit = fitFor(tiny);
      final result = suitabilityService.assess(
        profile: profileProvider.profileFor(tiny),
        bortle: 5,
        trackingMode: TrackingMode.eq,
        equipmentFit: fit,
        recommendedExposure: const Duration(minutes: 45),
      );

      expect(fit.score, lessThan(30));
      expect(result.quality.level, lessThanOrEqualTo(3));
    });

    test('missing magnitude and angular size uses conservative fallback', () {
      final incomplete = object(
        id: 'UNKNOWN',
        type: ObjectType.other,
        magnitude: '-',
      );
      final profile = profileProvider.profileFor(incomplete);
      final result = suitabilityService.assess(
        profile: profile,
        bortle: 5,
        trackingMode: TrackingMode.altAz,
      );

      expect(profile.estimatedSurfaceBrightness, isNull);
      expect(result.hasReliableSurfaceBrightness, isFalse);
      expect(result.quality.level, lessThanOrEqualTo(2));
    });
  });
}

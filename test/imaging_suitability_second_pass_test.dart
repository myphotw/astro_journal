import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/core/constants/equipment_kind.dart';
import 'package:astro_journal/core/constants/equipment_purpose.dart';
import 'package:astro_journal/core/constants/object_type.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/equipment.dart';
import 'package:astro_journal/data/models/fov_box.dart';
import 'package:astro_journal/data/models/imaging_suitability_assessment.dart';
import 'package:astro_journal/services/equipment/equipment_recommendation_service.dart';
import 'package:astro_journal/services/exposure_policy.dart';
import 'package:astro_journal/services/imaging_suitability_service.dart';
import 'package:astro_journal/services/object_imaging_profile_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const profileProvider = ObjectImagingProfileProvider();
  const equipmentService = EquipmentRecommendationService();
  const suitabilityService = ImagingSuitabilityService();
  const exposurePolicy = ExposurePolicy();

  const s30 = Equipment(
    id: 's30',
    name: 'Seestar S30 Pro',
    kind: EquipmentKind.smartTelescope,
    purpose: EquipmentPurpose.imaging,
    focalLengthMm: 160,
    fovWidthDegrees: 2.24,
    fovHeightDegrees: 3.99,
  );
  const singleFrameOnly = Equipment(
    id: 'single-frame',
    name: 'Single frame telescope',
    kind: EquipmentKind.reflector,
    purpose: EquipmentPurpose.imaging,
    focalLengthMm: 400,
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
      ra: '5h 35m',
      dec: '-5° 23\'',
      magnitude: magnitude,
      angularSize: angularSize,
    );
  }

  ImagingEquipmentFit fitFor(
    CatalogObject target, {
    Equipment equipment = s30,
  }) {
    final best = equipmentService
        .recommendForObject(object: target, equipment: [equipment])
        .imaging
        .single;
    return ImagingEquipmentFit(
      score: best.score,
      screenFillPercent: best.screenFillPercent,
      equipmentId: best.equipment.id,
      equipmentName: best.equipment.name,
      framingRecommendation: best.framingRecommendation,
      supportsMosaic: best.equipment.supportsMosaic,
    );
  }

  ImagingSuitabilityAssessment assess(
    CatalogObject target, {
    required int bortle,
    TrackingMode tracking = TrackingMode.eq,
    Equipment equipment = s30,
  }) {
    return suitabilityService.assess(
      profile: profileProvider.profileFor(target),
      bortle: bortle,
      trackingMode: tracking,
      equipmentFit: fitFor(target, equipment: equipment),
      recommendedExposure: const Duration(minutes: 60),
      targetAltitude: 50,
    );
  }

  group('second-pass real-world regression scenarios', () {
    final ngc6822 = object(
      id: 'NGC6822',
      type: ObjectType.galaxy,
      magnitude: '10.05',
      angularSize: "17.38' × 16.75'",
    );
    final m1 = object(
      id: 'M1',
      type: ObjectType.supernovaRemnant,
      magnitude: '8.4',
      angularSize: "6' × 4'",
    );

    test('NGC6822 dark sky improves score without hiding its hard limit', () {
      final urban = assess(ngc6822, bortle: 8, tracking: TrackingMode.altAz);
      final dark = assess(ngc6822, bortle: 3, tracking: TrackingMode.eq);

      expect(urban.filterMode, FilterMode.off);
      expect(urban.mosaicMode, MosaicMode.off);
      expect(urban.quality.level, lessThanOrEqualTo(2));
      expect(urban.suitabilityScore, lessThan(30));
      expect(dark.filterMode, FilterMode.off);
      expect(dark.mosaicMode, MosaicMode.off);
      expect(dark.suitabilityScore, greaterThan(urban.suitabilityScore));
      expect(dark.quality.level, lessThanOrEqualTo(2));
    });

    test('M1 filter mitigates pollution without reversing Bortle order', () {
      final urban = assess(m1, bortle: 8);
      final dark = assess(m1, bortle: 3);

      expect(urban.filterMode, FilterMode.on);
      expect(dark.filterMode, FilterMode.on);
      expect(
        dark.suitabilityScore,
        greaterThanOrEqualTo(urban.suitabilityScore),
      );
      expect(dark.scoreMultiplier, greaterThanOrEqualTo(urban.scoreMultiplier));
    });

    for (final target in [
      object(
        id: 'IC4663',
        type: ObjectType.planetaryNebula,
        magnitude: '11.7',
        angularSize: "0.22' × 0.20'",
      ),
      object(
        id: 'NGC2022',
        type: ObjectType.planetaryNebula,
        magnitude: '11.6',
        angularSize: "0.32' × 0.28'",
      ),
    ]) {
      test('${target.id} remains tiny, non-mosaic, and low quality', () {
        final fit = fitFor(target);
        final result = assess(target, bortle: 5);

        expect(fit.screenFillPercent, lessThanOrEqualTo(1));
        expect(result.mosaicMode, MosaicMode.off);
        expect(result.quality, ExpectedResultQuality.trace);
      });
    }

    test('M42 keeps Filter ON and strong suitability with real framing', () {
      final m42 = object(
        id: 'M42',
        type: ObjectType.emissionNebula,
        magnitude: '4.0',
        angularSize: "85' × 60'",
      );
      final result = assess(m42, bortle: 8);

      expect(result.filterMode, FilterMode.on);
      expect(result.mosaicMode, MosaicMode.off);
      expect(result.quality.level, greaterThanOrEqualTo(4));
    });

    test('M31 has aligned high quality and recommendation eligibility', () {
      final m31 = object(
        id: 'M31',
        type: ObjectType.galaxy,
        magnitude: '3.44',
        angularSize: "177.83' × 69.66'",
      );
      final profile = profileProvider.profileFor(m31);
      final result = assess(m31, bortle: 8);

      expect(result.filterMode, FilterMode.off);
      expect(result.mosaicMode, MosaicMode.off);
      expect(result.quality.level, greaterThanOrEqualTo(4));
      expect(exposurePolicy.isRecommended(bortle: 8, profile: profile), isTrue);
    });

    test('oversized target enables mosaic and relaxes framing penalty', () {
      final oversized = object(
        id: 'LARGE',
        type: ObjectType.emissionNebula,
        magnitude: '5.0',
        angularSize: "420' × 300'",
      );
      final mosaicFit = fitFor(oversized);
      final mosaic = assess(oversized, bortle: 5);
      final noMosaicFit = fitFor(oversized, equipment: singleFrameOnly);
      final noMosaic = assess(oversized, bortle: 5, equipment: singleFrameOnly);

      expect(
        mosaicFit.framingRecommendation,
        FramingRecommendation.mosaicRequired,
      );
      expect(mosaic.mosaicMode, MosaicMode.on);
      expect(
        noMosaicFit.framingRecommendation,
        FramingRecommendation.mosaicRequired,
      );
      expect(noMosaic.mosaicMode, MosaicMode.off);
      expect(mosaicFit.score, greaterThan(noMosaicFit.score));
      expect(mosaic.quality.level, greaterThan(noMosaic.quality.level));
    });

    test('mosaic does not override a faint target and polluted sky', () {
      final faintOversized = object(
        id: 'FAINT-LARGE',
        type: ObjectType.galaxy,
        magnitude: '12.0',
        angularSize: "420' × 300'",
      );
      final result = assess(faintOversized, bortle: 8);

      expect(result.mosaicMode, MosaicMode.on);
      expect(result.quality.level, lessThanOrEqualTo(2));
      expect(result.suitabilityScore, lessThan(40));
    });

    test('missing magnitude and size cannot produce Q4 or Q5', () {
      final unknown = object(
        id: 'UNKNOWN',
        type: ObjectType.emissionNebula,
        magnitude: '-',
      );
      final result = suitabilityService.assess(
        profile: profileProvider.profileFor(unknown),
        bortle: 3,
        trackingMode: TrackingMode.eq,
      );

      expect(result.hasReliableSurfaceBrightness, isFalse);
      expect(result.quality.level, lessThanOrEqualTo(2));
    });

    test('well-framed cluster stays Filter OFF and Mosaic OFF', () {
      final cluster = object(
        id: 'CLUSTER',
        type: ObjectType.openCluster,
        magnitude: '5.0',
        angularSize: "100' × 70'",
      );
      final fit = fitFor(cluster);
      final result = assess(cluster, bortle: 5);

      expect(fit.screenFillPercent, inInclusiveRange(30, 100));
      expect(result.filterMode, FilterMode.off);
      expect(result.mosaicMode, MosaicMode.off);
      expect(fit.score, greaterThanOrEqualTo(55));
    });
  });

  group('Bortle monotonicity', () {
    final targets = <CatalogObject>[
      object(
        id: 'GALAXY',
        type: ObjectType.galaxy,
        magnitude: '8.0',
        angularSize: "20' × 12'",
      ),
      object(
        id: 'EMISSION',
        type: ObjectType.emissionNebula,
        magnitude: '5.0',
        angularSize: "60' × 40'",
      ),
      object(
        id: 'SNR',
        type: ObjectType.supernovaRemnant,
        magnitude: '8.0',
        angularSize: "30' × 20'",
      ),
      object(
        id: 'CLUSTER',
        type: ObjectType.openCluster,
        magnitude: '5.0',
        angularSize: "30' × 20'",
      ),
    ];

    for (final target in targets) {
      test('${target.objectType} keeps B3 >= B5 >= B8', () {
        final profile = profileProvider.profileFor(target);
        const fit = ImagingEquipmentFit(
          score: 80,
          screenFillPercent: 70,
          framingRecommendation: FramingRecommendation.good,
          supportsMosaic: true,
        );
        final scores = [3, 5, 8]
            .map(
              (bortle) => suitabilityService
                  .assess(
                    profile: profile,
                    bortle: bortle,
                    trackingMode: TrackingMode.eq,
                    equipmentFit: fit,
                  )
                  .suitabilityScore,
            )
            .toList();

        expect(scores[0], greaterThanOrEqualTo(scores[1]));
        expect(scores[1], greaterThanOrEqualTo(scores[2]));
      });
    }
  });

  group('mosaic and tiny framing boundaries', () {
    final profile = profileProvider.profileFor(
      object(
        id: 'BOUNDARY',
        type: ObjectType.openCluster,
        magnitude: '5.0',
        angularSize: "30' × 20'",
      ),
    );

    ImagingSuitabilityAssessment atFill(
      int fill, {
      bool supportsMosaic = true,
    }) {
      final coverage = fill / 100;
      return suitabilityService.assess(
        profile: profile,
        bortle: 5,
        trackingMode: TrackingMode.eq,
        equipmentFit: ImagingEquipmentFit(
          score: fill <= 5 ? 15 : 60,
          screenFillPercent: fill,
          framingRecommendation: coverage >= 1.6
              ? FramingRecommendation.mosaicRequired
              : coverage >= 1.3
              ? FramingRecommendation.tight
              : FramingRecommendation.good,
          supportsMosaic: supportsMosaic,
        ),
      );
    }

    test('1% is strongly capped and never enables mosaic', () {
      final result = atFill(1);
      expect(result.quality, ExpectedResultQuality.trace);
      expect(result.mosaicMode, MosaicMode.off);
    });

    test('5% remains small but non-mosaic', () {
      final result = atFill(5);
      expect(result.quality.level, lessThanOrEqualTo(2));
      expect(result.mosaicMode, MosaicMode.off);
    });

    test('159% stays single-frame while 160% enables supported mosaic', () {
      expect(atFill(159).mosaicMode, MosaicMode.off);
      expect(atFill(160).mosaicMode, MosaicMode.on);
      expect(atFill(160, supportsMosaic: false).mosaicMode, MosaicMode.off);
    });
  });
}

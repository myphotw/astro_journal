import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/core/constants/equipment_kind.dart';
import 'package:astro_journal/core/constants/equipment_purpose.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/equipment.dart';
import 'package:astro_journal/data/models/equipment_capture_capability.dart';
import 'package:astro_journal/data/models/equipment_exposure_capability.dart';
import 'package:astro_journal/data/models/equipment_recommendation.dart';
import 'package:astro_journal/data/models/eyepiece.dart';
import 'package:astro_journal/data/models/recommendation_result.dart';
import 'package:astro_journal/features/home/viewmodel/home_view_model.dart';
import 'package:astro_journal/services/equipment/equipment_recommendation_service.dart';
import 'package:astro_journal/services/equipment/equipment_capture_presets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = EquipmentRecommendationService();

  CatalogObject object({
    required String id,
    String type = '구상성단',
    String? objectType,
    String magnitude = '5.8',
    String? angularSize,
    List<String> tags = const [],
  }) {
    return CatalogObject(
      id: id,
      number: 13,
      catalog: CatalogType.messier,
      name: id.toUpperCase(),
      type: type,
      constellation: 'Hercules',
      ra: '16h41m',
      dec: "+36°28'",
      magnitude: magnitude,
      objectType: objectType,
      angularSize: angularSize,
      tags: tags,
    );
  }

  Equipment seestarS30() {
    return const Equipment(
      id: 's30',
      name: 'Seestar S30 Pro',
      kind: EquipmentKind.smartTelescope,
      purpose: EquipmentPurpose.imaging,
      focalLengthMm: 160,
      fovWidthDegrees: 2.24,
      fovHeightDegrees: 3.99,
    );
  }

  Equipment seestarS50() {
    return const Equipment(
      id: 's50',
      name: 'Seestar S50 Pro',
      kind: EquipmentKind.smartTelescope,
      purpose: EquipmentPurpose.imaging,
      focalLengthMm: 250,
      fovWidthDegrees: 0.72,
      fovHeightDegrees: 1.28,
    );
  }

  Equipment bcto90() {
    return Equipment(
      id: 'bcto',
      name: 'BCTO90',
      kind: EquipmentKind.reflector,
      purpose: EquipmentPurpose.visual,
      apertureMm: 90,
      focalLengthMm: 500,
      eyepieces: const [
        Eyepiece(
          id: 'ep25',
          equipmentId: 'bcto',
          name: '25mm',
          focalLengthMm: 25,
          afovDegrees: 50,
        ),
        Eyepiece(
          id: 'ep6',
          equipmentId: 'bcto',
          name: '6mm',
          focalLengthMm: 6,
          afovDegrees: 52,
        ),
      ],
    );
  }

  Equipment bcto90WithoutEyepieces() {
    return const Equipment(
      id: 'bcto-empty',
      name: 'BCTO90 Empty',
      kind: EquipmentKind.reflector,
      purpose: EquipmentPurpose.visual,
      apertureMm: 90,
      focalLengthMm: 500,
    );
  }

  group('EquipmentRecommendationService', () {
    test('ranks imaging equipment by fit and excludes 확대 촬영 추천', () {
      final result = service.recommendForObject(
        object: object(id: 'm13'),
        equipment: [seestarS50(), seestarS30()],
      );

      expect(result.imaging.length, 2);
      expect(
        result.imaging.first.score,
        greaterThanOrEqualTo(result.imaging.last.score),
      );
      for (final item in result.imaging) {
        expect(item.reason, isNot('확대 촬영 추천'));
      }
    });

    test('uses framing-specific wording for small targets', () {
      final result = service.recommendForObject(
        object: object(id: 'm57', type: '행성상성운'),
        equipment: [seestarS30(), seestarS50()],
      );

      expect(
        result.imaging.any(
          (item) => item.reason == '프레임 적합' || item.reason == '화각에 여유 있게 들어옴',
        ),
        isTrue,
      );
    });

    test('selects best eyepiece for M13 visual', () {
      final result = service.recommendForObject(
        object: object(id: 'm13'),
        equipment: [bcto90()],
      );

      expect(result.visual, isNotEmpty);
      final best = result.visual.first;
      expect(best.isRecommended, isTrue);
      expect(best.eyepiece, isNotNull);
      expect(best.eyepieceFocalLabel, isNotEmpty);
      expect(best.equipment.name, 'BCTO90');
      expect(best.screenFillPercent, greaterThan(0));
      expect(best.recommendedEyepieceFocalLengthMm, isNotNull);
    });

    test(
      'filters imaging and visual recommendations by registered purpose',
      () {
        final result = service.recommendForObject(
          object: object(id: 'm13'),
          equipment: [seestarS30(), bcto90()],
        );

        expect(result.imaging, isNotEmpty);
        expect(
          result.imaging.every((item) => item.equipment.isImaging),
          isTrue,
        );
        expect(result.visual, isNotEmpty);
        expect(result.visual.every((item) => item.equipment.isVisual), isTrue);
      },
    );

    test('hides visual recommendation for an imaging-only target policy', () {
      final result = service.recommendForObject(
        object: object(id: 'm17', type: '발광성운'),
        equipment: [seestarS30(), bcto90()],
      );

      expect(result.showImaging, isTrue);
      expect(result.showVisual, isFalse);
      expect(result.visual, isEmpty);
    });

    test(
      'keeps visual telescope and ideal eyepiece when none are registered',
      () {
        final result = service.recommendForObject(
          object: object(id: 'm13'),
          equipment: [bcto90WithoutEyepieces()],
        );

        expect(result.visual, hasLength(1));
        expect(result.visual.single.equipment.name, 'BCTO90 Empty');
        expect(result.visual.single.eyepiece, isNull);
        expect(
          result.visual.single.recommendedEyepieceFocalLengthMm,
          isNotNull,
        );
        expect(
          result.visualAvailability,
          EquipmentRecommendationAvailability.available,
        );
      },
    );

    test(
      'selects the best owned eyepiece separately from the ideal focal length',
      () {
        final result = service.recommendForObject(
          object: object(id: 'm8', type: '발광성운', angularSize: "60' × 60'"),
          equipment: [bcto90()],
        );

        final best = result.visual.first;
        expect(best.eyepiece?.focalLengthMm, 25);
        expect(best.recommendedEyepieceFocalLengthMm, closeTo(15.6, 0.6));
        expect(
          best.recommendedEyepieceFocalLengthMm,
          isNot(best.eyepiece?.focalLengthMm),
        );
      },
    );

    test(
      'distinguishes missing imaging equipment from missing FOV metadata',
      () {
        final noImaging = service.recommendForObject(
          object: object(id: 'm13'),
          equipment: [bcto90()],
        );
        final missingFov = service.recommendForObject(
          object: object(id: 'm13'),
          equipment: [
            const Equipment(
              id: 'camera-no-fov',
              name: 'Camera without FOV',
              kind: EquipmentKind.smartTelescope,
              purpose: EquipmentPurpose.imaging,
            ),
          ],
        );

        expect(
          noImaging.imagingAvailability,
          EquipmentRecommendationAvailability.notRegistered,
        );
        expect(
          missingFov.imagingAvailability,
          EquipmentRecommendationAvailability.insufficientData,
        );
      },
    );

    test('includes screen fill percent for imaging equipment', () {
      final result = service.recommendForObject(
        object: object(id: 'm13'),
        equipment: [seestarS30(), seestarS50()],
      );

      expect(result.imaging, isNotEmpty);
      for (final item in result.imaging) {
        expect(item.screenFillPercent, greaterThan(0));
      }
    });

    test('ranks visual eyepiece combos excluding over 100% fill', () {
      final result = service.recommendForObject(
        object: object(id: 'm13'),
        equipment: [bcto90()],
      );

      expect(result.visual, isNotEmpty);
      for (final item in result.visual) {
        expect(item.screenFillPercent, lessThanOrEqualTo(100));
        expect(item.isRecommended, isTrue);
      }
    });

    test('M31 on S30 Pro fits in one frame with orientation-aware fill', () {
      final result = service.recommendForObject(
        object: object(id: 'm31', type: '은하', angularSize: "190' × 60'"),
        equipment: [seestarS30()],
      );

      expect(result.imaging, isNotEmpty);
      final s30 = result.imaging.firstWhere((e) => e.equipment.id == 's30');
      expect(s30.screenFillPercent, lessThan(100));
      expect(s30.screenFillNote, isNull);
      expect(s30.reason, isNot('모자이크 권장'));
    });

    test('excludes narrow eyepiece when target fills over 100% of FOV', () {
      final result = service.recommendForObject(
        object: object(id: 'm31', type: '은하', angularSize: "190' × 60'"),
        equipment: [bcto90()],
      );

      expect(result.visual, isNotEmpty);
      expect(
        result.visual.every((item) => item.screenFillPercent <= 100),
        isTrue,
      );
      expect(
        result.visual.any((item) => item.eyepiece?.focalLengthMm == 6),
        isFalse,
      );
    });

    test(
      'hides veil nebula visual section under existing suitability policy',
      () {
        final result = service.recommendForObject(
          object: object(id: 'ngc6960', type: '초신성잔해'),
          equipment: [bcto90()],
        );

        expect(result.showVisual, isFalse);
        expect(result.visual, isEmpty);
      },
    );

    test('hides NGC6334 visual section under existing suitability policy', () {
      final result = service.recommendForObject(
        object: object(id: 'ngc6334', type: '발광성운'),
        equipment: [bcto90()],
      );

      expect(result.showVisual, isFalse);
      expect(result.visual, isEmpty);
    });

    test('recommends M8 visual without no-filter block', () {
      final result = service.recommendForObject(
        object: object(id: 'm8', type: '발광성운'),
        equipment: [bcto90()],
      );

      expect(result.visual, isNotEmpty);
      expect(result.visual.first.isRecommended, isTrue);
      expect(result.visual.first.eyepiece, isNotNull);
    });

    test('NGC2237 visual uses central cluster recommendation', () {
      final result = service.recommendForObject(
        object: object(id: 'ngc2237', type: '발광성운'),
        equipment: [bcto90()],
      );

      expect(result.visual, isNotEmpty);
      final best = result.visual.first;
      expect(best.isRecommended, isTrue);
      expect(best.reason, '중앙 산개성단 관측 추천');
      expect(best.eyepiece?.focalLengthMm, 25);
      expect(best.screenFillPercent, greaterThan(0));
    });

    test('recommendForToday prioritizes equipment reason over condition', () {
      final m40 = object(id: 'm40', type: '쌍성', angularSize: "0.8'");
      final rec = RecommendationResult(
        object: m40,
        reasons: const [],
        season: '여름',
        score: 85,
        moonSeparation: 60,
      );

      final today = service.recommendForToday(
        object: m40,
        equipment: [seestarS30()],
        recommendation: rec,
      );

      expect(today.imaging, isNotNull);
      expect(today.imaging!.reason, '천체가 너무 작음');
      expect(today.imaging!.reason, isNot('현재 조건 최적'));
    });

    test('recommendForToday does not block visual equipment for weather', () {
      final rec = RecommendationResult(
        object: object(id: 'm42', type: '발광성운'),
        reasons: const [],
        season: '겨울',
        score: 85,
        moonSeparation: 60,
      );

      final condition = ObservationCondition(
        score: 80,
        siteName: 'Test',
        moon: const MoonInfo(
          age: 10,
          illumination: 0.7,
          phaseName: '상현',
          phaseEmoji: '🌓',
        ),
        cloudCover: 60,
        isObservationFeasible: false,
      );

      final today = service.recommendForToday(
        object: object(id: 'm42', type: '발광성운'),
        equipment: [seestarS30(), bcto90()],
        recommendation: rec,
        condition: condition,
      );

      expect(today.visual, isNotEmpty);
    });

    test('recommendForToday keeps only the best owned visual combination', () {
      final target = object(id: 'm8', type: '발광성운', angularSize: "60' × 60'");
      final rec = RecommendationResult(
        object: target,
        reasons: const [],
        season: '여름',
        score: 85,
        moonSeparation: 60,
      );

      final today = service.recommendForToday(
        object: target,
        equipment: [bcto90()],
        recommendation: rec,
      );

      expect(today.visual, hasLength(1));
      expect(today.visual.single.eyepiece?.focalLengthMm, 25);
      expect(today.visual.single.recommendedEyepieceFocalLengthMm, isNotNull);
    });

    test('returns empty when no equipment registered', () {
      final result = service.recommendForObject(
        object: object(id: 'm42'),
        equipment: const [],
      );

      expect(result.hasRegisteredEquipment, isFalse);
      expect(result.imaging, isEmpty);
    });

    test('capture settings do not change the existing imaging fit score', () {
      final withoutCapability = seestarS30();
      final withCapability = withoutCapability.copyWith(
        captureCapability: EquipmentCapturePresets.build(
          EquipmentCapturePreset.seestarS30Pro,
        ),
      );

      final baseline = service.recommendForObject(
        object: object(id: 'm13'),
        equipment: [withoutCapability],
      );
      final extended = service.recommendForObject(
        object: object(id: 'm13'),
        equipment: [withCapability],
      );

      expect(extended.imaging.single.score, baseline.imaging.single.score);
      expect(
        extended.imaging.single.screenFillPercent,
        baseline.imaging.single.screenFillPercent,
      );
      expect(extended.imaging.single.captureSettings, hasLength(2));
    });

    test('builds independent AZ and EQ capture setting guidance', () {
      final equipment = seestarS30().copyWith(
        captureCapability: EquipmentCapturePresets.build(
          EquipmentCapturePreset.seestarS30Pro,
        ),
      );

      final result = service.recommendForObject(
        object: object(id: 'm42', type: '발광성운'),
        equipment: [equipment],
      );
      final settings = result.imaging.single.captureSettings;

      expect(settings.map((item) => item.mode), [
        CaptureRecommendationMode.altAz,
        CaptureRecommendationMode.equatorial,
      ]);
      expect(settings.first.exposureSupportLabel, contains('2/5/10/20/30/60초'));
      expect(settings.last.exposureSupportLabel, contains('2/5/10/20/30/60초'));
      expect(
        settings.map((item) => item.exposureConfidence),
        everyElement(CaptureRecommendationConfidence.experimental),
      );
      expect(
        settings.first.recommendedExposureSeconds!,
        lessThanOrEqualTo(settings.last.recommendedExposureSeconds!),
      );
    });

    test('folds sensor derotation capability into the AZ display mode', () {
      final equipment = seestarS30().copyWith(
        captureCapability: EquipmentCapturePresets.build(
          EquipmentCapturePreset.draco,
        ),
      );

      final settings = service
          .recommendForObject(
            object: object(id: 'm42', type: '발광성운'),
            equipment: [equipment],
          )
          .imaging
          .single
          .captureSettings;

      expect(settings, hasLength(2));
      final az = settings.singleWhere(
        (item) => item.mode == CaptureRecommendationMode.altAz,
      );
      expect(az.label, 'AZ');
      expect(az.usesSensorDerotation, isTrue);
      expect(az.cautions.single, contains('EQ 추적과 동일'));
    });

    test('never returns an exposure outside the registered capability', () {
      final captureCapability = EquipmentCapturePresets.build(
        EquipmentCapturePreset.draco,
      );
      final equipment = seestarS30().copyWith(
        captureCapability: captureCapability,
      );
      final settings = service
          .recommendForObject(
            object: object(id: 'm42', type: '발광성운'),
            equipment: [equipment],
          )
          .imaging
          .single
          .captureSettings;

      for (final setting in settings) {
        final recommended = setting.recommendedExposureSeconds;
        if (recommended != null) {
          expect(
            captureCapability.supportsExposure(setting.modeId, recommended),
            isTrue,
          );
        }
        expect(setting.exposureReason, contains('시작값'));
      }
    });

    test(
      'omits Gain for unsupported equipment and reports supported values',
      () {
        final seestar = seestarS30().copyWith(
          captureCapability: EquipmentCapturePresets.build(
            EquipmentCapturePreset.seestarS30Pro,
          ),
        );
        final draco = seestarS30().copyWith(
          id: 'draco',
          captureCapability: EquipmentCapturePresets.build(
            EquipmentCapturePreset.draco,
          ),
        );

        final result = service.recommendForObject(
          object: object(id: 'm42', type: '발광성운'),
          equipment: [seestar, draco],
        );
        final seestarResult = result.imaging.singleWhere(
          (item) => item.equipment.id == 's30',
        );
        final dracoResult = result.imaging.singleWhere(
          (item) => item.equipment.id == 'draco',
        );

        expect(seestarResult.captureSettings.first.gainSupportLabel, isNull);
        expect(
          dracoResult.captureSettings.first.gainSupportLabel,
          contains('240'),
        );
        expect(dracoResult.captureSettings.first.recommendedGain, isNull);
      },
    );

    test('intersects target filter semantics with equipment support', () {
      final equipment = seestarS30().copyWith(
        captureCapability: EquipmentCapturePresets.build(
          EquipmentCapturePreset.seestarS30Pro,
        ),
      );

      final emission = service.recommendForObject(
        object: object(id: 'm42', type: '발광성운'),
        equipment: [equipment],
      );
      final galaxy = service.recommendForObject(
        object: object(id: 'm31', type: '은하'),
        equipment: [equipment],
      );

      expect(emission.imaging.single.captureSettings.first.recommendedFilters, [
        '듀얼밴드',
      ]);
      expect(galaxy.imaging.single.captureSettings.first.recommendedFilters, [
        '필터 끄기',
      ]);
    });

    test('records only observation environment inputs that were provided', () {
      final equipment = seestarS30().copyWith(
        captureCapability: EquipmentCapturePresets.build(
          EquipmentCapturePreset.seestarS30Pro,
        ),
      );
      final contextual = service.recommendForObject(
        object: object(id: 'm31', type: '은하'),
        equipment: [equipment],
        captureContext: const CaptureRecommendationContext(
          siteName: '집',
          bortle: 8,
          targetAltitude: 42,
          moonIllumination: 0.8,
          moonSeparation: 30,
          observableMinutes: 90,
        ),
      );
      final withoutContext = service.recommendForObject(
        object: object(id: 'm31', type: '은하'),
        equipment: [equipment],
      );

      final contextualSetting = contextual.imaging.single.captureSettings.first;
      final fallbackSetting =
          withoutContext.imaging.single.captureSettings.first;
      expect(
        contextualSetting.exposureAdvisories.join(' '),
        contains('Bortle 8'),
      );
      expect(
        contextualSetting.exposureAdvisories.join(' '),
        contains('달 밝기 80%'),
      );
      expect(
        fallbackSetting.exposureAdvisories.where(
          (value) => value.startsWith('Bortle') || value.startsWith('달 '),
        ),
        isEmpty,
      );
    });

    test('shows SHO capability without inventing a channel ratio', () {
      final equipment = seestarS30().copyWith(
        captureCapability: EquipmentCapturePresets.build(
          EquipmentCapturePreset.draco,
        ),
      );

      final setting = service
          .recommendForObject(
            object: object(id: 'm42', type: '발광성운'),
            equipment: [equipment],
          )
          .imaging
          .single
          .captureSettings
          .first;
      final sho = setting.channelCombinations.single;

      expect(setting.recommendedFilters, contains('SHO'));
      expect(sho.guidance, contains('합계 100%'));
      expect(sho.recommendedPrimaryPercent, isNull);
      expect(sho.recommendedSecondaryPercent, isNull);
    });

    test('keeps legacy equipment without capture capability recommendable', () {
      final result = service.recommendForObject(
        object: object(id: 'm13'),
        equipment: [seestarS30()],
      );

      expect(result.imaging, hasLength(1));
      expect(result.imaging.single.captureSettings, isEmpty);
      expect(result.imaging.single.score, greaterThan(0));
    });

    test('M42 separates basic exposure from highlight protection', () {
      final equipment = seestarS30().copyWith(
        captureCapability: EquipmentCapturePresets.build(
          EquipmentCapturePreset.seestarS30Pro,
        ),
      );
      final settings = service
          .recommendForObject(
            object: object(
              id: 'M42',
              type: '성단과 성운',
              objectType: '성단과 성운',
              magnitude: '4.00',
              angularSize: "90' × 60'",
              tags: const ['발광성운'],
            ),
            equipment: [equipment],
            captureContext: const CaptureRecommendationContext(
              siteName: '집',
              bortle: 9,
              moonIllumination: 0.89,
              moonSeparation: 38,
            ),
          )
          .imaging
          .single
          .captureSettings;

      final az = settings.singleWhere(
        (item) => item.mode == CaptureRecommendationMode.altAz,
      );
      final eq = settings.singleWhere(
        (item) => item.mode == CaptureRecommendationMode.equatorial,
      );
      expect(az.recommendedExposureSeconds, 20);
      expect(eq.recommendedExposureSeconds, 30);
      expect(
        az.exposureRecommendations
            .singleWhere(
              (item) =>
                  item.purpose == CaptureExposurePurpose.highlightProtection,
            )
            .exposureSeconds,
        5,
      );
      expect(
        eq.exposureRecommendations
            .singleWhere(
              (item) =>
                  item.purpose == CaptureExposurePurpose.highlightProtection,
            )
            .exposureSeconds,
        5,
      );
      expect(az.exposureAdvisories.join(' '), contains('Bortle 9'));
      expect(az.exposureAdvisories.join(' '), contains('각거리 38°'));
    });

    test('M45 keeps exposure stable while environment advice changes', () {
      final equipment = seestarS30().copyWith(
        captureCapability: EquipmentCapturePresets.build(
          EquipmentCapturePreset.seestarS30Pro,
        ),
      );
      final target = object(
        id: 'M45',
        type: '산개성단',
        objectType: '반사성운',
        magnitude: '1.6',
        tags: const ['반사성운', '산개성단'],
      );

      List<CaptureModeRecommendation> settingsFor(int bortle) => service
          .recommendForObject(
            object: target,
            equipment: [equipment],
            captureContext: CaptureRecommendationContext(
              siteName: bortle == 9 ? '집' : '구례',
              bortle: bortle,
            ),
          )
          .imaging
          .single
          .captureSettings;

      final home = settingsFor(9);
      final gurye = settingsFor(4);
      expect(home.map((item) => item.recommendedExposureSeconds), [20, 60]);
      expect(gurye.map((item) => item.recommendedExposureSeconds), [20, 60]);
      expect(home.first.exposureAdvisories.join(' '), contains('Bortle 9'));
      expect(gurye.first.exposureAdvisories.join(' '), contains('Bortle 4'));
      expect(home.first.exposureAdvisories.join(' '), contains('히스토그램'));
      expect(
        gurye.first.exposureAdvisories.join(' '),
        isNot(contains('히스토그램')),
      );
    });

    test('supports AZ-only and EQ-only equipment without phantom modes', () {
      const exposure = DiscreteExposureCapability(valuesSeconds: [10, 20]);
      Equipment modeEquipment(String id, EquipmentCaptureModeType type) {
        return seestarS30().copyWith(
          id: id,
          captureCapability: EquipmentCaptureCapability(
            modes: [
              EquipmentCaptureModeCapability(
                id: id,
                type: type,
                label: type.label,
                exposureCapability: exposure,
              ),
            ],
          ),
        );
      }

      final result = service.recommendForObject(
        object: object(id: 'm13'),
        equipment: [
          modeEquipment('az-only', EquipmentCaptureModeType.altAz),
          modeEquipment('eq-only', EquipmentCaptureModeType.equatorial),
        ],
      );

      expect(
        result.imaging
            .singleWhere((item) => item.equipment.id == 'az-only')
            .captureSettings
            .single
            .mode,
        CaptureRecommendationMode.altAz,
      );
      expect(
        result.imaging
            .singleWhere((item) => item.equipment.id == 'eq-only')
            .captureSettings
            .single
            .mode,
        CaptureRecommendationMode.equatorial,
      );
    });
  });
}

import 'package:astro_journal/core/constants/equipment_kind.dart';
import 'package:astro_journal/core/constants/equipment_purpose.dart';
import 'package:astro_journal/core/constants/object_imaging_profile_defaults.dart';
import 'package:astro_journal/core/constants/object_type.dart';
import 'package:astro_journal/data/models/equipment.dart';
import 'package:astro_journal/data/models/equipment_capture_capability.dart';
import 'package:astro_journal/data/models/equipment_exposure_capability.dart';
import 'package:astro_journal/data/models/equipment_recommendation.dart';
import 'package:astro_journal/services/equipment/capture_setting_recommendation_policy.dart';
import 'package:astro_journal/services/equipment/equipment_capture_presets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final emission = ObjectImagingProfileDefaults.forType(
    ObjectType.emissionNebula,
  );
  final galaxy = ObjectImagingProfileDefaults.forType(ObjectType.galaxy);

  Equipment equipment(String id, EquipmentCaptureCapability capability) =>
      Equipment(
        id: id,
        name: id,
        kind: EquipmentKind.smartTelescope,
        purpose: EquipmentPurpose.imaging,
        captureCapability: capability,
      );

  test('experimental exposure stays inside discrete capability', () {
    final capability = EquipmentCapturePresets.build(
      EquipmentCapturePreset.seestarS30Pro,
    );
    final mode = capability.modeById(EquipmentCaptureModeCapability.altAzId)!;
    final decision = const CaptureSettingRecommendationPolicy().evaluate(
      equipment: equipment('s30', capability),
      capability: capability,
      mode: mode,
      profile: emission,
      context: const CaptureRecommendationContext(
        bortle: 8,
        moonIllumination: 0.8,
        moonSeparation: 30,
      ),
    );

    expect(
      decision.exposureConfidence,
      CaptureRecommendationConfidence.experimental,
    );
    expect(decision.exposureSeconds, isNotNull);
    expect(
      capability.supportsExposure(mode.id, decision.exposureSeconds!),
      isTrue,
    );
    expect(decision.filterInputs, contains('Bortle 8'));
    expect(
      decision.filterConfidence,
      CaptureRecommendationConfidence.experimental,
    );
    expect(decision.recommendedFilters, contains('듀얼밴드'));
  });

  test('missing observation context keeps a safe capability-only result', () {
    final capability = EquipmentCapturePresets.build(
      EquipmentCapturePreset.seestarS30Pro,
    );
    final mode = capability.modeById(
      EquipmentCaptureModeCapability.equatorialId,
    )!;
    final decision = const CaptureSettingRecommendationPolicy().evaluate(
      equipment: equipment('s30', capability),
      capability: capability,
      mode: mode,
      profile: galaxy,
    );

    expect(decision.exposureSeconds, isNotNull);
    expect(
      capability.supportsExposure(mode.id, decision.exposureSeconds!),
      isTrue,
    );
    expect(
      decision.exposureInputs.where((value) => value.startsWith('Bortle')),
      isEmpty,
    );
    expect(decision.recommendedFilters, ['필터 끄기']);
  });

  test('verified values are recommended only when capability accepts them', () {
    final capability = EquipmentCapturePresets.build(
      EquipmentCapturePreset.seestarS30Pro,
    );
    final mode = capability.modeById(
      EquipmentCaptureModeCapability.equatorialId,
    )!;
    const validPolicy = CaptureSettingRecommendationPolicy(
      verifiedRules: [
        VerifiedCaptureSettingRule(
          id: 'verified.s30.eq.emission.v1',
          equipmentId: 's30',
          modeIds: {EquipmentCaptureModeCapability.equatorialId},
          objectTypes: {ObjectType.emissionNebula},
          exposureSeconds: 30,
          filterTypes: {EquipmentFilterType.dualBand},
        ),
      ],
    );
    final verified = validPolicy.evaluate(
      equipment: equipment('s30', capability),
      capability: capability,
      mode: mode,
      profile: emission,
    );

    expect(verified.exposureSeconds, 30);
    expect(
      verified.exposureConfidence,
      CaptureRecommendationConfidence.recommended,
    );
    expect(verified.exposurePolicyId, 'verified.s30.eq.emission.v1');
    expect(
      verified.filterConfidence,
      CaptureRecommendationConfidence.recommended,
    );

    const invalidPolicy = CaptureSettingRecommendationPolicy(
      verifiedRules: [
        VerifiedCaptureSettingRule(
          id: 'invalid.s30.eq.emission',
          equipmentId: 's30',
          modeIds: {EquipmentCaptureModeCapability.equatorialId},
          objectTypes: {ObjectType.emissionNebula},
          exposureSeconds: 17,
        ),
      ],
    );
    final fallback = invalidPolicy.evaluate(
      equipment: equipment('s30', capability),
      capability: capability,
      mode: mode,
      profile: emission,
    );
    expect(
      fallback.exposureConfidence,
      CaptureRecommendationConfidence.experimental,
    );
    expect(
      capability.supportsExposure(mode.id, fallback.exposureSeconds!),
      isTrue,
    );
  });

  test('Gain remains unavailable until a verified sensor rule is supplied', () {
    final capability = EquipmentCapturePresets.build(
      EquipmentCapturePreset.draco,
    );
    final mode = capability.modeById(
      EquipmentCaptureModeCapability.equatorialId,
    )!;
    final unverified = const CaptureSettingRecommendationPolicy().evaluate(
      equipment: equipment('draco', capability),
      capability: capability,
      mode: mode,
      profile: emission,
    );
    expect(unverified.gain, isNull);
    expect(
      unverified.gainConfidence,
      CaptureRecommendationConfidence.unavailable,
    );

    const verifiedPolicy = CaptureSettingRecommendationPolicy(
      verifiedRules: [
        VerifiedCaptureSettingRule(
          id: 'verified.draco.gain.v1',
          equipmentId: 'draco',
          gain: 100,
        ),
      ],
    );
    final verified = verifiedPolicy.evaluate(
      equipment: equipment('draco', capability),
      capability: capability,
      mode: mode,
      profile: emission,
    );
    expect(verified.gain, 100);
    expect(
      verified.gainConfidence,
      CaptureRecommendationConfidence.recommended,
    );
  });

  test(
    'SHO ratio is unavailable by default and verified ratio sums to 100',
    () {
      final capability = EquipmentCapturePresets.build(
        EquipmentCapturePreset.draco,
      );
      final mode = capability.modeById(
        EquipmentCaptureModeCapability.equatorialId,
      )!;
      final unverified = const CaptureSettingRecommendationPolicy()
          .evaluate(
            equipment: equipment('draco', capability),
            capability: capability,
            mode: mode,
            profile: emission,
          )
          .channelCombinations
          .single;
      expect(
        unverified.confidence,
        CaptureRecommendationConfidence.unavailable,
      );
      expect(unverified.recommendedPrimaryPercent, isNull);

      const verifiedPolicy = CaptureSettingRecommendationPolicy(
        verifiedRules: [
          VerifiedCaptureSettingRule(
            id: 'verified.draco.sho.v1',
            equipmentId: 'draco',
            channelCombinationId: 'sho_so_ho',
            primaryPercent: 40,
          ),
        ],
      );
      final verified = verifiedPolicy
          .evaluate(
            equipment: equipment('draco', capability),
            capability: capability,
            mode: mode,
            profile: emission,
          )
          .channelCombinations
          .single;
      expect(verified.confidence, CaptureRecommendationConfidence.recommended);
      expect(verified.recommendedPrimaryPercent, 40);
      expect(verified.recommendedSecondaryPercent, 60);
      expect(
        capability.channelCombinations.single.isValidRatio(
          primaryPercent: verified.recommendedPrimaryPercent!,
          secondaryPercent: verified.recommendedSecondaryPercent!,
        ),
        isTrue,
      );
    },
  );

  test('unsupported filter semantics never create a recommendation', () {
    const capability = EquipmentCaptureCapability(
      modes: [
        EquipmentCaptureModeCapability(
          id: EquipmentCaptureModeCapability.equatorialId,
          type: EquipmentCaptureModeType.equatorial,
          label: 'EQ',
        ),
      ],
      filters: [
        EquipmentFilterCapability(
          id: 'dual',
          type: EquipmentFilterType.dualBand,
          name: '듀얼밴드',
        ),
      ],
    );
    final decision = const CaptureSettingRecommendationPolicy().evaluate(
      equipment: equipment('dual-only', capability),
      capability: capability,
      mode: capability.modes.single,
      profile: galaxy,
    );

    expect(decision.recommendedFilters, isEmpty);
    expect(
      decision.filterConfidence,
      CaptureRecommendationConfidence.unavailable,
    );
  });

  test('user baseline is injected without model-name hardcoding', () {
    final capability = EquipmentCapturePresets.build(
      EquipmentCapturePreset.seestarS30Pro,
    );
    final mode = capability.modeById(
      EquipmentCaptureModeCapability.equatorialId,
    )!;
    const policy = CaptureSettingRecommendationPolicy(
      experimentalBaselines: [
        ExperimentalExposureBaseline(
          id: 'user.s30.eq.v1',
          equipmentId: 'registered-s30',
          modeIds: {EquipmentCaptureModeCapability.equatorialId},
          exposureSeconds: 60,
        ),
      ],
    );
    final decision = policy.evaluate(
      equipment: equipment('registered-s30', capability),
      capability: capability,
      mode: mode,
      profile: emission,
    );

    expect(decision.exposureSeconds, 60);
    expect(
      decision.exposureConfidence,
      CaptureRecommendationConfidence.experimental,
    );
    expect(decision.exposurePolicyId, 'user.s30.eq.v1');
    expect(decision.exposureInputs, contains('사용자 촬영 기준'));
  });

  test('range and free-input exposure values stay inside capability', () {
    const capabilities = <EquipmentExposureCapability>[
      RangeExposureCapability(minSeconds: 10, maxSeconds: 90, stepSeconds: 10),
      FreeInputExposureCapability(minSeconds: 7, maxSeconds: 83),
    ];

    for (final exposure in capabilities) {
      final capability = EquipmentCaptureCapability(
        modes: [
          EquipmentCaptureModeCapability(
            id: EquipmentCaptureModeCapability.equatorialId,
            type: EquipmentCaptureModeType.equatorial,
            label: 'EQ',
            exposureCapability: exposure,
          ),
        ],
        filters: const [
          EquipmentFilterCapability(
            id: 'off',
            type: EquipmentFilterType.off,
            name: '필터 끄기',
          ),
        ],
      );
      final mode = capability.modes.single;
      final decision = const CaptureSettingRecommendationPolicy().evaluate(
        equipment: equipment('generic', capability),
        capability: capability,
        mode: mode,
        profile: galaxy,
      );

      expect(
        capability.supportsExposure(mode.id, decision.exposureSeconds!),
        isTrue,
      );
    }
  });
}

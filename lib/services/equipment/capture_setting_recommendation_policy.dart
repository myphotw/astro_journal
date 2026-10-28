import '../../core/constants/object_type.dart';
import '../../core/constants/surface_brightness_class.dart';
import '../../data/models/catalog_object.dart';
import '../../data/models/equipment.dart';
import '../../data/models/equipment_capture_capability.dart';
import '../../data/models/equipment_exposure_capability.dart';
import '../../data/models/equipment_recommendation.dart';
import '../../data/models/object_imaging_profile.dart';

/// 제조사 자료나 실측으로 검증된 규칙을 나중에 주입할 수 있는 계약.
///
/// 기본 정책에는 검증되지 않은 장비별 숫자를 포함하지 않는다. 규칙의 값이
/// 현재 장비 capability를 벗어나면 해당 값은 사용하지 않는다.
class VerifiedCaptureSettingRule {
  const VerifiedCaptureSettingRule({
    required this.id,
    required this.equipmentId,
    this.modeIds = const {},
    this.objectTypes = const {},
    this.exposureSeconds,
    this.gain,
    this.filterTypes = const {},
    this.channelCombinationId,
    this.primaryPercent,
  });

  final String id;
  final String equipmentId;
  final Set<String> modeIds;
  final Set<ObjectType> objectTypes;
  final double? exposureSeconds;
  final double? gain;
  final Set<EquipmentFilterType> filterTypes;
  final String? channelCombinationId;
  final int? primaryPercent;

  bool matches({
    required Equipment equipment,
    required EquipmentCaptureModeCapability mode,
    required ObjectImagingProfile profile,
  }) =>
      equipment.id == equipmentId &&
      (modeIds.isEmpty || modeIds.contains(mode.id)) &&
      (objectTypes.isEmpty || objectTypes.contains(profile.objectType));
}

/// 사용자의 실측 경험처럼 제조사 검증값은 아니지만 반복 촬영에서 얻은
/// 모드별 시작값을 정책에 주입하기 위한 런타임 계약.
///
/// DB에 저장된 값이 없으면 기본 정책이 임의로 장비명이나 모델명을 보고
/// 이 값을 생성하지 않는다.
class ExperimentalExposureBaseline {
  const ExperimentalExposureBaseline({
    required this.id,
    required this.equipmentId,
    required this.modeIds,
    required this.exposureSeconds,
  });

  final String id;
  final String equipmentId;
  final Set<String> modeIds;
  final double exposureSeconds;

  bool matches(Equipment equipment, EquipmentCaptureModeCapability mode) =>
      equipment.id == equipmentId && modeIds.contains(mode.id);
}

class CaptureModePolicyDecision {
  const CaptureModePolicyDecision({
    this.exposureSeconds,
    required this.exposureConfidence,
    required this.exposurePolicyId,
    required this.exposureReason,
    this.exposureInputs = const [],
    this.exposureRecommendations = const [],
    this.exposureAdvisories = const [],
    this.gain,
    required this.gainConfidence,
    required this.gainPolicyId,
    required this.gainReason,
    this.gainInputs = const [],
    this.recommendedFilters = const [],
    required this.filterConfidence,
    required this.filterPolicyId,
    required this.filterReason,
    this.filterInputs = const [],
    this.channelCombinations = const [],
  });

  final double? exposureSeconds;
  final CaptureRecommendationConfidence exposureConfidence;
  final String exposurePolicyId;
  final String exposureReason;
  final List<String> exposureInputs;
  final List<CaptureExposureRecommendation> exposureRecommendations;
  final List<String> exposureAdvisories;

  final double? gain;
  final CaptureRecommendationConfidence gainConfidence;
  final String gainPolicyId;
  final String gainReason;
  final List<String> gainInputs;

  final List<String> recommendedFilters;
  final CaptureRecommendationConfidence filterConfidence;
  final String filterPolicyId;
  final String filterReason;
  final List<String> filterInputs;

  final List<ChannelCombinationRecommendation> channelCombinations;
}

/// 장비 capability 안에서 촬영 시작값을 고르는 검증 가능한 정책.
///
/// 검증된 장비 규칙이 없을 때의 노출값은 최적값이 아니라, 천체의 기존
/// 표면밝기 분류를 capability의 상대 위치에 대응시킨 시험 시작값이다.
class CaptureSettingRecommendationPolicy {
  const CaptureSettingRecommendationPolicy({
    this.verifiedRules = const [],
    this.experimentalBaselines = const [],
  });

  static const experimentalExposurePolicyId =
      'capture.exposure.purpose-aware.v2';
  static const experimentalFilterPolicyId =
      'capture.filter.target-semantics.v1';
  static const unavailableGainPolicyId =
      'capture.gain.no-verified-sensor-rule.v1';
  static const unavailableChannelPolicyId =
      'capture.channels.no-verified-target-ratio.v1';

  final List<VerifiedCaptureSettingRule> verifiedRules;
  final List<ExperimentalExposureBaseline> experimentalBaselines;

  CaptureModePolicyDecision evaluate({
    required Equipment equipment,
    required EquipmentCaptureCapability capability,
    required EquipmentCaptureModeCapability mode,
    required ObjectImagingProfile profile,
    CatalogObject? target,
    CaptureRecommendationContext? context,
  }) {
    final rule = _matchingRule(
      equipment: equipment,
      mode: mode,
      profile: profile,
    );
    final filter = _filterDecision(
      capability: capability,
      profile: profile,
      context: context,
      rule: rule,
    );
    final exposure = _exposureDecision(
      equipment: equipment,
      capability: capability,
      mode: mode,
      profile: profile,
      target: target,
      context: context,
      filterTypes: filter.types,
      rule: rule,
    );
    final gain = _gainDecision(capability: capability, rule: rule);
    final channels = capability.channelCombinations
        .map((combination) => _channelDecision(combination, rule))
        .toList(growable: false);

    return CaptureModePolicyDecision(
      exposureSeconds: exposure.value,
      exposureConfidence: exposure.confidence,
      exposurePolicyId: exposure.policyId,
      exposureReason: exposure.reason,
      exposureInputs: exposure.inputs,
      exposureRecommendations: exposure.recommendations,
      exposureAdvisories: exposure.advisories,
      gain: gain.value,
      gainConfidence: gain.confidence,
      gainPolicyId: gain.policyId,
      gainReason: gain.reason,
      gainInputs: gain.inputs,
      recommendedFilters: filter.names,
      filterConfidence: filter.confidence,
      filterPolicyId: filter.policyId,
      filterReason: filter.reason,
      filterInputs: filter.inputs,
      channelCombinations: channels,
    );
  }

  VerifiedCaptureSettingRule? _matchingRule({
    required Equipment equipment,
    required EquipmentCaptureModeCapability mode,
    required ObjectImagingProfile profile,
  }) {
    for (final rule in verifiedRules) {
      if (rule.matches(equipment: equipment, mode: mode, profile: profile)) {
        return rule;
      }
    }
    return null;
  }

  _ExposureDecision _exposureDecision({
    required Equipment equipment,
    required EquipmentCaptureCapability capability,
    required EquipmentCaptureModeCapability mode,
    required ObjectImagingProfile profile,
    CatalogObject? target,
    required Set<EquipmentFilterType> filterTypes,
    CaptureRecommendationContext? context,
    VerifiedCaptureSettingRule? rule,
  }) {
    final exposureCapability = mode.exposureCapability;
    if (exposureCapability == null) {
      return const _ExposureDecision(
        confidence: CaptureRecommendationConfidence.unavailable,
        policyId: 'capture.exposure.no-capability.v1',
        reason: '모드별 단일 프레임 노출 capability가 등록되지 않았습니다.',
      );
    }
    final verified = rule?.exposureSeconds;
    if (verified != null && capability.supportsExposure(mode.id, verified)) {
      return _buildExposureDecision(
        exposureCapability: exposureCapability,
        standardValue: verified,
        standardConfidence: CaptureRecommendationConfidence.recommended,
        standardPolicyId: rule!.id,
        standardReason: '검증된 장비·모드별 기준과 등록 capability를 모두 만족합니다.',
        profile: profile,
        target: target,
        filterTypes: filterTypes,
        context: context,
        inputs: [
          '장비 ${rule.equipmentId}',
          '모드 ${mode.label}',
          '천체 ${profile.objectType.label}',
        ],
      );
    }
    final baseline = _matchingExperimentalBaseline(equipment, mode);
    if (baseline != null &&
        capability.supportsExposure(mode.id, baseline.exposureSeconds)) {
      return _buildExposureDecision(
        exposureCapability: exposureCapability,
        standardValue: baseline.exposureSeconds,
        standardConfidence: CaptureRecommendationConfidence.experimental,
        standardPolicyId: baseline.id,
        standardReason: '사용자가 제공한 반복 촬영 기준을 시험 시작값으로 사용합니다.',
        profile: profile,
        target: target,
        filterTypes: filterTypes,
        context: context,
        inputs: ['사용자 촬영 기준', '모드 ${mode.label}'],
      );
    }

    var targetPosition = switch (profile.surfaceBrightnessClass) {
      SurfaceBrightnessClass.veryBright => 0.55,
      SurfaceBrightnessClass.bright => 0.65,
      SurfaceBrightnessClass.normal => 0.72,
      SurfaceBrightnessClass.dim => 0.8,
      SurfaceBrightnessClass.veryDim => 0.9,
      SurfaceBrightnessClass.extremeDim => 0.95,
    };
    final inputs = <String>[
      '천체 ${profile.objectType.label}',
      '표면밝기 ${profile.surfaceBrightnessClass.name}',
      '모드 ${mode.label}',
    ];
    final narrowband =
        filterTypes.contains(EquipmentFilterType.dualBand) ||
        filterTypes.contains(EquipmentFilterType.narrowBand);
    if (narrowband) {
      targetPosition += 0.15;
      inputs.add('협대역 계열 필터');
    }

    final trackingCeiling = switch (mode.type) {
      EquipmentCaptureModeType.altAz => 0.65,
      EquipmentCaptureModeType.altAzDerotated => 0.85,
      EquipmentCaptureModeType.equatorial => 1.0,
      EquipmentCaptureModeType.custom => 0.8,
    };
    if (mode.type == EquipmentCaptureModeType.altAz) {
      inputs.add('일반 AZ 추적 한계');
    } else if (mode.type == EquipmentCaptureModeType.altAzDerotated) {
      inputs.add('AZ 센서 회전 보정');
    }
    final position = targetPosition.clamp(0.0, trackingCeiling);
    final value = _valueAt(exposureCapability, position);

    return _buildExposureDecision(
      exposureCapability: exposureCapability,
      standardValue: value,
      standardConfidence: CaptureRecommendationConfidence.experimental,
      standardPolicyId: experimentalExposurePolicyId,
      standardReason: '대상 신호 특성과 모드별 추적 제약을 분리해 정한 시작값입니다.',
      profile: profile,
      target: target,
      filterTypes: filterTypes,
      context: context,
      inputs: inputs,
    );
  }

  _ExposureDecision _buildExposureDecision({
    required EquipmentExposureCapability exposureCapability,
    required double standardValue,
    required CaptureRecommendationConfidence standardConfidence,
    required String standardPolicyId,
    required String standardReason,
    required ObjectImagingProfile profile,
    required Set<EquipmentFilterType> filterTypes,
    required List<String> inputs,
    CatalogObject? target,
    CaptureRecommendationContext? context,
  }) {
    final recommendations = <CaptureExposureRecommendation>[
      CaptureExposureRecommendation(
        purpose: CaptureExposurePurpose.standard,
        exposureSeconds: standardValue,
        confidence: standardConfidence,
        policyId: standardPolicyId,
        reason: standardReason,
        inputs: inputs,
      ),
    ];
    final magnitude = double.tryParse(target?.magnitude.trim() ?? '');
    final protectsHighlights =
        magnitude != null &&
        magnitude <= 4.5 &&
        (profile.objectType == ObjectType.emissionNebula ||
            profile.objectType == ObjectType.complexNebula ||
            profile.objectType == ObjectType.nebulaWithCluster ||
            profile.objectType == ObjectType.openCluster ||
            profile.objectType == ObjectType.star ||
            profile.objectType == ObjectType.doubleStar);
    if (protectsHighlights) {
      final shortValue = _valueAt(exposureCapability, 0.15);
      if (shortValue < standardValue) {
        recommendations.add(
          CaptureExposureRecommendation(
            purpose: CaptureExposurePurpose.highlightProtection,
            exposureSeconds: shortValue,
            confidence: CaptureRecommendationConfidence.experimental,
            policyId: 'capture.exposure.highlight-protection.v1',
            reason: '밝은 중심부나 별의 포화를 줄이기 위한 HDR 보조 프레임입니다.',
            inputs: [
              '천체 ${profile.objectType.label}',
              '등급 ${target!.magnitude}',
            ],
          ),
        );
      }
    }

    if (_needsFaintStructureGuidance(profile)) {
      recommendations.add(
        CaptureExposureRecommendation(
          purpose: CaptureExposurePurpose.faintStructure,
          confidence: CaptureRecommendationConfidence.experimental,
          policyId: 'capture.exposure.faint-structure-integration.v1',
          reason: '센서 포화 기준이 없어 더 긴 단일 노출을 임의로 만들지 않습니다.',
          guidance: '기본 노출 유지 · 총 적산시간 확보',
          inputs: ['천체 ${profile.objectType.label}'],
        ),
      );
    }

    return _ExposureDecision(
      value: standardValue,
      confidence: standardConfidence,
      policyId: standardPolicyId,
      reason: standardReason,
      inputs: inputs,
      recommendations: recommendations,
      advisories: _environmentAdvisories(
        context: context,
        narrowband:
            filterTypes.contains(EquipmentFilterType.dualBand) ||
            filterTypes.contains(EquipmentFilterType.narrowBand),
      ),
    );
  }

  ExperimentalExposureBaseline? _matchingExperimentalBaseline(
    Equipment equipment,
    EquipmentCaptureModeCapability mode,
  ) {
    for (final baseline in experimentalBaselines) {
      if (baseline.matches(equipment, mode)) return baseline;
    }
    return null;
  }

  bool _needsFaintStructureGuidance(ObjectImagingProfile profile) =>
      profile.objectType == ObjectType.emissionNebula ||
      profile.objectType == ObjectType.reflectionNebula ||
      profile.objectType == ObjectType.darkNebula ||
      profile.objectType == ObjectType.supernovaRemnant ||
      profile.objectType == ObjectType.complexNebula ||
      profile.objectType == ObjectType.nebulaWithCluster ||
      profile.surfaceBrightnessClass == SurfaceBrightnessClass.veryDim ||
      profile.surfaceBrightnessClass == SurfaceBrightnessClass.extremeDim;

  List<String> _environmentAdvisories({
    required CaptureRecommendationContext? context,
    required bool narrowband,
  }) {
    if (context == null || !context.hasData) return const [];
    final advisories = <String>[];
    if (context.bortle != null) {
      advisories.add(
        '관측지 ${context.siteName ?? '-'} · Bortle ${context.bortle}',
      );
      if (context.bortle! >= 7) {
        advisories.add(
          '밝은 배경에서는 히스토그램을 확인하고 단일 노출 단축보다 촬영 시점·총 적산시간을 먼저 조정하세요.',
        );
      }
    }
    final illumination = context.moonIllumination;
    final separation = context.moonSeparation;
    if (illumination != null && separation != null) {
      advisories.add(
        '달 밝기 ${(illumination * 100).round()}% · 각거리 ${separation.round()}°',
      );
      if (illumination >= 0.6 && separation < 60) {
        advisories.add(
          narrowband
              ? '달 영향은 듀얼·협대역으로 완화될 수 있으나 시험 프레임 확인이 필요합니다.'
              : '밝고 가까운 달은 촬영 시점 변경이나 총 적산시간 증가가 더 적절할 수 있습니다.',
        );
      }
    }
    if (context.targetAltitude != null) {
      advisories.add('대상 고도 ${context.targetAltitude!.round()}°');
    }
    if (context.observableMinutes != null) {
      advisories.add('관측 가능 ${context.observableMinutes}분');
    }
    return advisories;
  }

  _GainDecision _gainDecision({
    required EquipmentCaptureCapability capability,
    VerifiedCaptureSettingRule? rule,
  }) {
    final gainCapability = capability.gainCapability;
    if (gainCapability == null) {
      return const _GainDecision(
        confidence: CaptureRecommendationConfidence.unavailable,
        policyId: 'capture.gain.unsupported.v1',
        reason: '이 장비에는 Gain capability가 등록되지 않았습니다.',
      );
    }
    final verified = rule?.gain;
    if (verified != null && gainCapability.supports(verified)) {
      return _GainDecision(
        value: verified,
        confidence: CaptureRecommendationConfidence.recommended,
        policyId: rule!.id,
        reason: '검증된 센서별 기준과 등록 Gain capability를 모두 만족합니다.',
        inputs: ['장비 ${rule.equipmentId}'],
      );
    }
    return const _GainDecision(
      confidence: CaptureRecommendationConfidence.unavailable,
      policyId: unavailableGainPolicyId,
      reason: '검증된 센서별 Gain 기준이 없어 지원 범위만 안내합니다.',
    );
  }

  _FilterDecision _filterDecision({
    required EquipmentCaptureCapability capability,
    required ObjectImagingProfile profile,
    CaptureRecommendationContext? context,
    VerifiedCaptureSettingRule? rule,
  }) {
    final supported = capability.filters;
    if (supported.isEmpty) {
      return const _FilterDecision(
        confidence: CaptureRecommendationConfidence.unavailable,
        policyId: 'capture.filter.no-capability.v1',
        reason: '지원 필터 capability가 등록되지 않았습니다.',
      );
    }

    final verifiedTypes = rule?.filterTypes ?? const <EquipmentFilterType>{};
    final verified = supported
        .where((filter) => verifiedTypes.contains(filter.type))
        .toList(growable: false);
    if (verified.isNotEmpty) {
      return _FilterDecision(
        names: verified.map((filter) => filter.name).toList(growable: false),
        types: verified.map((filter) => filter.type).toSet(),
        confidence: CaptureRecommendationConfidence.recommended,
        policyId: rule!.id,
        reason: '검증된 대상·장비 규칙과 실제 지원 필터가 일치합니다.',
        inputs: ['천체 ${profile.objectType.label}', '장비 ${rule.equipmentId}'],
      );
    }

    final preferred = _preferredFilterTypes(profile);
    final matches = supported
        .where((filter) => preferred.contains(filter.type))
        .toList(growable: true);
    final impactedBySky =
        (context?.bortle ?? 0) >= 7 ||
        ((context?.moonIllumination ?? 0) >= 0.6 &&
            (context?.moonSeparation ?? 180) < 60);
    if (impactedBySky && profile.supportsNarrowband) {
      matches.sort((left, right) {
        int priority(EquipmentFilterType type) => switch (type) {
          EquipmentFilterType.narrowBand => 0,
          EquipmentFilterType.dualBand => 1,
          _ => 2,
        };
        return priority(left.type).compareTo(priority(right.type));
      });
    }
    if (matches.isEmpty) {
      return const _FilterDecision(
        confidence: CaptureRecommendationConfidence.unavailable,
        policyId: 'capture.filter.no-semantic-match.v1',
        reason: '천체 특성과 일치하는 지원 필터를 확정할 근거가 부족합니다.',
      );
    }

    final inputs = <String>[
      '천체 ${profile.objectType.label}',
      '카탈로그 필터 ${profile.recommendedFilters.join('/')}',
    ];
    if (context?.bortle != null) inputs.add('Bortle ${context!.bortle}');
    if (context?.moonIllumination != null && context?.moonSeparation != null) {
      inputs.add('달 밝기 ${(context!.moonIllumination! * 100).round()}%');
      inputs.add('달 각거리 ${context.moonSeparation!.round()}°');
    }
    return _FilterDecision(
      names: matches.map((filter) => filter.name).toList(growable: false),
      types: matches.map((filter) => filter.type).toSet(),
      confidence: CaptureRecommendationConfidence.experimental,
      policyId: experimentalFilterPolicyId,
      reason: '천체 분류와 카탈로그 필터 특성을 장비 지원 필터와 교차한 일반 촬영 안내입니다.',
      inputs: inputs,
    );
  }

  ChannelCombinationRecommendation _channelDecision(
    EquipmentChannelCombinationCapability capability,
    VerifiedCaptureSettingRule? rule,
  ) {
    final primary = rule?.channelCombinationId == capability.id
        ? rule?.primaryPercent
        : null;
    if (primary != null &&
        capability.isValidRatio(
          primaryPercent: primary,
          secondaryPercent: 100 - primary,
        )) {
      return ChannelCombinationRecommendation(
        id: capability.id,
        name: capability.name,
        guidance:
            '${capability.primaryLabel} $primary% · '
            '${capability.secondaryLabel} ${100 - primary}%',
        confidence: CaptureRecommendationConfidence.recommended,
        policyId: rule!.id,
        reason: '검증된 천체별 비율과 장비 비율 capability를 모두 만족합니다.',
        inputs: ['장비 ${rule.equipmentId}'],
        recommendedPrimaryPercent: primary,
        recommendedSecondaryPercent: 100 - primary,
      );
    }

    final guidance = capability.ratioAdjustable
        ? '${capability.primaryLabel} ${capability.minPrimaryPercent}~'
              '${capability.maxPrimaryPercent}% '
              '(${capability.stepPercent}% 간격, 합계 100%)'
        : '고정 채널 조합';
    return ChannelCombinationRecommendation(
      id: capability.id,
      name: capability.name,
      guidance: guidance,
      confidence: CaptureRecommendationConfidence.unavailable,
      policyId: unavailableChannelPolicyId,
      reason: '검증된 천체별 채널 비율이 없어 지원 범위만 안내합니다.',
    );
  }

  Set<EquipmentFilterType> _preferredFilterTypes(ObjectImagingProfile profile) {
    final metadata = profile.recommendedFilters
        .map((filter) => filter.toLowerCase())
        .toList(growable: false);
    final hasNarrowbandMetadata = metadata.any(
      (filter) =>
          filter.contains('ha') ||
          filter.contains('oiii') ||
          filter.contains('sii'),
    );
    if (profile.supportsNarrowband || hasNarrowbandMetadata) {
      return const {
        EquipmentFilterType.dualBand,
        EquipmentFilterType.narrowBand,
      };
    }

    return switch (profile.objectType) {
      ObjectType.galaxy ||
      ObjectType.galaxyGroup ||
      ObjectType.reflectionNebula ||
      ObjectType.darkNebula ||
      ObjectType.openCluster ||
      ObjectType.globularCluster ||
      ObjectType.starCloud ||
      ObjectType.milkyWay ||
      ObjectType.doubleStar ||
      ObjectType.star ||
      ObjectType.planet ||
      ObjectType.moon ||
      ObjectType.dwarfPlanet => const {
        EquipmentFilterType.broadband,
        EquipmentFilterType.off,
      },
      _ => const <EquipmentFilterType>{},
    };
  }

  double _valueAt(EquipmentExposureCapability capability, double position) {
    return switch (capability) {
      DiscreteExposureCapability(:final valuesSeconds) => () {
        final sorted = [...valuesSeconds]..sort();
        final index = (position * (sorted.length - 1)).round();
        return sorted[index];
      }(),
      RangeExposureCapability(
        :final minSeconds,
        :final maxSeconds,
        :final stepSeconds,
      ) =>
        () {
          final raw = minSeconds + (maxSeconds - minSeconds) * position;
          final steps = ((raw - minSeconds) / stepSeconds).round();
          return (minSeconds + steps * stepSeconds).clamp(
            minSeconds,
            maxSeconds,
          );
        }(),
      FreeInputExposureCapability(:final minSeconds, :final maxSeconds) =>
        (minSeconds + (maxSeconds - minSeconds) * position)
            .roundToDouble()
            .clamp(minSeconds, maxSeconds),
    };
  }
}

class _ExposureDecision {
  const _ExposureDecision({
    this.value,
    required this.confidence,
    required this.policyId,
    required this.reason,
    this.inputs = const [],
    this.recommendations = const [],
    this.advisories = const [],
  });

  final double? value;
  final CaptureRecommendationConfidence confidence;
  final String policyId;
  final String reason;
  final List<String> inputs;
  final List<CaptureExposureRecommendation> recommendations;
  final List<String> advisories;
}

class _GainDecision {
  const _GainDecision({
    this.value,
    required this.confidence,
    required this.policyId,
    required this.reason,
    this.inputs = const [],
  });

  final double? value;
  final CaptureRecommendationConfidence confidence;
  final String policyId;
  final String reason;
  final List<String> inputs;
}

class _FilterDecision {
  const _FilterDecision({
    this.names = const [],
    this.types = const {},
    required this.confidence,
    required this.policyId,
    required this.reason,
    this.inputs = const [],
  });

  final List<String> names;
  final Set<EquipmentFilterType> types;
  final CaptureRecommendationConfidence confidence;
  final String policyId;
  final String reason;
  final List<String> inputs;
}

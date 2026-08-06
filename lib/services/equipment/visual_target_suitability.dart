import '../../core/constants/angular_size_class.dart';

import '../../core/constants/object_type.dart';

import '../../core/constants/surface_brightness_class.dart';

import '../../core/constants/visual_observation_weights.dart';

import '../../data/models/catalog_object.dart';

import '../../data/models/object_imaging_profile.dart';



/// 안시 관측 기준 (기본: 필터 없음).

enum VisualObservationBasis {

  standard,

  noFilterExempt,

  noFilterModerate,

  centralOpenCluster,

}



class VisualTargetSuitabilityInfo {

  const VisualTargetSuitabilityInfo({

    required this.tier,

    required this.visualSurfaceBrightness,

    required this.requiresWideField,

    required this.forceNotRecommended,

    required this.observationBasis,

    required this.noFilterPenalty,

    this.effectiveObjectType,

    this.effectiveTargetSizeDegrees,

    this.blockReason,

  });



  final VisualSuitabilityTier tier;

  final SurfaceBrightnessClass visualSurfaceBrightness;

  final bool requiresWideField;

  final bool forceNotRecommended;

  final VisualObservationBasis observationBasis;

  final double noFilterPenalty;

  final ObjectType? effectiveObjectType;

  final double? effectiveTargetSizeDegrees;

  final String? blockReason;

}



/// 안시 관측 적합/부적합 천체 분류 (카탈로그 ID 기준, 필터 없음 전제).

abstract final class VisualTargetSuitability {

  static const _wideFieldRequiredIds = {

    'ic1340',

    'ic4628',

    'ngc6960',

    'ngc6992',

    'ngc7000',

    'ngc1499',

    'ngc6334',

    'sh2-276',

    'sh2276',

    'barnard loop',

  };



  static const _veryDimVisualIds = {

    'ngc6334',

    'ngc1499',

    'ngc7000',

    'ic4628',

    'sh2-276',

    'sh2276',

    'ic1340',

    'ngc6960',

    'ngc6992',

  };



  static const _highSuitabilityIds = {

    'm13',

    'm57',

    'm27',

    'm42',

    'm8',

  };



  static const _noFilterExemptIds = {'m42', 'm8'};



  static const _noFilterModerateIds = {'m20'};



  static const _centralOpenClusterIds = {'ngc2237', 'c49'};



  static VisualTargetSuitabilityInfo analyze(

    CatalogObject object,

    ObjectImagingProfile profile,

  ) {

    final basis = _observationBasisFor(object);

    final tier = tierFor(object, basis: basis);

    final visualBrightness = _visualSurfaceBrightness(object, profile, tier);

    final requiresWideField = _requiresWideField(object, basis: basis);

    final penalizedWithoutWhitelist = _isPenalizedWithoutWhitelist(
      basis: basis,
      objectType: profile.objectType,
    );

    final forceBlock = penalizedWithoutWhitelist ||
        _shouldForceBlock(

      basis: basis,

      tier: tier,

      brightness: visualBrightness,

      requiresWideField: requiresWideField,

    );



    final effectiveType = basis == VisualObservationBasis.centralOpenCluster

        ? ObjectType.openCluster

        : null;

    final effectiveSize = basis == VisualObservationBasis.centralOpenCluster

        ? VisualObservationWeights.centralClusterSizeDegrees

        : null;



    return VisualTargetSuitabilityInfo(

      tier: tier,

      visualSurfaceBrightness: visualBrightness,

      requiresWideField: requiresWideField,

      forceNotRecommended: forceBlock,

      observationBasis: basis,

      noFilterPenalty: _noFilterPenalty(basis, profile.objectType, profile),

      effectiveObjectType: effectiveType,

      effectiveTargetSizeDegrees: effectiveSize,

      blockReason: forceBlock

          ? (penalizedWithoutWhitelist
              ? '필터 없이 관측이 어렵습니다.'
              : _blockReason(

              brightness: visualBrightness,

              requiresWideField: requiresWideField,

            ))

          : null,

    );

  }



  static VisualSuitabilityTier tierFor(

    CatalogObject object, {

    VisualObservationBasis? basis,

  }) {

    final resolvedBasis = basis ?? _observationBasisFor(object);

    if (resolvedBasis == VisualObservationBasis.centralOpenCluster) {

      return VisualSuitabilityTier.normal;

    }



    final id = object.id.toLowerCase();

    final displayId = object.displayId.toLowerCase();

    final name = object.name.toLowerCase();

    final common = object.commonName?.toLowerCase() ?? '';



    if (_matches(id, displayId, name, common, _wideFieldRequiredIds) ||

        name.contains('veil') ||

        name.contains('california') ||

        name.contains('north america') ||

        name.contains('rosette') ||

        (name.contains('cat') && name.contains('paw')) ||

        common.contains('장막') ||

        common.contains('california') ||

        common.contains('장미') ||

        common.contains('고양이')) {

      return VisualSuitabilityTier.low;

    }



    if (_matches(id, displayId, name, common, _highSuitabilityIds)) {

      return VisualSuitabilityTier.high;

    }



    return VisualSuitabilityTier.normal;

  }



  static VisualObservationBasis _observationBasisFor(CatalogObject object) {

    final id = object.id.toLowerCase();

    final displayId = object.displayId.toLowerCase();

    final name = object.name.toLowerCase();

    final common = object.commonName?.toLowerCase() ?? '';



    if (_matches(id, displayId, name, common, _centralOpenClusterIds) ||

        common.contains('장미')) {

      return VisualObservationBasis.centralOpenCluster;

    }

    if (_matches(id, displayId, name, common, _noFilterExemptIds)) {

      return VisualObservationBasis.noFilterExempt;

    }

    if (_matches(id, displayId, name, common, _noFilterModerateIds)) {

      return VisualObservationBasis.noFilterModerate;

    }

    return VisualObservationBasis.standard;

  }



  static double _noFilterPenalty(

    VisualObservationBasis basis,

    ObjectType objectType,

    ObjectImagingProfile profile,

  ) {

    return switch (basis) {

      VisualObservationBasis.noFilterExempt => 1.0,

      VisualObservationBasis.noFilterModerate =>

        VisualObservationWeights.noFilterModeratePenalty,

      VisualObservationBasis.centralOpenCluster => 1.0,

      VisualObservationBasis.standard => _standardNoFilterPenalty(

          objectType,

          profile,

        ),

    };

  }



  static double _standardNoFilterPenalty(

    ObjectType objectType,

    ObjectImagingProfile profile,

  ) {

    final penalizedType =

        VisualObservationWeights.isNoFilterPenalizedType(objectType);

    final veryLarge =

        profile.angularSizeClass == AngularSizeClass.veryLarge;



    if (penalizedType || (objectType.isNebula && veryLarge)) {

      return VisualObservationWeights.noFilterNebulaPenalty;

    }

    return 1.0;

  }



  /// 필터 없음 기준 안시 화이트리스트 (이 목록·모드만 성운류 추천 허용).
  static bool isNoFilterVisualWhitelist(CatalogObject object) {
    final basis = _observationBasisFor(object);
    return basis != VisualObservationBasis.standard;
  }

  static bool _isPenalizedWithoutWhitelist({
    required VisualObservationBasis basis,
    required ObjectType objectType,
  }) {
    if (basis != VisualObservationBasis.standard) return false;
    return VisualObservationWeights.isNoFilterPenalizedType(objectType);
  }

  static bool _shouldForceBlock({

    required VisualObservationBasis basis,

    required VisualSuitabilityTier tier,

    required SurfaceBrightnessClass brightness,

    required bool requiresWideField,

  }) {

    if (basis == VisualObservationBasis.centralOpenCluster) {

      return false;

    }

    if (basis == VisualObservationBasis.noFilterExempt) {

      return false;

    }



    return (tier == VisualSuitabilityTier.low || requiresWideField) &&

        brightness.index >= SurfaceBrightnessClass.dim.index;

  }



  static SurfaceBrightnessClass _visualSurfaceBrightness(

    CatalogObject object,

    ObjectImagingProfile profile,

    VisualSuitabilityTier tier,

  ) {

    if (_matchesAnyKnownDimTarget(object)) {

      return SurfaceBrightnessClass.veryDim;

    }



    if (tier == VisualSuitabilityTier.low) {

      return _diminish(profile.surfaceBrightnessClass, 2);

    }



    if (tier == VisualSuitabilityTier.high) {

      return _brighten(profile.surfaceBrightnessClass, 1);

    }



    return profile.surfaceBrightnessClass;

  }



  static bool _requiresWideField(

    CatalogObject object, {

    VisualObservationBasis? basis,

  }) {

    final resolvedBasis = basis ?? _observationBasisFor(object);

    if (resolvedBasis == VisualObservationBasis.centralOpenCluster) {

      return false;

    }

    return _matchesAnyKnownDimTarget(object) ||

        tierFor(object, basis: resolvedBasis) == VisualSuitabilityTier.low;

  }



  static bool _matchesAnyKnownDimTarget(CatalogObject object) {

    final id = object.id.toLowerCase();

    final displayId = object.displayId.toLowerCase();

    final name = object.name.toLowerCase();

    final common = object.commonName?.toLowerCase() ?? '';

    return _matches(

      id,

      displayId,

      name,

      common,

      _veryDimVisualIds,

    );

  }



  static String _blockReason({

    required SurfaceBrightnessClass brightness,

    required bool requiresWideField,

  }) {

    if (requiresWideField) {

      return '필터 없이 관측이 어렵습니다.';

    }

    if (brightness.index >= SurfaceBrightnessClass.veryDim.index) {

      return '표면 밝기가 매우 낮습니다.';

    }

    if (brightness.index >= SurfaceBrightnessClass.dim.index) {

      return '현재 장비로는 안시가 어렵습니다.';

    }

    return '필터 없이 관측이 어렵습니다.';

  }



  static SurfaceBrightnessClass _diminish(

    SurfaceBrightnessClass value,

    int steps,

  ) {

    final next = value.index + steps;

    if (next >= SurfaceBrightnessClass.values.length) {

      return SurfaceBrightnessClass.extremeDim;

    }

    return SurfaceBrightnessClass.values[next];

  }



  static SurfaceBrightnessClass _brighten(

    SurfaceBrightnessClass value,

    int steps,

  ) {

    final next = value.index - steps;

    if (next < 0) return SurfaceBrightnessClass.veryBright;

    return SurfaceBrightnessClass.values[next];

  }



  static bool _matches(

    String id,

    String displayId,

    String name,

    String common,

    Set<String> keys,

  ) {

    for (final key in keys) {

      if (id == key ||

          displayId == key ||

          id.contains(key) ||

          displayId.contains(key) ||

          name.contains(key) ||

          common.contains(key)) {

        return true;

      }

    }

    return false;

  }

}



enum VisualSuitabilityTier {

  high,

  normal,

  low,

}


import '../core/constants/imaging_recommendation_rules.dart';
import '../core/constants/surface_brightness_class.dart';
import '../data/models/catalog_exposure_guidance.dart';
import '../data/models/imaging_suitability_assessment.dart';
import '../data/models/object_imaging_profile.dart';
import 'exposure_policy.dart';
import 'imaging_suitability_service.dart';

/// Builds catalog-detail exposure guidance from reference Bortle settings.
class CatalogExposureGuidanceBuilder {
  const CatalogExposureGuidanceBuilder({
    ExposurePolicy? exposurePolicy,
    ImagingSuitabilityService? imagingSuitabilityService,
  }) : _exposurePolicy = exposurePolicy ?? const ExposurePolicy(),
       _imagingSuitabilityService =
           imagingSuitabilityService ?? const ImagingSuitabilityService();

  final ExposurePolicy _exposurePolicy;
  final ImagingSuitabilityService _imagingSuitabilityService;

  CatalogExposureGuidance build({
    required ObjectImagingProfile profile,
    required int referenceBortle,
    ImagingEquipmentFit? equipmentFit,
    TrackingMode trackingMode = TrackingMode.altAz,
  }) {
    final feasibility = _resolveFeasibility(profile, referenceBortle);
    final showsCurrent = feasibility.showsCurrentExposureTime;
    final showsIdeal = feasibility.showsIdealEnvironment;

    final currentMin = showsCurrent
        ? _exposurePolicy
              .calculateMinimumExposure(
                bortle: referenceBortle,
                profile: profile,
              )
              .inMinutes
        : null;
    final currentRec = showsCurrent
        ? _exposurePolicy
              .calculateRecommendedExposure(
                bortle: referenceBortle,
                profile: profile,
              )
              .inMinutes
        : null;

    final idealBortle = showsIdeal ? profile.recommendedBortle : null;
    final idealMin = showsIdeal
        ? _exposurePolicy
              .calculateMinimumExposure(
                bortle: profile.recommendedBortle,
                profile: profile,
              )
              .inMinutes
        : null;
    final idealRec = showsIdeal
        ? _exposurePolicy
              .calculateRecommendedExposure(
                bortle: profile.recommendedBortle,
                profile: profile,
              )
              .inMinutes
        : null;
    final assessment = _imagingSuitabilityService.assess(
      profile: profile,
      bortle: referenceBortle,
      trackingMode: trackingMode,
      equipmentFit: equipmentFit,
      recommendedExposure: _exposurePolicy.calculateRecommendedExposure(
        bortle: referenceBortle,
        profile: profile,
      ),
    );

    return CatalogExposureGuidance(
      referenceBortle: referenceBortle,
      feasibility: feasibility,
      currentMinimumMinutes: currentMin,
      currentRecommendedMinutes: currentRec,
      reason: showsCurrent ? null : _resolveReason(profile, referenceBortle),
      idealBortle: idealBortle,
      idealMinimumMinutes: idealMin,
      idealRecommendedMinutes: idealRec,
      imagingAssessment: assessment,
    );
  }

  CatalogExposureFeasibility _resolveFeasibility(
    ObjectImagingProfile profile,
    int referenceBortle,
  ) {
    if (ImagingRecommendationRules.isTypeExcludedAtBortle(
          profile.objectType,
          referenceBortle,
        ) ||
        referenceBortle > profile.minimumRecommendedBortle + 1) {
      return CatalogExposureFeasibility.stronglyNotRecommended;
    }

    if (!_exposurePolicy.isRecommended(
      bortle: referenceBortle,
      profile: profile,
    )) {
      return CatalogExposureFeasibility.notRecommended;
    }

    if (referenceBortle <= profile.recommendedBortle) {
      return CatalogExposureFeasibility.recommended;
    }

    return CatalogExposureFeasibility.feasible;
  }

  String _resolveReason(ObjectImagingProfile profile, int referenceBortle) {
    if (ImagingRecommendationRules.isTypeExcludedAtBortle(
      profile.objectType,
      referenceBortle,
    )) {
      return '현재 환경에서는 촬영을 권장하지 않습니다.';
    }

    if (referenceBortle > profile.minimumRecommendedBortle + 1) {
      return '광해 영향이 큽니다.';
    }

    switch (profile.surfaceBrightnessClass) {
      case SurfaceBrightnessClass.extremeDim:
      case SurfaceBrightnessClass.veryDim:
        return '대상이 매우 희미합니다.';
      case SurfaceBrightnessClass.dim:
        return '낮은 표면밝기입니다.';
      case SurfaceBrightnessClass.normal:
      case SurfaceBrightnessClass.bright:
      case SurfaceBrightnessClass.veryBright:
        if (referenceBortle > profile.recommendedBortle) {
          return '광해 영향이 큽니다.';
        }
        return '현재 환경에서는 촬영 효율이 낮습니다.';
    }
  }
}

import '../../core/constants/angular_size_class.dart';
import '../../core/constants/imaging_difficulty.dart';
import '../../core/constants/object_type.dart';
import '../../core/constants/surface_brightness_class.dart';

enum ImagingMetadataReliability { reliable, partial, missing }

/// Runtime-only sensitivity to light pollution, derived from the existing
/// object type and imaging profile. It is intentionally not persisted in the
/// catalog database.
enum TargetLightPollutionSensitivity { low, medium, high, veryHigh }

extension TargetLightPollutionSensitivityLabel
    on TargetLightPollutionSensitivity {
  String get label => switch (this) {
    TargetLightPollutionSensitivity.low => '낮음',
    TargetLightPollutionSensitivity.medium => '보통',
    TargetLightPollutionSensitivity.high => '높음',
    TargetLightPollutionSensitivity.veryHigh => '매우 높음',
  };
}

/// Per-target imaging characteristics used by exposure and score engines.
class ObjectImagingProfile {
  const ObjectImagingProfile({
    required this.objectType,
    required this.imagingDifficulty,
    required this.surfaceBrightnessClass,
    required this.angularSizeClass,
    required this.baseExposureMinutes,
    required this.minimumRecommendedBortle,
    required this.recommendedBortle,
    required this.supportsNarrowband,
    required this.recommendedFilters,
    this.estimatedSurfaceBrightness,
    this.metadataReliability = ImagingMetadataReliability.missing,
  });

  final ObjectType objectType;
  final ImagingDifficulty imagingDifficulty;
  final SurfaceBrightnessClass surfaceBrightnessClass;
  final AngularSizeClass angularSizeClass;
  final int baseExposureMinutes;

  /// Worst acceptable Bortle scale (higher = more light pollution tolerated).
  final int minimumRecommendedBortle;

  /// Ideal observation site Bortle (lower = darker sky).
  final int recommendedBortle;
  final bool supportsNarrowband;
  final List<String> recommendedFilters;

  /// Estimated mean surface brightness in mag/arcsec^2.
  ///
  /// This is only populated when both integrated magnitude and angular size
  /// are available. A null value means the catalog metadata is insufficient;
  /// callers must keep the existing type-based fallback.
  final double? estimatedSurfaceBrightness;

  /// Runtime-only confidence derived from magnitude and angular-size fields.
  /// It is deliberately not persisted in SQLite.
  final ImagingMetadataReliability metadataReliability;

  TargetLightPollutionSensitivity get lightPollutionSensitivity {
    if (objectType == ObjectType.reflectionNebula ||
        objectType == ObjectType.darkNebula ||
        surfaceBrightnessClass == SurfaceBrightnessClass.extremeDim ||
        surfaceBrightnessClass == SurfaceBrightnessClass.veryDim) {
      return TargetLightPollutionSensitivity.veryHigh;
    }

    if (objectType == ObjectType.galaxyGroup ||
        objectType == ObjectType.starCloud ||
        objectType == ObjectType.milkyWay ||
        surfaceBrightnessClass == SurfaceBrightnessClass.dim ||
        minimumRecommendedBortle <= 3) {
      return TargetLightPollutionSensitivity.high;
    }

    if ((supportsNarrowband &&
            surfaceBrightnessClass.index <=
                SurfaceBrightnessClass.normal.index) ||
        surfaceBrightnessClass == SurfaceBrightnessClass.veryBright ||
        surfaceBrightnessClass == SurfaceBrightnessClass.bright) {
      return TargetLightPollutionSensitivity.low;
    }

    return TargetLightPollutionSensitivity.medium;
  }

  ObjectImagingProfile copyWith({
    ObjectType? objectType,
    ImagingDifficulty? imagingDifficulty,
    SurfaceBrightnessClass? surfaceBrightnessClass,
    AngularSizeClass? angularSizeClass,
    int? baseExposureMinutes,
    int? minimumRecommendedBortle,
    int? recommendedBortle,
    bool? supportsNarrowband,
    List<String>? recommendedFilters,
    double? estimatedSurfaceBrightness,
    ImagingMetadataReliability? metadataReliability,
  }) {
    return ObjectImagingProfile(
      objectType: objectType ?? this.objectType,
      imagingDifficulty: imagingDifficulty ?? this.imagingDifficulty,
      surfaceBrightnessClass:
          surfaceBrightnessClass ?? this.surfaceBrightnessClass,
      angularSizeClass: angularSizeClass ?? this.angularSizeClass,
      baseExposureMinutes: baseExposureMinutes ?? this.baseExposureMinutes,
      minimumRecommendedBortle:
          minimumRecommendedBortle ?? this.minimumRecommendedBortle,
      recommendedBortle: recommendedBortle ?? this.recommendedBortle,
      supportsNarrowband: supportsNarrowband ?? this.supportsNarrowband,
      recommendedFilters: recommendedFilters ?? this.recommendedFilters,
      estimatedSurfaceBrightness:
          estimatedSurfaceBrightness ?? this.estimatedSurfaceBrightness,
      metadataReliability: metadataReliability ?? this.metadataReliability,
    );
  }
}

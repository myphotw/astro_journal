import 'dart:math' as math;

import '../core/constants/angular_size_class.dart';
import '../core/constants/catalog_object_metadata_overrides.dart';
import '../core/constants/imaging_difficulty.dart';
import '../core/constants/object_imaging_profile_defaults.dart';
import '../core/constants/object_type.dart';
import '../core/constants/surface_brightness_class.dart';
import '../data/models/catalog_object.dart';
import '../data/models/object_imaging_profile.dart';
import '../data/models/representative_framing_size.dart';
import 'equipment/angular_size_parser.dart';

/// Infers per-target imaging traits from catalog metadata and type templates.
///
/// No per-catalog-id profile overrides are used. Brightness and difficulty are
/// derived from magnitude, angular size, and [ObjectType] rules.
class ImagingProfileResolver {
  const ImagingProfileResolver();

  ObjectImagingProfile resolve(CatalogObject object, ObjectType objectType) {
    final template = ObjectImagingProfileDefaults.forType(objectType);
    final angularSize = _resolveAngularSize(object);
    final maxArcmin = angularSize == null
        ? null
        : math.max(angularSize.widthArcmin, angularSize.heightArcmin);
    final angularSizeClass = _resolveAngularSizeClass(maxArcmin);
    final magnitude = _parseMagnitude(object.magnitude);
    final metadataReliability = switch ((magnitude, angularSize)) {
      (final double _, final RepresentativeFramingSize _) =>
        ImagingMetadataReliability.reliable,
      (null, null) => ImagingMetadataReliability.missing,
      _ => ImagingMetadataReliability.partial,
    };
    final estimatedSurfaceBrightness = _estimateSurfaceBrightness(
      magnitude: magnitude,
      widthArcmin: angularSize?.widthArcmin,
      heightArcmin: angularSize?.heightArcmin,
    );

    final brightness = _inferSurfaceBrightness(
      objectType: objectType,
      magnitude: magnitude,
      maxArcmin: maxArcmin,
      estimatedSurfaceBrightness: estimatedSurfaceBrightness,
    );
    final difficulty = _inferImagingDifficulty(
      objectType: objectType,
      brightness: brightness,
    );

    return template.copyWith(
      surfaceBrightnessClass: brightness,
      imagingDifficulty: difficulty,
      angularSizeClass: angularSizeClass,
      baseExposureMinutes: brightness.baseExposureMinutes,
      estimatedSurfaceBrightness: estimatedSurfaceBrightness,
      metadataReliability: metadataReliability,
    );
  }

  RepresentativeFramingSize? _resolveAngularSize(CatalogObject object) {
    if (object.majorAxis != null &&
        object.minorAxis != null &&
        object.majorAxis! > 0 &&
        object.minorAxis! > 0) {
      return RepresentativeFramingSize(
        widthArcmin: object.majorAxis!,
        heightArcmin: object.minorAxis!,
      );
    }

    final candidates = <String?>[
      object.angularSize,
      CatalogObjectMetadataOverrides.forId(object.id)?.angularSize,
      CatalogObjectMetadataOverrides.forId(object.displayId)?.angularSize,
      CatalogObjectMetadataOverrides.representativeFramingOverrideForId(
        object.id,
      ),
      CatalogObjectMetadataOverrides.representativeFramingOverrideForId(
        object.displayId,
      ),
    ];

    RepresentativeFramingSize? best;
    for (final raw in candidates) {
      final parsed = AngularSizeParser.parse(raw);
      if (parsed == null) continue;
      final maxSide = math.max(parsed.widthArcmin, parsed.heightArcmin);
      final bestMaxSide = best == null
          ? null
          : math.max(best.widthArcmin, best.heightArcmin);
      if (bestMaxSide == null || maxSide > bestMaxSide) {
        best = parsed;
      }
    }
    return best;
  }

  double? _estimateSurfaceBrightness({
    required double? magnitude,
    required double? widthArcmin,
    required double? heightArcmin,
  }) {
    if (magnitude == null ||
        widthArcmin == null ||
        heightArcmin == null ||
        widthArcmin <= 0 ||
        heightArcmin <= 0) {
      return null;
    }

    // Mean surface brightness for an elliptical target:
    // mu = integrated magnitude + 2.5 log10(area in arcsec^2).
    final areaArcsecSquared = math.pi * widthArcmin * heightArcmin * 3600 / 4;
    return magnitude + 2.5 * math.log(areaArcsecSquared) / math.ln10;
  }

  double? _parseMagnitude(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed == '-') {
      return null;
    }
    return double.tryParse(trimmed);
  }

  AngularSizeClass _resolveAngularSizeClass(double? maxArcmin) {
    if (maxArcmin == null) {
      return AngularSizeClass.medium;
    }
    if (maxArcmin < 5) return AngularSizeClass.verySmall;
    if (maxArcmin < 15) return AngularSizeClass.small;
    if (maxArcmin < 45) return AngularSizeClass.medium;
    if (maxArcmin < 90) return AngularSizeClass.large;
    return AngularSizeClass.veryLarge;
  }

  SurfaceBrightnessClass _inferSurfaceBrightness({
    required ObjectType objectType,
    required double? magnitude,
    required double? maxArcmin,
    required double? estimatedSurfaceBrightness,
  }) {
    final general = _inferGeneralBrightness(
      magnitude: magnitude,
      maxArcmin: maxArcmin,
    );

    return switch (objectType) {
      ObjectType.galaxy => _inferGalaxyBrightness(
        magnitude: magnitude,
        maxArcmin: maxArcmin,
        estimatedSurfaceBrightness: estimatedSurfaceBrightness,
      ),
      ObjectType.planetaryNebula || ObjectType.complexNebula => general.atLeast(
        SurfaceBrightnessClass.bright,
      ),
      ObjectType.nebulaWithCluster => _inferNebulaWithClusterBrightness(
        maxArcmin: maxArcmin,
      ),
      ObjectType.supernovaRemnant => general.atLeast(
        SurfaceBrightnessClass.dim,
      ),
      ObjectType.emissionNebula => _inferEmissionNebulaBrightness(
        general: general,
        magnitude: magnitude,
      ),
      ObjectType.openCluster => _inferOpenClusterBrightness(
        magnitude: magnitude,
      ),
      ObjectType.globularCluster => _inferGlobularClusterBrightness(
        magnitude: magnitude,
      ),
      _ => general,
    };
  }

  SurfaceBrightnessClass _inferGeneralBrightness({
    required double? magnitude,
    required double? maxArcmin,
  }) {
    if (maxArcmin != null) {
      if (maxArcmin >= 180) {
        return SurfaceBrightnessClass.extremeDim;
      }
      if (maxArcmin >= 120) {
        return SurfaceBrightnessClass.veryDim;
      }
      if (maxArcmin >= 90) {
        return SurfaceBrightnessClass.dim;
      }
    }

    if (magnitude != null) {
      if (magnitude <= 6.5) {
        return SurfaceBrightnessClass.bright;
      }
      if (magnitude <= 7.5) {
        return SurfaceBrightnessClass.normal;
      }
      if (magnitude <= 8.0) {
        return SurfaceBrightnessClass.dim;
      }
      return SurfaceBrightnessClass.veryDim;
    }

    return SurfaceBrightnessClass.normal;
  }

  SurfaceBrightnessClass _inferEmissionNebulaBrightness({
    required SurfaceBrightnessClass general,
    required double? magnitude,
  }) {
    if (magnitude != null && magnitude <= 4.0) {
      return SurfaceBrightnessClass.veryBright;
    }
    if (magnitude != null && magnitude <= 6.5) {
      return SurfaceBrightnessClass.bright;
    }
    return general;
  }

  SurfaceBrightnessClass _inferGalaxyBrightness({
    required double? magnitude,
    required double? maxArcmin,
    required double? estimatedSurfaceBrightness,
  }) {
    if (estimatedSurfaceBrightness != null) {
      if (estimatedSurfaceBrightness < 20.5) {
        return SurfaceBrightnessClass.veryBright;
      }
      if (estimatedSurfaceBrightness < 22.5) {
        return SurfaceBrightnessClass.bright;
      }
      if (estimatedSurfaceBrightness < 23.0) {
        return SurfaceBrightnessClass.normal;
      }
      if (estimatedSurfaceBrightness < 23.7) {
        return SurfaceBrightnessClass.dim;
      }
      if (estimatedSurfaceBrightness < 24.5) {
        return SurfaceBrightnessClass.veryDim;
      }
      return SurfaceBrightnessClass.extremeDim;
    }

    // Catalogs without enough photometry retain the previous magnitude-only
    // fallback instead of being treated as confidently low surface brightness.
    if (magnitude == null) {
      return SurfaceBrightnessClass.normal;
    }
    if (magnitude <= 5.5) {
      return SurfaceBrightnessClass.bright;
    }
    if (magnitude >= 7.6 && magnitude <= 8.0) {
      return SurfaceBrightnessClass.dim;
    }
    if (magnitude > 8.0 && magnitude <= 8.5) {
      return SurfaceBrightnessClass.normal;
    }
    if (magnitude > 8.5) {
      return SurfaceBrightnessClass.dim;
    }
    return SurfaceBrightnessClass.normal;
  }

  SurfaceBrightnessClass _inferNebulaWithClusterBrightness({
    required double? maxArcmin,
  }) {
    if (maxArcmin != null && maxArcmin >= 90) {
      return SurfaceBrightnessClass.dim;
    }
    return SurfaceBrightnessClass.normal;
  }

  SurfaceBrightnessClass _inferOpenClusterBrightness({
    required double? magnitude,
  }) {
    if (magnitude != null && magnitude <= 4.0) {
      return SurfaceBrightnessClass.veryBright;
    }
    if (magnitude != null && magnitude <= 6.5) {
      return SurfaceBrightnessClass.bright;
    }
    return SurfaceBrightnessClass.normal;
  }

  SurfaceBrightnessClass _inferGlobularClusterBrightness({
    required double? magnitude,
  }) {
    if (magnitude != null && magnitude <= 6.5) {
      return SurfaceBrightnessClass.bright;
    }
    if (magnitude != null && magnitude <= 8.0) {
      return SurfaceBrightnessClass.normal;
    }
    return SurfaceBrightnessClass.dim;
  }

  ImagingDifficulty _inferImagingDifficulty({
    required ObjectType objectType,
    required SurfaceBrightnessClass brightness,
  }) {
    final fromBrightness = switch (brightness) {
      SurfaceBrightnessClass.veryBright => ImagingDifficulty.veryEasy,
      SurfaceBrightnessClass.bright => ImagingDifficulty.easy,
      SurfaceBrightnessClass.normal => ImagingDifficulty.normal,
      SurfaceBrightnessClass.dim => ImagingDifficulty.normal,
      SurfaceBrightnessClass.veryDim => ImagingDifficulty.hard,
      SurfaceBrightnessClass.extremeDim => ImagingDifficulty.hard,
    };

    return switch (objectType) {
      ObjectType.galaxy when brightness == SurfaceBrightnessClass.dim =>
        ImagingDifficulty.normal,
      ObjectType.supernovaRemnant => fromBrightness.atLeast(
        ImagingDifficulty.hard,
      ),
      ObjectType.emissionNebula ||
      ObjectType.complexNebula ||
      ObjectType.planetaryNebula ||
      ObjectType.openCluster ||
      ObjectType.globularCluster => fromBrightness.atMost(
        ImagingDifficulty.easy,
      ),
      _ => fromBrightness,
    };
  }
}

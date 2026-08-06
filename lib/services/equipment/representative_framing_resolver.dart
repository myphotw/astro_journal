import '../../core/constants/angular_size_class.dart';
import '../../core/constants/catalog_object_metadata_overrides.dart';
import '../../data/models/catalog_object.dart';
import '../../data/models/representative_framing_size.dart';
import '../object_imaging_profile_provider.dart';
import 'angular_size_parser.dart';

/// 장비 추천 전용 대표 프레이밍 크기 (Catalog angular_size와 분리).
class RepresentativeFramingResolver {
  const RepresentativeFramingResolver({
    ObjectImagingProfileProvider? profileProvider,
  }) : _profileProvider =
            profileProvider ?? const ObjectImagingProfileProvider();

  final ObjectImagingProfileProvider _profileProvider;

  RepresentativeFramingSize resolve(CatalogObject object) {
    final overrideRaw = _overrideRaw(object);
    RepresentativeFramingSize? resolved;
    if (overrideRaw != null) {
      resolved = AngularSizeParser.parse(overrideRaw);
    }

    resolved ??= AngularSizeParser.parse(object.angularSize);

    if (resolved == null) {
      final profile = _profileProvider.profileFor(object);
      resolved = RepresentativeFramingSize.squareDegrees(
        _degreesForClass(profile.angularSizeClass),
      );
    }

    return _withPositionAngle(object, resolved);
  }

  RepresentativeFramingSize _withPositionAngle(
    CatalogObject object,
    RepresentativeFramingSize size,
  ) {
    final pa = CatalogObjectMetadataOverrides.positionAngleDegreesForId(
          object.displayName,
        ) ??
        CatalogObjectMetadataOverrides.positionAngleDegreesForId(object.id);
    if (pa == null) return size;
    return RepresentativeFramingSize(
      widthArcmin: size.widthArcmin,
      heightArcmin: size.heightArcmin,
      positionAngleDegrees: pa,
    );
  }

  String? _overrideRaw(CatalogObject object) {
    return CatalogObjectMetadataOverrides.representativeFramingOverrideForId(
          object.displayName,
        ) ??
        CatalogObjectMetadataOverrides.representativeFramingOverrideForId(
          object.id,
        );
  }

  double _degreesForClass(AngularSizeClass sizeClass) {
    return switch (sizeClass) {
      AngularSizeClass.verySmall => 0.05,
      AngularSizeClass.small => 0.17,
      AngularSizeClass.medium => 0.375,
      AngularSizeClass.large => 0.75,
      AngularSizeClass.veryLarge => 1.5,
    };
  }
}

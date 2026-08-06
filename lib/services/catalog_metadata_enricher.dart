import '../core/constants/angular_size_class.dart';
import '../core/constants/catalog_object_metadata_overrides.dart';
import '../core/constants/catalog_type.dart';
import '../core/constants/constellation_names.dart';
import '../data/models/catalog_object.dart';
import 'object_imaging_profile_provider.dart';
import 'season_planner_service.dart';

/// 천체 카탈로그 메타데이터(계절·크기·설명)를 계산해 DB 저장용으로 보강한다.
class CatalogMetadataEnricher {
  const CatalogMetadataEnricher({
    SeasonPlannerService? seasonPlannerService,
    ObjectImagingProfileProvider? imagingProfileProvider,
  })  : _seasonPlannerService = seasonPlannerService ?? const SeasonPlannerService(),
        _imagingProfileProvider =
            imagingProfileProvider ?? const ObjectImagingProfileProvider();

  final SeasonPlannerService _seasonPlannerService;
  final ObjectImagingProfileProvider _imagingProfileProvider;

  CatalogObject enrich(CatalogObject object) {
    final override = CatalogObjectMetadataOverrides.forId(object.displayName) ??
        CatalogObjectMetadataOverrides.forId(object.id);

    final seasonFields = _seasonPlannerService.computeSeasonFields(object);
    final angularSize = override?.angularSize ?? _deriveAngularSize(object);
    final description = override?.description ?? _deriveDescription(object);

    return object.copyWith(
      peakMonth: seasonFields?.peakMonth,
      bestSeason: seasonFields?.label,
      angularSize: angularSize,
      description: description,
    );
  }

  String? _deriveAngularSize(CatalogObject object) {
    if (object.catalog == CatalogType.solar ||
        object.catalog == CatalogType.milky) {
      return null;
    }

    final profile = _imagingProfileProvider.profileFor(object);
    return switch (profile.angularSizeClass) {
      AngularSizeClass.verySmall => "약 5' 미만",
      AngularSizeClass.small => "약 5'~15'",
      AngularSizeClass.medium => "약 15'~30'",
      AngularSizeClass.large => "약 30'~1°",
      AngularSizeClass.veryLarge => "약 1° 이상",
    };
  }

  String? _deriveDescription(CatalogObject object) {
    final type = object.displayType;
    final name = object.displayCommonName;
    final constellation = ConstellationNames.normalize(object.constellation);

    if (constellation.isNotEmpty && constellation != '-') {
      if (name == object.displayName || name == type) {
        return '$constellation에 위치한 $type.';
      }
      return '$constellation에 위치한 $type. $name.';
    }

    if (name.isNotEmpty && name != '-') {
      return '$type · $name.';
    }

    return type.isNotEmpty && type != '-' ? '$type.' : null;
  }
}

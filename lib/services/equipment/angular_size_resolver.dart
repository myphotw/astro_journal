import '../../core/constants/angular_size_class.dart';
import '../../data/models/catalog_object.dart';
import '../object_imaging_profile_provider.dart';

/// 천체 시각 크기를 도(°) 단위로 변환한다.
class AngularSizeResolver {
  const AngularSizeResolver({
    ObjectImagingProfileProvider? profileProvider,
  }) : _profileProvider =
            profileProvider ?? const ObjectImagingProfileProvider();

  final ObjectImagingProfileProvider _profileProvider;

  double resolveDegrees(CatalogObject object) {
    final parsed = _parseAngularSizeString(object.angularSize);
    if (parsed != null) {
      return parsed;
    }

    final profile = _profileProvider.profileFor(object);
    return _degreesForClass(profile.angularSizeClass);
  }

  double? _parseAngularSizeString(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;

    final arcminMatch = RegExp(r"(\d+(?:\.\d+)?)\s*'").firstMatch(raw);
    if (arcminMatch != null) {
      final arcmin = double.tryParse(arcminMatch.group(1)!);
      if (arcmin != null) {
        return arcmin / 60.0;
      }
    }

    final degreeMatch = RegExp(r'(\d+(?:\.\d+)?)\s*°').firstMatch(raw);
    if (degreeMatch != null) {
      return double.tryParse(degreeMatch.group(1)!);
    }

    return null;
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

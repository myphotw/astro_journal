import '../core/constants/object_imaging_profile_defaults.dart';
import '../core/constants/object_type.dart';
import '../data/models/catalog_object.dart';
import '../data/models/object_imaging_profile.dart';
import 'imaging_profile_resolver.dart';

/// Resolves imaging profiles from catalog metadata without changing the DB schema.
class ObjectImagingProfileProvider {
  const ObjectImagingProfileProvider({
    ImagingProfileResolver? resolver,
  }) : _resolver = resolver ?? const ImagingProfileResolver();

  final ImagingProfileResolver _resolver;

  ObjectImagingProfile profileFor(CatalogObject object) {
    final resolvedType = _resolveImagingType(object);
    return _resolver.resolve(object, resolvedType);
  }

  ObjectType _resolveImagingType(CatalogObject object) {
    final resolved = object.resolvedObjectType;
    if (resolved != ObjectType.other) {
      return resolved;
    }

    for (final tag in object.tags) {
      final fromTag = ObjectType.fromLabel(tag);
      if (fromTag != ObjectType.other) {
        return fromTag;
      }
    }

    final name = object.name.toLowerCase();
    if (name.contains('milky') || name.contains('은하수')) {
      return ObjectType.milkyWay;
    }

    return ObjectType.other;
  }

  /// Type-only template without catalog metadata inference.
  ObjectImagingProfile templateForType(ObjectType type) {
    return ObjectImagingProfileDefaults.forType(type);
  }
}

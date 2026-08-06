import '../../data/models/object_imaging_profile.dart';

/// Intentionally empty.
///
/// Profile tuning is done via [ObjectImagingProfileDefaults] to keep
/// catalog-wide consistency without per-object exceptions.
abstract final class ObjectImagingProfileOverrides {
  static ObjectImagingProfile? forCatalogId(String catalogId) => null;
}

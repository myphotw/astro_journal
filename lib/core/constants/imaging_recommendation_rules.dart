import 'object_type.dart';

/// Temporary recommendation thresholds for profile-aware exposure policy.
abstract final class ImagingRecommendationRules {
  static const int seoulBortle = 9;

  static const int darkNebulaMaxBortle = 6;
  static const int narrowbandReliefMaxBortle = 9;

  static const int galaxyHighBortleExposureBonusMinutes = 12;

  static bool isTypeExcludedAtBortle(ObjectType objectType, int bortle) {
    if (objectType == ObjectType.darkNebula &&
        bortle >= darkNebulaMaxBortle) {
      return true;
    }
    if (objectType == ObjectType.milkyWay && bortle >= 7) {
      return true;
    }
    return false;
  }
}

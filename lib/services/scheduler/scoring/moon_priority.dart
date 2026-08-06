import '../../../core/constants/object_type.dart';
import '../../../data/models/object_imaging_profile.dart';

/// Prioritizes targets that should be shot before lunar interference rises.
class MoonPriority {
  const MoonPriority();

  static const _highPriorityTypes = {
    ObjectType.reflectionNebula,
    ObjectType.darkNebula,
    ObjectType.galaxy,
    ObjectType.galaxyGroup,
  };

  static const _lowPriorityTypes = {
    ObjectType.emissionNebula,
    ObjectType.planetaryNebula,
    ObjectType.supernovaRemnant,
  };

  double calculate({
    required ObjectImagingProfile profile,
    required int moonSafeMinutes,
  }) {
    var score = 50.0;

    if (_highPriorityTypes.contains(profile.objectType)) {
      score += 25;
    } else if (_lowPriorityTypes.contains(profile.objectType)) {
      score -= 15;
    }

    if (moonSafeMinutes <= 60) {
      score += 20;
    } else if (moonSafeMinutes <= 120) {
      score += 10;
    }

    return score.clamp(0.0, 100.0);
  }
}

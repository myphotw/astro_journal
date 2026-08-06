import '../../core/constants/moon_separation_weights.dart';
import '../../data/models/catalog_object.dart';
import '../../data/models/observation_context.dart';
import '../celestial_position_service.dart';

/// Scores lunar interference for a target at a specific evaluation time.
class MoonScore {
  const MoonScore();

  double calculate({
    required CatalogObject object,
    required ObservationContext context,
    required CelestialPositionService positionService,
    required DateTime evaluationTime,
  }) {
    final raHours = CelestialPositionService.parseRaHours(object.ra);
    final decDeg = CelestialPositionService.parseDecDeg(object.dec);
    final moonCoords = positionService.getMoonEquatorial(evaluationTime);
    final separation = CelestialPositionService.angularSeparationDeg(
      ra1Hours: raHours,
      dec1Deg: decDeg,
      ra2Hours: moonCoords.raHours,
      dec2Deg: moonCoords.decDeg,
    );

    final moonIllumBonus =
        (1 - context.moonIllumination.clamp(0.0, 1.0)) * 50.0;
    final separationBonus = (separation / 120.0 * 50.0).clamp(0.0, 50.0);
    final separationPenalty =
        MoonSeparationWeights.penaltyForSeparation(separation);

    return (moonIllumBonus + separationBonus + separationPenalty)
        .clamp(0.0, 100.0);
  }
}

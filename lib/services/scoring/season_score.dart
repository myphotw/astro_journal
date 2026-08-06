import 'dart:math' as math;

import '../../data/models/catalog_object.dart';
import '../../data/models/observation_context.dart';
import '../celestial_position_service.dart';

/// Scores seasonal suitability from right ascension vs month.
class SeasonScore {
  const SeasonScore();

  static const _optimalRaByMonth = [7, 9, 11, 13, 15, 17, 19, 21, 23, 1, 3, 5];

  double calculate({
    required CatalogObject object,
    required ObservationContext context,
  }) {
    final month = context.currentTime.month;
    final optimalRa = _optimalRaByMonth[month - 1].toDouble();
    final raHours = CelestialPositionService.parseRaHours(object.ra);
    final dist = _raDistance(optimalRa, raHours);
    return (math.max(0.0, 1 - dist / 12.0) * 100.0).clamp(0.0, 100.0);
  }

  double _raDistance(double ra1, double ra2) {
    var diff = (ra1 - ra2).abs();
    if (diff > 12) diff = 24 - diff;
    return diff;
  }
}

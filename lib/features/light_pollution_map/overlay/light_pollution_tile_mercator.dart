import 'dart:math' as math;

/// Web Mercator helpers for Google Maps tile coordinates.
class LightPollutionTileMercator {
  LightPollutionTileMercator._();

  static double tileXToLng(int x, int z, [double offset = 0]) {
    return (x + offset) / math.pow(2, z) * 360.0 - 180.0;
  }

  static double tileYToLat(int y, int z, [double offset = 0]) {
    final n = math.pi - 2.0 * math.pi * (y + offset) / math.pow(2, z);
    return 180.0 / math.pi * math.atan(0.5 * (math.exp(n) - math.exp(-n)));
  }

  static ({
    double north,
    double south,
    double west,
    double east,
  }) tileBounds(int x, int y, int z) {
    return (
      north: tileYToLat(y, z),
      south: tileYToLat(y + 1, z),
      west: tileXToLng(x, z),
      east: tileXToLng(x + 1, z),
    );
  }
}

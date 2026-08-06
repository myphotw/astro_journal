/// Moon–target angular separation (degrees) score penalties for recommendation v2.1.
abstract final class MoonSeparationWeights {
  static const double tier1Max = 20;
  static const double tier2Max = 40;
  static const double tier3Max = 60;
  static const double tier4Max = 90;

  static const double tier1Penalty = -40;
  static const double tier2Penalty = -25;
  static const double tier3Penalty = -15;
  static const double tier4Penalty = -5;

  /// Returns a non-positive score adjustment for [separationDeg] (0–180°).
  static double penaltyForSeparation(double separationDeg) {
    final sep = separationDeg.clamp(0.0, 180.0);
    if (sep < tier1Max) return tier1Penalty;
    if (sep < tier2Max) return tier2Penalty;
    if (sep < tier3Max) return tier3Penalty;
    if (sep < tier4Max) return tier4Penalty;
    return 0;
  }
}

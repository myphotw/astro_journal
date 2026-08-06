/// Imaging difficulty tier used by exposure and recommendation logic.
enum ImagingDifficulty {
  veryEasy,
  easy,
  normal,
  hard,
  veryHard,
  extreme,
}

extension ImagingDifficultyExposure on ImagingDifficulty {
  double get exposureMultiplier => switch (this) {
        ImagingDifficulty.veryEasy => 0.75,
        ImagingDifficulty.easy => 0.88,
        ImagingDifficulty.normal => 1.0,
        ImagingDifficulty.hard => 1.15,
        ImagingDifficulty.veryHard => 1.30,
        ImagingDifficulty.extreme => 1.50,
      };
}

extension ImagingDifficultyOrdering on ImagingDifficulty {
  int get tierIndex => ImagingDifficulty.values.indexOf(this);

  ImagingDifficulty atLeast(ImagingDifficulty minimum) {
    return tierIndex >= minimum.tierIndex ? this : minimum;
  }

  ImagingDifficulty atMost(ImagingDifficulty maximum) {
    return tierIndex <= maximum.tierIndex ? this : maximum;
  }
}

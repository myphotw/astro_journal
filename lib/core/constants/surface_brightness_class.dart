/// Surface-brightness class for imaging (not visual magnitude).
enum SurfaceBrightnessClass {
  veryBright,
  bright,
  normal,
  dim,
  veryDim,
  extremeDim,
}

extension SurfaceBrightnessClassExposure on SurfaceBrightnessClass {
  /// Baseline integration minutes before Bortle gap and difficulty adjustments.
  int get baseExposureMinutes => switch (this) {
        SurfaceBrightnessClass.veryBright => 20,
        SurfaceBrightnessClass.bright => 30,
        SurfaceBrightnessClass.normal => 45,
        SurfaceBrightnessClass.dim => 60,
        SurfaceBrightnessClass.veryDim => 75,
        SurfaceBrightnessClass.extremeDim => 90,
      };

  int get lightPollutionPenaltyMinutes => switch (this) {
        SurfaceBrightnessClass.veryBright => 0,
        SurfaceBrightnessClass.bright => 3,
        SurfaceBrightnessClass.normal => 8,
        SurfaceBrightnessClass.dim => 12,
        SurfaceBrightnessClass.veryDim => 18,
        SurfaceBrightnessClass.extremeDim => 25,
      };

  double get lightPollutionScorePenalty => switch (this) {
        SurfaceBrightnessClass.veryBright => 0,
        SurfaceBrightnessClass.bright => 3,
        SurfaceBrightnessClass.normal => 8,
        SurfaceBrightnessClass.dim => 12,
        SurfaceBrightnessClass.veryDim => 18,
        SurfaceBrightnessClass.extremeDim => 25,
      };
}

extension SurfaceBrightnessClassOrdering on SurfaceBrightnessClass {
  int get tierIndex => SurfaceBrightnessClass.values.indexOf(this);

  /// Ensures the class is not dimmer than [minimumBrightness].
  SurfaceBrightnessClass atLeast(SurfaceBrightnessClass minimumBrightness) {
    return tierIndex <= minimumBrightness.tierIndex ? this : minimumBrightness;
  }

  /// Ensures the class is not brighter than [maximumBrightness].
  SurfaceBrightnessClass atMost(SurfaceBrightnessClass maximumBrightness) {
    return tierIndex >= maximumBrightness.tierIndex
        ? this
        : maximumBrightness;
  }
}

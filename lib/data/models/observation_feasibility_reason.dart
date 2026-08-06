/// Why a slot is not feasible for observation/imaging.
enum ObservationFeasibilityReason {
  rainVolume('강수량'),
  cloudTooHigh('구름량'),
  rainProbability('강수 확률'),
  visibilityTooLow('가시거리'),
  windTooStrong('풍속'),
  belowMinAltitude('최소 고도 미만'),
  aboveMaxAltitude('최대 고도 초과'),
  outsideAzimuth('방위각 범위 밖'),
  lightPollution('광해'),
  belowHorizon('지평선 아래');

  const ObservationFeasibilityReason(this.label);
  final String label;
}

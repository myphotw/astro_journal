/// Site observation environment derived from GPS and light-pollution data.
///
/// Pipeline: atlas brightness (mcd/m²) → sqm → bortle → observationScore.
class ObservationCondition {
  const ObservationCondition({
    required this.latitude,
    required this.longitude,
    required this.createdAt,
    this.row,
    this.col,
    this.brightness,
    this.sqm,
    this.bortle,
    this.observationScore,
  });

  final double latitude;
  final double longitude;
  final int? row;
  final int? col;
  final double? brightness;
  final DateTime createdAt;

  /// Predicted sky quality (mag/arcsec²) from atlas brightness.
  final double? sqm;

  /// Bortle scale (1–9, 9 = inner city).
  final int? bortle;

  /// Site light-pollution observation score (0–100).
  final double? observationScore;

  bool get hasBrightnessData => brightness != null;
}

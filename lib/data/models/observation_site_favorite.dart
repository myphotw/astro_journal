import '../../core/constants/database_constants.dart';

class ObservationSiteFavorite {
  const ObservationSiteFavorite({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.bortle,
    this.sqm,
    this.brightnessGrade,
    required this.createdAt,
  });

  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final int? bortle;
  final double? sqm;
  final String? brightnessGrade;
  final DateTime createdAt;

  Map<String, dynamic> toMap() {
    return {
      DatabaseConstants.colId: id,
      DatabaseConstants.colName: name,
      DatabaseConstants.colLatitude: latitude,
      DatabaseConstants.colLongitude: longitude,
      DatabaseConstants.colBortle: bortle,
      DatabaseConstants.colSqm: sqm,
      DatabaseConstants.colBrightnessGrade: brightnessGrade,
      DatabaseConstants.colCreatedAt: createdAt.toIso8601String(),
    };
  }

  factory ObservationSiteFavorite.fromMap(Map<String, dynamic> map) {
    return ObservationSiteFavorite(
      id: map[DatabaseConstants.colId] as String,
      name: map[DatabaseConstants.colName] as String,
      latitude: (map[DatabaseConstants.colLatitude] as num).toDouble(),
      longitude: (map[DatabaseConstants.colLongitude] as num).toDouble(),
      bortle: map[DatabaseConstants.colBortle] as int?,
      sqm: (map[DatabaseConstants.colSqm] as num?)?.toDouble(),
      brightnessGrade: map[DatabaseConstants.colBrightnessGrade] as String?,
      createdAt: DateTime.parse(map[DatabaseConstants.colCreatedAt] as String),
    );
  }
}

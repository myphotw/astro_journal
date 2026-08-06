import '../../core/constants/database_constants.dart';

class Eyepiece {
  const Eyepiece({
    required this.id,
    required this.equipmentId,
    required this.name,
    required this.focalLengthMm,
    required this.afovDegrees,
    this.sortOrder = 0,
  });

  final String id;
  final String equipmentId;
  final String name;
  final double focalLengthMm;
  final double afovDegrees;
  final int sortOrder;

  Map<String, dynamic> toMap() {
    return {
      DatabaseConstants.colId: id,
      DatabaseConstants.colEquipmentId: equipmentId,
      DatabaseConstants.colName: name,
      DatabaseConstants.colFocalLengthMm: focalLengthMm,
      DatabaseConstants.colAfovDegrees: afovDegrees,
      DatabaseConstants.colSortOrder: sortOrder,
    };
  }

  factory Eyepiece.fromMap(Map<String, dynamic> map) {
    return Eyepiece(
      id: map[DatabaseConstants.colId] as String,
      equipmentId: map[DatabaseConstants.colEquipmentId] as String,
      name: map[DatabaseConstants.colName] as String,
      focalLengthMm: (map[DatabaseConstants.colFocalLengthMm] as num).toDouble(),
      afovDegrees: (map[DatabaseConstants.colAfovDegrees] as num).toDouble(),
      sortOrder: map[DatabaseConstants.colSortOrder] as int? ?? 0,
    );
  }

  Eyepiece copyWith({
    String? id,
    String? equipmentId,
    String? name,
    double? focalLengthMm,
    double? afovDegrees,
    int? sortOrder,
  }) {
    return Eyepiece(
      id: id ?? this.id,
      equipmentId: equipmentId ?? this.equipmentId,
      name: name ?? this.name,
      focalLengthMm: focalLengthMm ?? this.focalLengthMm,
      afovDegrees: afovDegrees ?? this.afovDegrees,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}

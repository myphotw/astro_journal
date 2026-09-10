enum MultiNightFramingBranch { rising, setting }

class MultiNightFramingReference {
  const MultiNightFramingReference({
    required this.id,
    required this.catalogObjectId,
    required this.referenceCapturedAt,
    required this.siteId,
    required this.equipmentId,
    required this.referenceHourAngleDeg,
    required this.referenceParallacticAngleDeg,
    required this.referenceBranch,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String catalogObjectId;
  final DateTime referenceCapturedAt;
  final String siteId;
  final String equipmentId;
  final double referenceHourAngleDeg;
  final double referenceParallacticAngleDeg;
  final MultiNightFramingBranch referenceBranch;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;

  factory MultiNightFramingReference.fromJson(Map<String, dynamic> json) =>
      MultiNightFramingReference(
        id: _requiredString(json, 'id'),
        catalogObjectId: _requiredString(json, 'catalog_object_id'),
        referenceCapturedAt: _requiredDate(json, 'reference_captured_at'),
        siteId: _requiredString(json, 'site_id'),
        equipmentId: _requiredString(json, 'equipment_id'),
        referenceHourAngleDeg: _requiredDouble(
          json,
          'reference_hour_angle_deg',
        ),
        referenceParallacticAngleDeg: _requiredDouble(
          json,
          'reference_parallactic_angle_deg',
        ),
        referenceBranch: MultiNightFramingBranch.values.firstWhere(
          (value) => value.name == _requiredString(json, 'reference_branch'),
          orElse: () =>
              throw const FormatException('reference_branch is invalid.'),
        ),
        revision: _requiredInt(json, 'revision'),
        createdAt: _requiredDate(json, 'created_at'),
        updatedAt: _requiredDate(json, 'updated_at'),
        deletedAt: _optionalDate(json['deleted_at']),
      );

  factory MultiNightFramingReference.fromMap(Map<String, Object?> map) =>
      MultiNightFramingReference(
        id: map['id']! as String,
        catalogObjectId: map['catalog_object_id']! as String,
        referenceCapturedAt: DateTime.parse(
          map['reference_captured_at']! as String,
        ),
        siteId: map['site_id']! as String,
        equipmentId: map['equipment_id']! as String,
        referenceHourAngleDeg: (map['reference_hour_angle_deg']! as num)
            .toDouble(),
        referenceParallacticAngleDeg:
            (map['reference_parallactic_angle_deg']! as num).toDouble(),
        referenceBranch: MultiNightFramingBranch.values.firstWhere(
          (value) => value.name == map['reference_branch'],
        ),
        revision: (map['revision'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.parse(map['created_at']! as String),
        updatedAt: DateTime.parse(map['updated_at']! as String),
        deletedAt: _optionalDate(map['deleted_at']),
      );

  Map<String, Object?> toMap() => {
    'id': id,
    'catalog_object_id': catalogObjectId,
    'reference_captured_at': _timezoneAwareIso8601(referenceCapturedAt),
    'site_id': siteId,
    'equipment_id': equipmentId,
    'reference_hour_angle_deg': referenceHourAngleDeg,
    'reference_parallactic_angle_deg': referenceParallacticAngleDeg,
    'reference_branch': referenceBranch.name,
    'revision': revision,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'deleted_at': deletedAt?.toUtc().toIso8601String(),
  };

  Map<String, Object?> toJson() => Map<String, Object?>.from(toMap());

  Map<String, Object?> toCreateJson() => {
    'id': id,
    'catalog_object_id': catalogObjectId,
    ..._mutableJson(),
  };

  Map<String, Object?> toPatchJson({required int expectedRevision}) => {
    'expected_revision': expectedRevision,
    ..._mutableJson(),
  };

  Map<String, Object?> _mutableJson() => {
    'reference_captured_at': _timezoneAwareIso8601(referenceCapturedAt),
    'site_id': siteId,
    'equipment_id': equipmentId,
    'reference_hour_angle_deg': referenceHourAngleDeg,
    'reference_parallactic_angle_deg': referenceParallacticAngleDeg,
    'reference_branch': referenceBranch.name,
  };

  MultiNightFramingReference copyWith({
    DateTime? referenceCapturedAt,
    String? siteId,
    String? equipmentId,
    double? referenceHourAngleDeg,
    double? referenceParallacticAngleDeg,
    MultiNightFramingBranch? referenceBranch,
    int? revision,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
  }) => MultiNightFramingReference(
    id: id,
    catalogObjectId: catalogObjectId,
    referenceCapturedAt: referenceCapturedAt ?? this.referenceCapturedAt,
    siteId: siteId ?? this.siteId,
    equipmentId: equipmentId ?? this.equipmentId,
    referenceHourAngleDeg: referenceHourAngleDeg ?? this.referenceHourAngleDeg,
    referenceParallacticAngleDeg:
        referenceParallacticAngleDeg ?? this.referenceParallacticAngleDeg,
    referenceBranch: referenceBranch ?? this.referenceBranch,
    revision: revision ?? this.revision,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
  );
}

class MultiNightFramingDeleteResult {
  const MultiNightFramingDeleteResult({
    required this.referenceId,
    required this.revision,
    required this.deletedAt,
  });

  final String referenceId;
  final int revision;
  final DateTime deletedAt;

  factory MultiNightFramingDeleteResult.fromJson(Map<String, dynamic> json) {
    if (json['deleted'] != true) {
      throw const FormatException('Reference delete was not confirmed.');
    }
    return MultiNightFramingDeleteResult(
      referenceId: _requiredString(json, 'reference_id'),
      revision: _requiredInt(json, 'revision'),
      deletedAt: _requiredDate(json, 'deleted_at'),
    );
  }
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$key is missing.');
  }
  return value;
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! num) throw FormatException('$key is missing.');
  return value.toInt();
}

double _requiredDouble(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! num) throw FormatException('$key is missing.');
  return value.toDouble();
}

DateTime _requiredDate(Map<String, dynamic> json, String key) {
  final value = _optionalDate(json[key]);
  if (value == null) throw FormatException('$key is missing.');
  return value;
}

DateTime? _optionalDate(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

String _timezoneAwareIso8601(DateTime value) {
  if (value.isUtc) return value.toIso8601String();
  final offset = value.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final absolute = offset.abs();
  final hours = absolute.inHours.toString().padLeft(2, '0');
  final minutes = (absolute.inMinutes % 60).toString().padLeft(2, '0');
  return '${value.toIso8601String()}$sign$hours:$minutes';
}

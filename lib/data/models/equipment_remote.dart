import '../../core/constants/equipment_kind.dart';
import '../../core/constants/equipment_purpose.dart';
import 'equipment.dart';
import 'equipment_exposure_capability.dart';
import 'eyepiece.dart';

class EquipmentRemoteAggregate {
  const EquipmentRemoteAggregate({
    required this.equipment,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final Equipment equipment;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  factory EquipmentRemoteAggregate.fromJson(Map<String, dynamic> json) {
    final id = _requiredString(json, 'id');
    return EquipmentRemoteAggregate(
      equipment: Equipment(
        id: id,
        name: _requiredString(json, 'name'),
        kind: EquipmentKind.values.firstWhere(
          (value) => value.name == _requiredString(json, 'kind'),
          orElse: () =>
              throw const FormatException('Equipment kind is invalid.'),
        ),
        purpose: EquipmentPurpose.values.firstWhere(
          (value) => value.name == _requiredString(json, 'purpose'),
          orElse: () =>
              throw const FormatException('Equipment purpose is invalid.'),
        ),
        isActive: _requiredBool(json, 'is_active'),
        focalLengthMm: _optionalDouble(json['focal_length_mm']),
        apertureMm: _optionalDouble(json['aperture_mm']),
        fovWidthDegrees: _optionalDouble(json['fov_width_degrees']),
        fovHeightDegrees: _optionalDouble(json['fov_height_degrees']),
        sortOrder: _requiredInt(json, 'sort_order'),
        eyepieces: _requiredList(json, 'eyepieces')
            .map(
              (item) => Eyepiece(
                id: _requiredString(item, 'id'),
                equipmentId: _optionalString(item['equipment_id']) ?? id,
                name: _requiredString(item, 'name'),
                focalLengthMm: _requiredDouble(item, 'focal_length_mm'),
                afovDegrees: _requiredDouble(item, 'afov_degrees'),
                sortOrder: _requiredInt(item, 'sort_order'),
              ),
            )
            .toList(growable: false),
        azExposureCapability: _capability(json['az_exposure_capability']),
        eqExposureCapability: _capability(json['eq_exposure_capability']),
      ),
      revision: _requiredInt(json, 'revision'),
      createdAt: _requiredDate(json, 'created_at'),
      updatedAt: _requiredDate(json, 'updated_at'),
      deletedAt: _optionalDate(json['deleted_at']),
    );
  }

  Map<String, Object?> toJson() => {
    ...toCreateJson(),
    'revision': revision,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'deleted_at': deletedAt?.toUtc().toIso8601String(),
  };

  Map<String, Object?> toCreateJson() => {
    'id': equipment.id,
    ..._mutableJson(),
  };

  Map<String, Object?> toPatchJson({required int expectedRevision}) => {
    'expected_revision': expectedRevision,
    ..._mutableJson(),
  };

  Map<String, Object?> _mutableJson() => {
    'name': equipment.name.trim(),
    'kind': equipment.kind.name,
    'purpose': equipment.purpose.name,
    'is_active': equipment.isActive,
    'focal_length_mm': equipment.focalLengthMm,
    'aperture_mm': equipment.apertureMm,
    'fov_width_degrees': equipment.fovWidthDegrees,
    'fov_height_degrees': equipment.fovHeightDegrees,
    'sort_order': equipment.sortOrder,
    'eyepieces': equipment.eyepieces
        .map(
          (item) => <String, Object?>{
            'id': item.id,
            'equipment_id': equipment.id,
            'name': item.name.trim(),
            'focal_length_mm': item.focalLengthMm,
            'afov_degrees': item.afovDegrees,
            'sort_order': item.sortOrder,
          },
        )
        .toList(growable: false),
    'az_exposure_capability': equipment.azExposureCapability?.toJson(),
    'eq_exposure_capability': equipment.eqExposureCapability?.toJson(),
  };
}

class EquipmentRemoteDeleteResult {
  const EquipmentRemoteDeleteResult({
    required this.equipmentId,
    required this.revision,
    required this.deletedAt,
  });

  final String equipmentId;
  final int revision;
  final DateTime deletedAt;

  factory EquipmentRemoteDeleteResult.fromJson(Map<String, dynamic> json) {
    if (json['deleted'] != true) {
      throw const FormatException('Equipment delete was not confirmed.');
    }
    return EquipmentRemoteDeleteResult(
      equipmentId: _requiredString(json, 'equipment_id'),
      revision: _requiredInt(json, 'revision'),
      deletedAt: _requiredDate(json, 'deleted_at'),
    );
  }
}

EquipmentExposureCapability? _capability(Object? raw) {
  if (raw == null) return null;
  if (raw is! Map) {
    throw const FormatException('Exposure capability must be an object.');
  }
  return EquipmentExposureCapability.fromJson(Map<String, dynamic>.from(raw));
}

List<Map<String, dynamic>> _requiredList(
  Map<String, dynamic> json,
  String key,
) {
  final value = json[key];
  if (value is! List) throw FormatException('$key is missing.');
  return value
      .map((raw) {
        if (raw is! Map) throw FormatException('$key contains a non-object.');
        return Map<String, dynamic>.from(raw);
      })
      .toList(growable: false);
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = _optionalString(json[key]);
  if (value == null) throw FormatException('$key is missing.');
  return value;
}

String? _optionalString(Object? value) {
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty) return null;
  return value;
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! num) throw FormatException('$key is missing.');
  return value.toInt();
}

double _requiredDouble(Map<String, dynamic> json, String key) {
  final value = _optionalDouble(json[key]);
  if (value == null) throw FormatException('$key is missing.');
  return value;
}

double? _optionalDouble(Object? value) =>
    value is num ? value.toDouble() : null;

bool _requiredBool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! bool) throw FormatException('$key is missing.');
  return value;
}

DateTime _requiredDate(Map<String, dynamic> json, String key) {
  final value = _optionalDate(json[key]);
  if (value == null) throw FormatException('$key is missing.');
  return value;
}

DateTime? _optionalDate(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

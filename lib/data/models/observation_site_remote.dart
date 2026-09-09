import 'blocked_azimuth_range.dart';
import 'horizon_point.dart';
import 'imaging_suitability_assessment.dart';
import 'observation_site.dart';

class ObservationSiteRemoteAggregate {
  const ObservationSiteRemoteAggregate({
    required this.site,
    required this.revision,
  });

  final ObservationSite site;
  final int revision;

  factory ObservationSiteRemoteAggregate.fromJson(Map<String, dynamic> json) {
    final id = _requiredString(json, 'id');
    final revision = _requiredInt(json, 'revision');
    final createdAt = _requiredDate(json, 'created_at');
    final updatedAt = _requiredDate(json, 'updated_at');
    final horizon = _requiredList(json, 'horizon_points')
        .map(
          (raw) => HorizonPoint(
            id: _requiredString(raw, 'id'),
            observationSiteId:
                _optionalString(raw['observation_site_id']) ?? id,
            azimuth: _requiredDouble(raw, 'azimuth'),
            minAltitude: _requiredDouble(raw, 'min_altitude'),
            maxAltitude: _optionalDouble(raw['max_altitude']),
            sortOrder: _optionalInt(raw['sort_order']) ?? 0,
            source: HorizonDataSource.fromStorageValue(
              _optionalString(raw['source']),
            ),
          ),
        )
        .toList(growable: false);
    final blocked = _requiredList(json, 'blocked_azimuth_ranges')
        .map(
          (raw) => BlockedAzimuthRange(
            id: _requiredString(raw, 'id'),
            observationSiteId:
                _optionalString(raw['observation_site_id']) ?? id,
            startAzimuth: _requiredDouble(raw, 'start_azimuth'),
            endAzimuth: _requiredDouble(raw, 'end_azimuth'),
            reason: _optionalString(raw['reason']),
            source: HorizonDataSource.fromStorageValue(
              _optionalString(raw['source']),
            ),
          ),
        )
        .toList(growable: false);

    final trackingName = _requiredString(json, 'tracking_mode');
    final trackingMode = TrackingMode.values.firstWhere(
      (value) => value.name == trackingName,
      orElse: () => throw const FormatException(
        'ObservationSite tracking_mode is invalid.',
      ),
    );
    return ObservationSiteRemoteAggregate(
      revision: revision,
      site: ObservationSite(
        id: id,
        name: _requiredString(json, 'name'),
        address: _optionalString(json['address']),
        latitude: _requiredDouble(json, 'latitude'),
        longitude: _requiredDouble(json, 'longitude'),
        bortle: _optionalInt(json['bortle']),
        sqm: _optionalDouble(json['sqm']),
        brightnessGrade: _optionalString(json['brightness_grade']),
        isFavorite: _requiredBool(json, 'is_favorite'),
        trackingMode: trackingMode,
        defaultEquipmentId: _optionalString(json['default_equipment_id']),
        defaultMinAltitude: _requiredDouble(json, 'default_min_altitude'),
        defaultMaxAltitude: _optionalDouble(json['default_max_altitude']),
        preferredStart: _optionalString(json['preferred_start']),
        preferredEnd: _optionalString(json['preferred_end']),
        memo: json['memo'] is String ? json['memo'] as String : '',
        createdAt: createdAt,
        updatedAt: updatedAt,
        deletedAt: _optionalDate(json['deleted_at']),
        horizonPoints: horizon,
        blockedAzimuthRanges: blocked,
      ),
    );
  }

  Map<String, Object?> toJson() => {
    ...toCreateJson(includeDefaultEquipmentId: true),
    'revision': revision,
    'created_at': site.createdAt.toUtc().toIso8601String(),
    'updated_at': site.updatedAt.toUtc().toIso8601String(),
    'deleted_at': site.deletedAt?.toUtc().toIso8601String(),
  };

  Map<String, Object?> toCreateJson({bool includeDefaultEquipmentId = false}) =>
      _mutableJson(
        includeId: true,
        includeDefaultEquipmentId: includeDefaultEquipmentId,
      );

  Map<String, Object?> toPatchJson({
    required int expectedRevision,
    bool includeDefaultEquipmentId = false,
  }) => {
    'expected_revision': expectedRevision,
    ..._mutableJson(
      includeId: false,
      includeDefaultEquipmentId: includeDefaultEquipmentId,
    ),
  };

  Map<String, Object?> _mutableJson({
    required bool includeId,
    required bool includeDefaultEquipmentId,
  }) => {
    if (includeId) 'id': site.id,
    'name': site.name.trim(),
    'latitude': site.latitude,
    'longitude': site.longitude,
    'address': site.address?.trim(),
    'bortle': site.bortle,
    'sqm': site.sqm,
    'brightness_grade': site.brightnessGrade?.trim(),
    'is_favorite': site.isFavorite,
    'tracking_mode': site.trackingMode.name,
    if (includeDefaultEquipmentId)
      'default_equipment_id': site.defaultEquipmentId,
    'default_min_altitude': site.defaultMinAltitude,
    'default_max_altitude': site.defaultMaxAltitude,
    'preferred_start': site.preferredStart,
    'preferred_end': site.preferredEnd,
    'memo': site.memo,
    'horizon_points': site.horizonPoints
        .map(
          (point) => <String, Object?>{
            'id': point.id,
            'observation_site_id': site.id,
            'azimuth': point.azimuth,
            'min_altitude': point.minAltitude,
            'max_altitude': point.maxAltitude,
            'sort_order': point.sortOrder,
            'source': point.source.storageValue,
          },
        )
        .toList(growable: false),
    'blocked_azimuth_ranges': site.blockedAzimuthRanges
        .map(
          (range) => <String, Object?>{
            'id': range.id,
            'observation_site_id': site.id,
            'start_azimuth': range.startAzimuth,
            'end_azimuth': range.endAzimuth,
            'reason': range.reason,
            'source': range.source.storageValue,
          },
        )
        .toList(growable: false),
  };
}

class ObservationSiteRemoteDeleteResult {
  const ObservationSiteRemoteDeleteResult({
    required this.siteId,
    required this.revision,
    required this.deletedAt,
  });

  final String siteId;
  final int revision;
  final DateTime deletedAt;

  factory ObservationSiteRemoteDeleteResult.fromJson(
    Map<String, dynamic> json,
  ) {
    if (json['deleted'] != true) {
      throw const FormatException('ObservationSite delete was not confirmed.');
    }
    return ObservationSiteRemoteDeleteResult(
      siteId: _requiredString(json, 'site_id'),
      revision: _requiredInt(json, 'revision'),
      deletedAt: _requiredDate(json, 'deleted_at'),
    );
  }
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
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = _optionalInt(json[key]);
  if (value == null) throw FormatException('$key is missing.');
  return value;
}

int? _optionalInt(Object? value) => value is num ? value.toInt() : null;

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

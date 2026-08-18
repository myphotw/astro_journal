import 'blocked_azimuth_range.dart';
import 'horizon_point.dart';
import 'imaging_suitability_assessment.dart';

class ObservationSite {
  const ObservationSite({
    required this.id,
    required this.name,
    this.address,
    required this.latitude,
    required this.longitude,
    this.bortle,
    this.sqm,
    this.brightnessGrade,
    this.isFavorite = true,
    this.trackingMode = TrackingMode.altAz,
    this.defaultEquipmentId,
    this.defaultMinAltitude = 20,
    this.defaultMaxAltitude,
    this.preferredStart,
    this.preferredEnd,
    this.memo = '',
    required this.createdAt,
    required this.updatedAt,
    this.lastUsedAt,
    this.deletedAt,
    this.horizonPoints = const [],
    this.blockedAzimuthRanges = const [],
  });

  final String id;
  final String name;
  final String? address;
  final double latitude;
  final double longitude;
  final int? bortle;
  final double? sqm;
  final String? brightnessGrade;
  final bool isFavorite;
  final TrackingMode trackingMode;
  final String? defaultEquipmentId;
  final double defaultMinAltitude;
  final double? defaultMaxAltitude;

  /// Local wall-clock HH:mm. Site timezone support is deferred.
  final String? preferredStart;
  final String? preferredEnd;
  final String memo;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastUsedAt;
  final DateTime? deletedAt;
  final List<HorizonPoint> horizonPoints;
  final List<BlockedAzimuthRange> blockedAzimuthRanges;

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name.trim(),
    'address': address?.trim(),
    'latitude': latitude,
    'longitude': longitude,
    'bortle': bortle,
    'sqm': sqm,
    'brightness_grade': brightnessGrade,
    'is_favorite': isFavorite ? 1 : 0,
    'tracking_mode': trackingMode.name,
    'default_equipment_id': defaultEquipmentId,
    'default_min_altitude': defaultMinAltitude,
    'default_max_altitude': defaultMaxAltitude,
    'preferred_start': preferredStart,
    'preferred_end': preferredEnd,
    'memo': memo,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'last_used_at': lastUsedAt?.toIso8601String(),
    'deleted_at': deletedAt?.toIso8601String(),
  };

  factory ObservationSite.fromMap(
    Map<String, Object?> map, {
    List<HorizonPoint> horizonPoints = const [],
    List<BlockedAzimuthRange> blockedAzimuthRanges = const [],
  }) {
    return ObservationSite(
      id: map['id']! as String,
      name: map['name']! as String,
      address: map['address'] as String?,
      latitude: (map['latitude']! as num).toDouble(),
      longitude: (map['longitude']! as num).toDouble(),
      bortle: map['bortle'] as int?,
      sqm: (map['sqm'] as num?)?.toDouble(),
      brightnessGrade: map['brightness_grade'] as String?,
      isFavorite: (map['is_favorite'] as int? ?? 1) == 1,
      trackingMode: TrackingMode.values.firstWhere(
        (mode) => mode.name == map['tracking_mode'],
        orElse: () => TrackingMode.altAz,
      ),
      defaultEquipmentId: map['default_equipment_id'] as String?,
      defaultMinAltitude: (map['default_min_altitude'] as num? ?? 20)
          .toDouble(),
      defaultMaxAltitude: (map['default_max_altitude'] as num?)?.toDouble(),
      preferredStart: map['preferred_start'] as String?,
      preferredEnd: map['preferred_end'] as String?,
      memo: map['memo'] as String? ?? '',
      createdAt: DateTime.parse(map['created_at']! as String),
      updatedAt: DateTime.parse(map['updated_at']! as String),
      lastUsedAt: _date(map['last_used_at']),
      deletedAt: _date(map['deleted_at']),
      horizonPoints: horizonPoints,
      blockedAzimuthRanges: blockedAzimuthRanges,
    );
  }

  static DateTime? _date(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  ObservationSite copyWith({
    String? id,
    String? name,
    String? address,
    bool clearAddress = false,
    double? latitude,
    double? longitude,
    int? bortle,
    bool clearBortle = false,
    double? sqm,
    bool clearSqm = false,
    String? brightnessGrade,
    bool? isFavorite,
    TrackingMode? trackingMode,
    String? defaultEquipmentId,
    bool clearDefaultEquipment = false,
    double? defaultMinAltitude,
    double? defaultMaxAltitude,
    bool clearDefaultMaxAltitude = false,
    String? preferredStart,
    bool clearPreferredStart = false,
    String? preferredEnd,
    bool clearPreferredEnd = false,
    String? memo,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastUsedAt,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
    List<HorizonPoint>? horizonPoints,
    List<BlockedAzimuthRange>? blockedAzimuthRanges,
  }) {
    return ObservationSite(
      id: id ?? this.id,
      name: name ?? this.name,
      address: clearAddress ? null : (address ?? this.address),
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      bortle: clearBortle ? null : (bortle ?? this.bortle),
      sqm: clearSqm ? null : (sqm ?? this.sqm),
      brightnessGrade: brightnessGrade ?? this.brightnessGrade,
      isFavorite: isFavorite ?? this.isFavorite,
      trackingMode: trackingMode ?? this.trackingMode,
      defaultEquipmentId: clearDefaultEquipment
          ? null
          : (defaultEquipmentId ?? this.defaultEquipmentId),
      defaultMinAltitude: defaultMinAltitude ?? this.defaultMinAltitude,
      defaultMaxAltitude: clearDefaultMaxAltitude
          ? null
          : (defaultMaxAltitude ?? this.defaultMaxAltitude),
      preferredStart: clearPreferredStart
          ? null
          : (preferredStart ?? this.preferredStart),
      preferredEnd: clearPreferredEnd
          ? null
          : (preferredEnd ?? this.preferredEnd),
      memo: memo ?? this.memo,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
      horizonPoints: horizonPoints ?? this.horizonPoints,
      blockedAzimuthRanges: blockedAzimuthRanges ?? this.blockedAzimuthRanges,
    );
  }
}

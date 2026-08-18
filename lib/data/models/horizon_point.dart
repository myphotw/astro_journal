enum HorizonDataSource {
  manual('manual'),
  cameraScan('camera_scan'),
  photoImport('photo_import'),
  videoImport('video_import');

  const HorizonDataSource(this.storageValue);

  final String storageValue;

  static HorizonDataSource fromStorageValue(String? value) {
    return HorizonDataSource.values.firstWhere(
      (source) => source.storageValue == value,
      orElse: () => HorizonDataSource.manual,
    );
  }
}

class HorizonPoint {
  const HorizonPoint({
    required this.id,
    required this.observationSiteId,
    required this.azimuth,
    required this.minAltitude,
    this.maxAltitude,
    this.sortOrder = 0,
    this.source = HorizonDataSource.manual,
  });

  final String id;
  final String observationSiteId;
  final double azimuth;
  final double minAltitude;
  final double? maxAltitude;
  final int sortOrder;
  final HorizonDataSource source;

  Map<String, Object?> toMap() => {
    'id': id,
    'observation_site_id': observationSiteId,
    'azimuth': azimuth,
    'min_altitude': minAltitude,
    'max_altitude': maxAltitude,
    'sort_order': sortOrder,
    'source': source.storageValue,
  };

  factory HorizonPoint.fromMap(Map<String, Object?> map) => HorizonPoint(
    id: map['id']! as String,
    observationSiteId: map['observation_site_id']! as String,
    azimuth: (map['azimuth']! as num).toDouble(),
    minAltitude: (map['min_altitude']! as num).toDouble(),
    maxAltitude: (map['max_altitude'] as num?)?.toDouble(),
    sortOrder: map['sort_order'] as int? ?? 0,
    source: HorizonDataSource.fromStorageValue(map['source'] as String?),
  );

  HorizonPoint copyWith({
    String? id,
    String? observationSiteId,
    double? azimuth,
    double? minAltitude,
    double? maxAltitude,
    bool clearMaxAltitude = false,
    int? sortOrder,
    HorizonDataSource? source,
  }) {
    return HorizonPoint(
      id: id ?? this.id,
      observationSiteId: observationSiteId ?? this.observationSiteId,
      azimuth: azimuth ?? this.azimuth,
      minAltitude: minAltitude ?? this.minAltitude,
      maxAltitude: clearMaxAltitude ? null : (maxAltitude ?? this.maxAltitude),
      sortOrder: sortOrder ?? this.sortOrder,
      source: source ?? this.source,
    );
  }
}

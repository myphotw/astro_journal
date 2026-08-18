import 'horizon_point.dart';

class BlockedAzimuthRange {
  const BlockedAzimuthRange({
    required this.id,
    required this.observationSiteId,
    required this.startAzimuth,
    required this.endAzimuth,
    this.reason,
    this.source = HorizonDataSource.manual,
  });

  final String id;
  final String observationSiteId;
  final double startAzimuth;
  final double endAzimuth;
  final String? reason;
  final HorizonDataSource source;

  /// Circular ranges are intentional: 350 -> 20 crosses north.
  bool contains(double azimuth) {
    final normalized = azimuth % 360;
    if (startAzimuth <= endAzimuth) {
      return normalized >= startAzimuth && normalized <= endAzimuth;
    }
    return normalized >= startAzimuth || normalized <= endAzimuth;
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'observation_site_id': observationSiteId,
    'start_azimuth': startAzimuth,
    'end_azimuth': endAzimuth,
    'reason': reason,
    'source': source.storageValue,
  };

  factory BlockedAzimuthRange.fromMap(Map<String, Object?> map) =>
      BlockedAzimuthRange(
        id: map['id']! as String,
        observationSiteId: map['observation_site_id']! as String,
        startAzimuth: (map['start_azimuth']! as num).toDouble(),
        endAzimuth: (map['end_azimuth']! as num).toDouble(),
        reason: map['reason'] as String?,
        source: HorizonDataSource.fromStorageValue(map['source'] as String?),
      );
}

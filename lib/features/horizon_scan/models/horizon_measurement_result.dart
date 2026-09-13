import '../../../data/models/blocked_azimuth_range.dart';
import '../../../data/models/horizon_point.dart';

enum HorizonMeasurementMode { limited, fullSky }

class HorizonBoundaryMeasurement {
  const HorizonBoundaryMeasurement({
    required this.azimuth,
    required this.altitude,
  });

  final double azimuth;
  final double altitude;
}

class HorizonMeasurementResult {
  const HorizonMeasurementResult({
    required this.mode,
    required this.points,
    required this.blockedRanges,
    required this.leftMeasurements,
    required this.rightMeasurements,
    required this.upperMeasurements,
    required this.lowerMeasurements,
    this.startAzimuth,
    this.endAzimuth,
  });

  final HorizonMeasurementMode mode;
  final List<HorizonPoint> points;
  final List<BlockedAzimuthRange> blockedRanges;
  final List<HorizonBoundaryMeasurement> leftMeasurements;
  final List<HorizonBoundaryMeasurement> rightMeasurements;
  final List<HorizonBoundaryMeasurement> upperMeasurements;
  final List<HorizonBoundaryMeasurement> lowerMeasurements;
  final double? startAzimuth;
  final double? endAzimuth;

  bool get hasUpperBoundary => upperMeasurements.isNotEmpty;
  bool get hasLowerBoundary => lowerMeasurements.isNotEmpty;
}

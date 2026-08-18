import 'dart:typed_data';

enum HorizonSensorAccuracy { good, medium, low, unknown }

class OrientationSample {
  const OrientationSample({
    required this.sampledAt,
    required this.sensorTimestampNanos,
    required this.azimuth,
    required this.pitch,
    required this.roll,
    this.accuracy = HorizonSensorAccuracy.unknown,
    this.trueNorthApplied = false,
  });

  final DateTime sampledAt;
  final int sensorTimestampNanos;
  final double azimuth;
  final double pitch;
  final double roll;
  final HorizonSensorAccuracy accuracy;
  final bool trueNorthApplied;
}

class HorizonFrameReference {
  HorizonFrameReference({
    required this.capturedAt,
    required this.width,
    required this.height,
    required this.lumaBytes,
  });

  final DateTime capturedAt;
  final int width;
  final int height;
  final Uint8List lumaBytes;

  void clear() => lumaBytes.fillRange(0, lumaBytes.length, 0);
}

class HorizonScanSample {
  const HorizonScanSample({
    required this.timestamp,
    required this.sensorTimestampNanos,
    required this.azimuth,
    required this.pitch,
    required this.roll,
    required this.coverageBin,
    required this.sensorAccuracy,
    required this.trueNorthApplied,
    this.frame,
  });

  final DateTime timestamp;
  final int sensorTimestampNanos;
  final double azimuth;
  final double pitch;
  final double roll;
  final int coverageBin;
  final HorizonSensorAccuracy sensorAccuracy;
  final bool trueNorthApplied;
  final HorizonFrameReference? frame;
}

import 'horizon_scan_sample.dart';

enum HorizonScanStatus {
  idle,
  initializing,
  scanning,
  paused,
  processing,
  completed,
  cancelled,
  error,
}

enum HorizonScanDirection { clockwise, counterClockwise }

enum HorizonSpeedGuide { steady, tooFast }

enum HorizonPitchGuide { level, tiltUp, tiltDown }

class HorizonScanCameraInformation {
  const HorizonScanCameraInformation({
    required this.cameraName,
    required this.previewWidth,
    required this.previewHeight,
    required this.sensorOrientation,
    required this.horizontalFov,
    required this.verticalFov,
    required this.intrinsicsSource,
    required this.intrinsicsConfidence,
  });

  final String cameraName;
  final int previewWidth;
  final int previewHeight;
  final int sensorOrientation;
  final double horizontalFov;
  final double verticalFov;
  final String intrinsicsSource;
  final String intrinsicsConfidence;
}

class HorizonScanSession {
  HorizonScanSession({
    required this.id,
    required this.observationSiteId,
    required this.startedAt,
    this.status = HorizonScanStatus.idle,
  });

  final String id;
  final String observationSiteId;
  final DateTime startedAt;
  DateTime? completedAt;
  HorizonScanCameraInformation? cameraInformation;
  double? startAzimuth;
  double? currentAzimuth;
  double cumulativeRotation = 0;
  HorizonScanDirection? direction;
  HorizonScanStatus status;
  final Set<int> coveredBins = <int>{};
  final List<HorizonScanSample> samples = <HorizonScanSample>[];
  final List<String> qualityWarnings = <String>[];
  double currentSpeed = 0;
  double averageSpeed = 0;
  HorizonSpeedGuide speedGuide = HorizonSpeedGuide.steady;
  HorizonPitchGuide pitchGuide = HorizonPitchGuide.level;

  int get sampleCount => samples.length;

  double coverageFraction(int totalBins) =>
      totalBins == 0 ? 0 : coveredBins.length / totalBins;

  List<int> missingBins(int totalBins) => [
    for (var bin = 0; bin < totalBins; bin++)
      if (!coveredBins.contains(bin)) bin,
  ];

  void addWarning(String warning) {
    if (!qualityWarnings.contains(warning)) qualityWarnings.add(warning);
  }

  void clearFrames() {
    for (final sample in samples) {
      sample.frame?.clear();
    }
    samples.clear();
    coveredBins.clear();
  }
}

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';

import '../models/horizon_scan_sample.dart';
import '../models/horizon_scan_session.dart';

class HorizonScanSampler {
  HorizonScanSampler(this.session);

  static const double binSizeDegrees = 5;
  static const int totalBins = 72;
  static const double minimumCoverage = 0.90;
  static const double minimumRotation = 330;
  static const double startHeadingTolerance = 15;
  static const double directionDetectionDegrees = 10;
  static const double tooFastDegreesPerSecond = 25;
  static const double pitchToleranceDegrees = 15;

  final HorizonScanSession session;
  double? _lastAzimuth;
  int? _lastTimestampNanos;
  double _signedRotation = 0;
  double _absoluteRotation = 0;
  int? _firstTimestampNanos;

  static double normalizeAzimuth(double value) {
    final normalized = value % 360;
    return normalized < 0 ? normalized + 360 : normalized;
  }

  static double unwrapDelta(double previous, double current) =>
      ((current - previous + 540) % 360) - 180;

  static double angularDistance(double first, double second) =>
      unwrapDelta(first, second).abs();

  int binFor(double azimuth) =>
      (normalizeAzimuth(azimuth) / binSizeDegrees).floor() % totalBins;

  bool needsSample(double azimuth) =>
      !session.coveredBins.contains(binFor(azimuth));

  void updateOrientation(OrientationSample sample) {
    final azimuth = normalizeAzimuth(sample.azimuth);
    session.startAzimuth ??= azimuth;
    session.currentAzimuth = azimuth;
    _firstTimestampNanos ??= sample.sensorTimestampNanos;

    final previous = _lastAzimuth;
    final previousTimestamp = _lastTimestampNanos;
    if (previous != null && previousTimestamp != null) {
      final delta = unwrapDelta(previous, azimuth);
      final elapsedSeconds =
          (sample.sensorTimestampNanos - previousTimestamp) / 1000000000;
      _signedRotation += delta;
      _absoluteRotation += delta.abs();
      session.cumulativeRotation = _signedRotation.abs();
      if (elapsedSeconds > 0) {
        session.currentSpeed = delta.abs() / elapsedSeconds;
      }
      final totalSeconds =
          (sample.sensorTimestampNanos - _firstTimestampNanos!) / 1000000000;
      if (totalSeconds > 0) {
        session.averageSpeed = _absoluteRotation / totalSeconds;
      }
    }

    if (session.direction == null &&
        _signedRotation.abs() >= directionDetectionDegrees) {
      session.direction = _signedRotation >= 0
          ? HorizonScanDirection.clockwise
          : HorizonScanDirection.counterClockwise;
    }
    session.speedGuide = session.currentSpeed >= tooFastDegreesPerSecond
        ? HorizonSpeedGuide.tooFast
        : HorizonSpeedGuide.steady;
    session.pitchGuide = switch (sample.pitch) {
      > pitchToleranceDegrees => HorizonPitchGuide.tiltDown,
      < -pitchToleranceDegrees => HorizonPitchGuide.tiltUp,
      _ => HorizonPitchGuide.level,
    };
    if (sample.accuracy == HorizonSensorAccuracy.low) {
      session.addWarning('방향 센서 정확도가 낮습니다.');
    }
    if (!sample.trueNorthApplied) {
      session.addWarning('GPS 보정 없이 자북 기준으로 측정했습니다.');
    }
    _lastAzimuth = azimuth;
    _lastTimestampNanos = sample.sensorTimestampNanos;
  }

  bool recordSample(
    OrientationSample orientation, {
    HorizonFrameReference? frame,
  }) {
    final bin = binFor(orientation.azimuth);
    if (!session.coveredBins.add(bin)) {
      frame?.clear();
      return false;
    }
    session.samples.add(
      HorizonScanSample(
        timestamp: orientation.sampledAt,
        sensorTimestampNanos: orientation.sensorTimestampNanos,
        azimuth: normalizeAzimuth(orientation.azimuth),
        pitch: orientation.pitch,
        roll: orientation.roll,
        coverageBin: bin,
        sensorAccuracy: orientation.accuracy,
        trueNorthApplied: orientation.trueNorthApplied,
        frame: frame,
      ),
    );
    if (isComplete) {
      session.status = HorizonScanStatus.completed;
      session.completedAt ??= DateTime.now();
      if (session.coveredBins.length < totalBins) {
        session.addWarning('일부 방향의 측정값이 부족합니다.');
      }
    }
    return true;
  }

  bool get isComplete {
    final start = session.startAzimuth;
    final current = session.currentAzimuth;
    if (start == null || current == null) return false;
    return session.coverageFraction(totalBins) >= minimumCoverage &&
        session.cumulativeRotation >= minimumRotation &&
        angularDistance(start, current) <= startHeadingTolerance;
  }

  static HorizonFrameReference downsampleLuma(
    CameraImage image, {
    int targetWidth = 256,
    int targetHeight = 144,
  }) {
    if (image.planes.isEmpty) {
      throw StateError('카메라 프레임에 이미지 plane이 없습니다.');
    }
    final plane = image.planes.first;
    final output = Uint8List(targetWidth * targetHeight);
    final pixelStride = plane.bytesPerPixel ?? 1;
    for (var y = 0; y < targetHeight; y++) {
      final sourceY = math.min(
        image.height - 1,
        y * image.height ~/ targetHeight,
      );
      final rowOffset = sourceY * plane.bytesPerRow;
      for (var x = 0; x < targetWidth; x++) {
        final sourceX = math.min(
          image.width - 1,
          x * image.width ~/ targetWidth,
        );
        final sourceIndex = rowOffset + sourceX * pixelStride;
        if (sourceIndex < plane.bytes.length) {
          output[y * targetWidth + x] = plane.bytes[sourceIndex];
        }
      }
    }
    return HorizonFrameReference(
      capturedAt: DateTime.now(),
      width: targetWidth,
      height: targetHeight,
      lumaBytes: output,
    );
  }
}
